# LinkPure for Android

LinkPure 的 Android 原生实现（Kotlin / Gradle），与 `Apps/macOS`、`Apps/iOS` 并列。

## 为什么是这个目录

规则库和一致性向量是**跨语言的数据契约**，全仓库只存一份：

| 共享的东西 | 唯一来源 | Android 侧怎么用 |
|---|---|---|
| 规则库 | `Sources/LinkPureCore/Resources/shared-rules.json` | `core/build.gradle.kts` 用 `resources.srcDir(...)` 打进 classpath |
| 一致性向量 | `Tests/LinkPureCoreTests/Vectors/` | `syncVectors` 任务同步到 `build/vectors`，用系统属性告诉测试 |

**这里不放副本。** 跑 `Scripts/sync-spec.sh` 更新上游时，Swift 和 Android 两边一起更新。

## 结构

```
Apps/android/
├── settings.gradle.kts
├── gradle/libs.versions.toml
├── core/                             LinkPureCore 的 Kotlin 版（纯 JVM，不依赖 Android）
│   └── src/main/kotlin/com/rxliuli/linkpure/core/
│       ├── Rule.kt                   数据契约（与 shared-rules.json 对应）
│       ├── UrlCleaner.kt             规则引擎（行为契约见 conformance/README.md）
│       ├── PercentCodec.kt           两种 percent-decode（捕获组 vs query key，语义不同）
│       ├── LocalRule.kt              用户规则 + 导入导出交换格式
│       └── RulesManager.kt           加载内置规则库 + JSON 配置
└── app/                              Android app
    └── src/main/kotlin/com/rxliuli/linkpure/
        ├── ProcessTextActivity.kt    ★ 唯一入口，全程不 setContentView
        ├── clean/Cleaner.kt          清洗一次（本地快算优先，短链才联网）
        ├── clean/CleanNotifier.kt    通知：已清洗 / 本来就干净 / 不是 URL
        ├── clean/CopyActionReceiver.kt  通知上的「复制」
        ├── data/RuleStore.kt         文件存储 + Flutter 规则迁移
        ├── data/HttpRedirectFollower.kt  followRedirect 规则的逐跳跟随
        └── ui/                       Compose 规则管理 + 编辑器
```

`:core` 刻意做成**纯 JVM 模块**（不是 Android library）：1053 条向量几秒跑完，
而且引擎里不可能不小心用到 Android API。

## 界面：布局交给系统容器

这条规矩是 Swift 侧 README 里立下的，第一版 Android 界面违反了——用 `LazyColumn`
把「使用说明 + 测试框 + 两排按钮 + 列表」手工堆成一摞，结果说明占了四成屏幕、
真正的列表被挤到折叠线以下，看起来「主次不分」。现在是：

| 意图 | 容器 |
|---|---|
| 当前在哪一屏（列表 / 编辑 / 说明） | `AnimatedContent`（左右滑入 + 淡出） |
| 切「我的规则 / 内置规则库」 | `TabRow`（自带指示器与横向动画） |
| 搜索 | 顶栏的搜索图标 → 顶栏内输入框（自动聚焦） |
| 新建规则 | `FloatingActionButton` |
| 导入 / 导出 / 使用说明 / 关于 | 顶栏溢出菜单 |
| 删一条规则 | 列表里**滑动** |
| 一条规则的次要动作 | **不另开入口**：内置规则的文案可选中复制（`SelectionContainer`），用户规则的正则在编辑器里复制 |
| 操作反馈 | `Snackbar`（删除/导入后带 Undo） |
| 保存 / 取消 | 编辑器自带的 `TopAppBar`（Save 在右上） |
| 测试结果 | 编辑器里的**重写链**（与 Swift 侧 `RuleTestResultView` 对齐） |

三个刻意做的决定：

1. **同一个动作只在一个地方**。删除只在列表里滑动做——行内不再放删除按钮，
   编辑器里也不再放一个。启用开关同理，只在列表行尾。
2. **使用说明单独成页**，不铺在主界面当卡片。
3. **搜索跨两个列表**，并藏掉 tab。用户点搜索时脑子里是「找一条规则」，
   而不是「在当前这个列表里找」——在「我的规则」里搜 `youtube` 却提示「没有匹配」，
   而内置库里明明有一堆，那是蠢的。
4. **导入固定合并，不弹选择**。macOS 与 iOS 都是写死 `merge: true`
   （`MainWindowView.swift:686` / `IOSRulesView.swift:470`），第一版我在 Android 上
   多造了一个「Merge / Replace」对话框——三个等重按钮，让用户做一个本来不需要做的决定。
   想替换就先删掉再导，而且合并永远不破坏已有数据、还有撤销兜底。
5. **每一屏的 app bar 都画在 `AnimatedContent` 里面**，不能挂在 `Scaffold.topBar` 上。
   编辑器那一屏的 topBar 是空的（它自带 app bar），挂在 Scaffold 上会让 padding
   在切换时从「两行标题的顶栏」跳到 0——**横向滑动的同时整个页面向上一顶**，看着很怪。
6. **撤销条是 6 秒，不是 Material 的 `Long`（10 秒）**。iOS 用 6 秒
   （`IOSRulesView.swift`），macOS 8 秒（`MainWindowView.swift`）；Material 只给了
   Short(4s) / Long(10s)，所以用 `Indefinite` + 自己 `delay(6000)` 收起。
   连删两条时记得把上一条的计时器取消，否则前一个计时器会把新那条提前收起。
7. **编辑器的预览要跑两遍**：先用同步的 `checkLocally` 把第一帧画出来（不闪），
   再用异步的 `check` 覆盖一次。**异步那遍不能省**——`checkLocally` 不配 follower，
   所以命中 `followRedirect` 规则时它只能给出「没有匹配」而不是展开后的 URL。
   iOS 的 `RuleEditorView` 也是这个两步（预先同步算 + `.task` 里 `await check`）。
   异步那遍加了 250ms 防抖，不然打字时每个键都会去联网。
8. **没有长按菜单**。曾经有一个（照 iOS 抄的：Edit / Enable-Disable / Copy rule ID /
   Copy regular expression / Delete），但 5 项里有 3 项与「点整行 / 尾部开关 / 滑动」重复。
   没有多选的移动端，长按菜单只是重复动作的集散地——macOS 那边是
   `contextMenu(forSelectionType:)`，作用于**选中集**，那才是名副其实的上下文菜单。
   内置规则的文案改用 `SelectionContainer`，直接走系统原生的选中/复制。

另外补了一个真 bug：编辑器里按系统返回键会直接退出 app（没有 `BackHandler`）。
现在只要不在列表页，返回键就退回列表。

### 测试结果要显示**重写链**，不能只给最终结果

写规则时真正要回答的问题是「**哪些规则按什么顺序依次命中了**」。只印一个最终结果时，
很容易误判成「我的规则没生效」——实际上往往是前面的内置规则先改掉了 URL，
你的规则在第二轮才匹配上。

例：规则 `^https://youtu\.be/(\w+)$`（带 `$` 锚点）+ 测试 URL `https://youtu.be/xxx?si=yyy`

```
Rewrite chain (2 steps)
  https://youtu.be/xxx                          ← si 已被前面的规则删掉
  https://www.youtube.com/watch?v=xxx            ← 第二轮你的规则才生效
```

`MatchResult.chain` 引擎一直在算（`check` / `checkLocally` 都返回它），`03-iteration.json`
的向量也盯着它——之前只是 UI 没展示。参考实现 Redirector 与 Swift 侧也都是这么做的。

## 跑

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"

./gradlew :core:test                # 1053 条一致性向量
./gradlew :app:assembleDebug        # Android app
```

期望输出：

```
ok   01-params.json  (10 cases, 0 failed)
...
TOTAL: 1053 cases, 0 failed
```

## 在模拟器/真机上试这个入口

```bash
P=com.rxliuli.linkpure.dev
adb install -r app/build/outputs/apk/debug/app-debug.apk
# 整个命令必须包在**一层引号**里：adb shell 会把参数拼成一条命令交给设备上的 sh，
# 不包的话 URL 里的 & 会被当成后台执行符，实际传进去的只剩 ? 前面那一段。
adb shell "am start -n $P/com.rxliuli.linkpure.ProcessTextActivity \
  --es android.intent.extra.PROCESS_TEXT 'https://example.com/?utm_source=x&id=1'"

adb shell dumpsys notification --noredact | grep -E "android.title=|android.text="
```

真正的原位替换要在浏览器地址栏里选中一段链接、走「处理文本」菜单才能看到
（`am start` 没有调用方，收不到 setResult）。

## 验 Flutter 规则迁移

迁移读的是 `shared_prefs/FlutterSharedPreferences.xml` 里的 `flutter.local_rules`，
而 debug 构建带 `.dev` 后缀、数据目录不同，**读不到**。所以要用真实包名跑：

```bash
./gradlew :app:assembleDebug -PrealPackage
```

## 移植时踩到的两处（都不在规范里，是语言差异）

1. **`\d` / `\w` / `\s` 不需要改写。** Java 的 `Pattern` 默认就是 ASCII 语义
   （`\d` = `[0-9]`、`\w` = `[a-zA-Z_0-9]`），所以 Swift 那边为了绕开 ICU 的 Unicode
   语义而写的 `asciiRewrite()` 在这里是多余的。`05-regex-flavor.json` 那 9 条向量盯着这件事。
2. **不能用 `java.net.URLDecoder`。** 它总是把 `+` 当空格，用在「捕获组」上会与
   Dart 的 `Uri.decodeComponent` 分歧（规范第 5 条明确要求捕获组**不**做 `+` → 空格）。
   见 `PercentCodec`。

## 形态（已由探针定案）

**只做 `ACTION_PROCESS_TEXT`，默认静默模式 + 通知。**

依据是 `~/code/kotlin/ClipboardAccessProbe` 的实测结论：

- Android 10+ **读不到后台剪贴板**，而且**连 `clipboardChanged` 事件都收不到**
  —— 所以 macOS 那种「零操作自动改写」在 Android 上原理上不可能
- `ACTION_PROCESS_TEXT` 的内容随 intent 进来，**完全不碰剪贴板**，因此绕开了全部限制
- 快捷设置磁贴 / 悬浮球 / 小组件：实测不行或已放弃，理由见探针仓库 README

## 用户规则只写「一个正则 + 一个替换目标」

`Rule` 有三个互斥字段（`regexSubstitution` / `removeParams` / `followRedirect`，
引擎优先级就是这个顺序），但**只有第一种是给用户编的**：

| 字段 | 内置规则库里的条数 | 用户能编吗 |
|---|---|---|
| `removeParams` | **978**（92%） | ❌ |
| `regexSubstitution` | 66 | ✅ |
| `followRedirect` | 13 | ❌ |

后面两种是**内置规则库用的机制**：引擎支持、列表里只读展示（「removes utm_x」），
但编辑器不碰。Flutter 参考实现就是这样（`rule_edit_page.dart` 里 `removeParams`
**零次出现**，git 历史里也从未有过编辑器相关的改动），iOS/macOS 的 `RuleEditorView`
同理（它的 `canSave` 要求替换目标非空，所以这类规则在那边是只读的）。

> 之所以不能在编辑器里开放 `removeParams`：**它永远导不出去**。交换格式只能表达
> from→to，`RuleExchange.export` 遇到这类规则只能跳过。让用户能造出一种导不走的东西，
> 本身就是个陷阱。
>
> 曾经 Android 版本自作主张加过一个「Replace URL / Remove params」模式切换，
> 后来删掉了——那是个功能发明，不是对齐。

## 通知的正文是**清洗后的 URL**，不是一句概括

```
LinkPure
URL cleaned
https://www.youtube.com/watch?v=dQw4w9WgXcQ      ← 正文
2 params removed                                  ← 展开才有的补充
[Copy]
```

用户要知道的就是「它变成了什么」。macOS 侧也是这么发的
（`NotificationService.post(title: "URL Rewritten", body: to)`），Flutter 侧同理。

曾经错过一次：正文发的是 `summary`（「URL rewritten」/「2 params removed」），
**URL 根本不在通知里**——而那个 `summary` 在 `removed == 0` 时还会回一句
「URL rewritten」，等于把 URL 重复一遍。现在 `summary` 只在真的去掉了参数时才非空，
而且只作为展开后的那一行。

## 上架前必须改的两处

1. **`versionCode` 必须大于 Flutter 版在 Play 上的当前值**（0.5.2 → 502）。
   现在是 `600`（与 Swift 侧 build 号对齐）。**改小了 Play 会直接拒。**
2. **签名密钥必须复用 Flutter 版的 `android/upload-keystore.jks`**（在
   `~/code/flutter/LinkPure/android/`）。Play 要求同一 package name 用同一 upload key，
   换了就永远无法更新，只能新开一个 app。

## CI 发布（release.yml 的 `android` job）

`./gradlew :app:bundleRelease :app:assembleRelease` → 校验 APK 签名 → 把 AAB 传给 Play，
AAB/APK 同时作为构建产物留下。

**签名**的四个 secret 已经在 `build-android` environment 里
（`ANDROID_KEYSTORE_BASE64` / `ANDROID_PASSWORD` 系列：`ANDROID_STORE_PASSWORD`、
`ANDROID_KEY_PASSWORD`、`ANDROID_KEY_ALIAS`），CI 用它们现写 `key.properties` 与
`upload-keystore.jks`——这两个文件都在 `.gitignore` 里，本机发布时自己放一份在
`Apps/android/` 下即可（`storeFile` 用相对模块根的路径）。

**Play 的发布凭据**是另一样东西，需要自己建一次：

1. Play Console → 设置 → API 访问权限 → 关联（或创建）一个 Google Cloud 项目
2. 在该 Cloud 项目里建服务账号，授予「Play 服务账号」角色；只发测试轨道要
   「发布到测试轨道」，要发 production 还要「管理生产版本与发布」
3. 下载该服务账号的 JSON 密钥
4. `gh secret set PLAY_SERVICE_ACCOUNT_JSON --env build-android < 下载的.json`

没配这一步时 job **不会红**：打印一条 warning 并在 Step Summary 里说明，
AAB/APK 照旧产出（其它渠道也互不影响）。配好之后每次发版自动上传。

默认发到 **internal** 轨道（秒级生效、不进审核）。要发正式版就
`gh workflow run release.yml -f play-track=production`。

## 还没做的

- **真机验证**：目前只在 API 37 模拟器上跑过
- **Swift 侧的导出行为需要对齐**：Kotlin 现在遇到 `removeParams` / `followRedirect` 型规则是
  **跳过 + 告诉用户跳了几条**（Flutter 参考实现也是跳过），而 `RuleExchange.export`
  在 Swift 侧是**抛异常**——结果就是「有一条删参数规则就整包导不出去」。建议对齐到跳过。

## 三个实测踩到的坑

1. **kotlinx.serialization 默认会省略等于默认值的字段**，导致写出的 `rules.json`
   里没有 `enabled` / `version`。而 Swift 的 `LocalRule` / `RuleFile` 里这两个属性
   非可选、无默认值，`Codable` 遇到缺键会**直接解码失败**——也就是
   「Kotlin 写出来的文件 Swift 读不了」。修法是 `LinkPureJson` 里开 `encodeDefaults = true`，
   `RuleExchangeTest.ruleFileAlwaysWritesVersionAndEnabled` 盯着这件事。
2. **`adb shell` 会把参数拼成一条命令交给设备上的 sh**，所以
   `--es android.intent.extra.PROCESS_TEXT 'https://…?a=1&b=2'` 里的 `&` 会被当成后台执行符，
   实际传进去的只剩 `?` 前面那一段。整个 `am start` 命令必须再包一层引号。
3. **`rememberSwipeToDismissBoxState` 内部是 `rememberSaveable`**，而 `LazyColumn` 会按
   item key 保存每一行的状态。于是「滑掉 → 删除 → 撤销恢复」时，同 key 的那一行会把
   **「已滑出」的位置一起恢复回来**：规则确实回来了，但看起来是坏的（内容滑到屏幕外，
   只剩背景色和 Delete）。

   修法是不用那个工厂函数，直接 `remember { SwipeToDismissBoxState(...) }`——构造器是公开的。
   不 saveable 就不会被恢复，重新插回来时总是从 `Settled` 开始。
