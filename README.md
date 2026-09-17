# LinkPure (Swift)

LinkPure 的 **native Apple 平台实现**：macOS 菜单栏应用 + iOS（AppIntent）。

规则引擎抽成 `LinkPureCore` Swift Package —— 与 Flutter 版、以及未来的 Android 版
共享**同一份规则库与同一套行为规范**。

## 为什么这样组织

核心逻辑（规则引擎 + 1061 条规则）是唯一的资产；平台集成才是各端差异所在。
所以策略是：

> **共享真相（规则数据 + conformance 向量），而不是共享运行时（代码）。**

`LinkPureCore` 只有约 250 行，但被 **1053 条语言无关向量**验证过——这些向量同时也在
Dart（参考实现）与 Rust（独立实现）上跑过。

## 结构

```
linkpure/
├── Package.swift                     # LinkPureCore
├── Sources/LinkPureCore/
│   ├── Rule.swift                    数据契约（与 shared-rules.json 对应）
│   ├── LocalRule.swift               用户规则 + 导入/导出交换格式
│   ├── UrlCleaner.swift              规则引擎（行为契约见 conformance/README.md）
│   ├── RulesManager.swift            加载内置规则库 + 默认重定向跟随
│   └── Resources/shared-rules.json   vendored 规则库
├── Tests/LinkPureCoreTests/          1053 条一致性向量
├── Apps/Shared/                      两个平台共用
│   ├── AppModel.swift                规则状态 + 测试（macOS 额外带剪贴板监听）
│   ├── RuleStore.swift               用户规则持久化
│   ├── RuleEditorView.swift          规则编辑（macOS sheet / iOS Form）
│   ├── JSONDocument.swift            导入导出用
│   └── CleanURLTextIntent.swift      ★ 给 Shortcut 用的纯函数 AppIntent
├── Apps/macOS/                       菜单栏应用（MenuBarExtra + 窗口）
│   ├── MainWindowView.swift          NavigationSplitView + Table 的规则管理窗口
│   ├── SettingsView.swift            设置（⌘,）
│   └── LinkPureApp.swift             Scene / 菜单命令（FocusedValues）
├── Apps/iOS/                         规则管理 + 使用方式引导
├── Scripts/sync-spec.sh              从 Flutter 仓库同步规则库与向量
└── project.yml                       XcodeGen（macOS / iOS）
```

## 两个平台的能力差异（重要）

| | macOS | iOS |
|---|---|---|
| 自动改写（零操作） | ✅ 后台轮询 `NSPasteboard` | ❌ **系统不允许** |
| 用户需要做什么 | 什么都不用做 | 配置一次快捷指令，之后手动触发 |
| 入口 | 菜单栏常驻 | 控制中心 / 轻点背面 / Siri |
| 集成方式 | 剪贴板监听 | `CleanURLTextIntent` + Shortcut |

### iOS 的形态是**实测逼出来的**，不是选出来的

1. **`ControlWidget`（控制中心控件）不可行。**
   后台执行时 `UIPasteboard.general` 不是“被拒绝”，而是**另一块空的 pasteboard**：
   `numberOfItems == 0`，`detectedValues` 直接抛 `PBErrorDomain Code=4`。
2. **`AppShortcutsProvider` 也救不了。**
   App Shortcut 只能包装你自己的一个 intent，**装不下 `Get Clipboard` 这种系统动作**；
   而 intent 自己在后台又读不到剪贴板。
3. **唯一可行**：让 **Shortcuts 自己去读**，把字符串当参数传进来——
   因此 `CleanURLTextIntent` 是纯字符串进/出，**完全不碰剪贴板**，
   也就能做到**不弹「允许粘贴」提示**。

对应的工作流（App 内的「使用方式」页有逐步引导）：

```
获取剪贴板（系统读） → Clean URL Text（本 App） → [结果有变化才] 拷贝到剪贴板（系统写）+ 通知
```

写回（「拷贝到剪贴板」）必须包在这个 `If` **里面**，而不是放在它外面：
iOS 写剪贴板**没有内容去重**，结果一样也照写会白白触发 Universal Clipboard 同步、
把复制的富文本压成纯文本。`Clean URL Text` 本身没有副作用，风险全在这个写回动作的位置。
macOS 端挡这件事的是同一套判断（`ClipboardMonitor` 里的 `rewritten != text`）。

## 构建与测试

```bash
# 规则引擎：跑 1053 条一致性向量
swift test

# 同步规则库与向量（唯一来源是 Flutter 仓库）
./Scripts/sync-spec.sh ~/code/flutter/LinkPure

# macOS app
xcodegen generate
xcodebuild -project LinkPure.xcodeproj -scheme LinkPureMac -destination 'platform=macOS' build

# iOS app
xcodebuild -project LinkPure.xcodeproj -scheme LinkPureIOS \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## 实现要点（几处容易踩的坑）

1. **`\d` / `\w` 必须按 ASCII 解释。** Swift 走的 ICU 默认是 Unicode 语义，
   而规范要求 ASCII（与 Dart/JS 一致）。`UrlCleaner.asciiRewrite()` 把它们改写成
   显式字符类 `[0-9]` / `[0-9A-Za-z_]`。Rust 侧也踩过同一个坑。
2. **规则匹配大小写不敏感**（`NSRegularExpression.Options.caseInsensitive`），
   与 Redirector 一致；但**参数名匹配区分大小写**。
3. **参数移除按原始 query 串处理**，不走 `URLComponents` 往返：
   否则会折叠重复参数、重编码参数值、省略默认端口。
4. **参数名先精确匹配再试正则**：Branch 风格的 `$3p` / `$deep_link` 字面上含 `$`，
   当正则会因 `$` 是行尾锚点而永久失效。
5. **`followRedirect` 用注入的 `RedirectFollower`**，网络调用不进 golden 向量。
6. **改 app 名不能只改 `CFBundleDisplayName`。**
   `PRODUCT_NAME` 默认取 `$(TARGET_NAME)`，会连带决定 **`.app` 文件名**、
   `CFBundleName`、`CFBundleExecutable`；而 `CFBundleDisplayName` **只覆盖
   Finder / 主屏**的显示名。曾经的表现：

   | 场景 | 实际用的键 | 错误显示 |
   |---|---|---|
   | Finder / iOS 主屏 | `CFBundleDisplayName` | ✅ LinkPure |
   | **系统设置 → 登录项** | **`.app` 文件名** | ❌ LinkPureMac.app |
   | iOS 权限弹窗 / 设置 | `CFBundleName` | ❌ LinkPureIOS |
   | 进程名 | `CFBundleExecutable` | ❌ LinkPureMac |

   所以两个 target 都必须显式 `PRODUCT_NAME: LinkPure`。
   > 注：已经注册过的登录项，其显示名是 BTM 数据库里**注册时缓存**的，
   > 改名后即使 unregister → `lsregister -f` → register 也不会刷新；
   > 全新安装不会有这个问题。
7. **菜单栏图标不要用 `NSApp.applicationIconImage`。**
   那是 **Finder 渲染版**（系统在外层加了一圈圆角底板），实际图形会小约 30%
   （实测 11.5pt vs 其他图标的 17.5pt）。应该从原始 artwork 裁掉透明留白后
   生成菜单栏专用图（`MenuBarIcon.imageset`）。
   > 排查时还踩到一个坑：Xcode 调试器启的实例会一直在跑旧二进制，
   > 改动看不到效果——要先把 `debugserver` 一起清掉。
8. **UI 的“测试结果”要把规则集版本号算进 `task(id:)`。**
   只写 `.task(id: testURL)` 的话，切换规则启用/禁用时 URL 没变，
   结果不会重算，会一直显示陈旧的。

前 5 条在 `Tests/LinkPureCoreTests/Vectors/` 里有对应向量守护；
6–8 是 UI/工程层面的，靠文档与代码注释约束。

## macOS 应用

- 菜单栏常驻（`LSUIElement`，无 Dock 图标）
- 轮询 `NSPasteboard.changeCount` 监听剪贴板（macOS 允许后台读取，
  所以桌面端能做到真正的「零操作自动改写」）
- 改写后写回剪贴板 + 系统通知（3 秒后自动收起）
- 规则列表（搜索 / 单条开关）、URL 测试、新增用户规则、导入导出
- 开机自启：`SMAppService.mainApp`（macOS 13+），入口在主窗口侧边栏底部和状态栏菜单（⌘, 也可）
- 最低版本 **macOS 15**：唯一原因是 `Scene.defaultLaunchBehavior(.suppressed)`
  （用来做到“启动不弹主窗口”），它 `@available(macOS 15.0, *)`
- **App Sandbox 已开启**（上架 Mac App Store 的硬性要求）

### 窗口 UI：布局交给系统容器

主窗口刻意**不**用 `VStack` 自己摆一个工具栏 + 分隔线堆叠的布局，而是把每个意图交给
对应的系统容器，由它去决定位置、尺寸和交互：

| 意图 | 容器 | 白拿到的行为 |
|---|---|---|
| 切「我的规则 / 内置规则库」 | `NavigationSplitView` sidebar | 活的半透明材质、系统列宽、`⌃⌘S` 折叠 |
| 搜索 | `.searchable` | 搜索框进工具栏、`⌘F`、`Esc` 清空、焦点环 |
| 新增 / 导入 / 导出 | `ToolbarItemGroup` | 高度、间距、hover、窗口变窄时的溢出折叠 |
| 状态 | `.navigationSubtitle` | 进标题栏副标题 |
| 1061 条内置规则 | `Table` | 点列头排序、拖列宽、自动虚拟化 |
| 开机自启 | `Settings` scene | 设置窗口 |
| 菜单 / 快捷键 | `.commands` + `FocusedValues` | `⌘N` / `⌘I` / `⌘E`，窗口不在时自动置灰 |

四个实测踩到的坑（都已在代码里注释）：

1. **`.commands` 必须挂在 `Window` 场景上。** 挂到 `Settings` 场景上，菜单项就只在
   设置窗口活动时才存在——按 `⌘N` 什么都不发生。
2. **`Settings` 场景不会给 `LSUIElement` app 自动装「设置…」菜单项。** 环境里的
   `openSettings()` 是好的（窗口能正常开），但菜单栏里没这一项、`⌘,` 按下去无反应。
   要用 `CommandGroup(replacing: .appSettings) { SettingsLink { … } }` 自己接一下。
3. **`ContentUnavailableView` 不会自己撑满**，它是按内容取尺寸的。空状态直接放进
   detail 列的话，整列（测试条 + 空状态 + 状态栏）会变成一个"内容大小的块"，
   被 `NavigationSplitView` 在中间居中——上下各留一大片空白。要显式
   `.frame(maxWidth: .infinity, maxHeight: .infinity)`。有数据时那位置是 `List`，
   天然撑满，所以只有空状态看得出来。
4. **设置入口不能只放在状态栏菜单里。** 这是个菜单栏 app，用户习惯去点状态栏图标；
   主窗口开着的时候，设置就该在窗口里点得到（侧边栏底部，macOS 上放应用级控件的位置）。

### iOS 窗口 UI：约定和 macOS 相反

同一套数据模型，但两个平台的"原生"不是同一套东西：

| | macOS | iOS |
|---|---|---|
| 次要信息（如规则 id） | `.help()` 悬停提示 | **长按菜单**（`.help()` 在 iPhone 上是死的） |
| 进详情 | 行内铅笔按钮 / 右键菜单 | **点整行**（只有 swipe 等于藏起来，没人会去试） |
| 长列表 | 要自己截断/虚拟化 | `List` 本身就是懒的，**不要**截断 |
| 空状态 | `ContentUnavailableView` 铺满 | 同一个组件，但要把 `listRowBackground` 清掉 |
| 操作结果提示 | 底部状态栏 | **必须 `.alert`**（内置规则库有 1061 行，提示塞进列表末尾等于看不见） |
| 删除 | 行内垃圾桶 → **立即删** + 状态栏 8 秒「撤销」 | 滑动 → **立即删** + 底部 6 秒撤销条 |

两边都不二次确认：

- **macOS**：confirm 是留给"撤销不了"的操作的（Safari 清历史、关闭未保存的文稿），
  而删一条规则就是一次数组插入就能恢复的事。Finder / Xcode / Mail / 备忘录
  删东西也都不问。
- **iOS**：滑动删除本来就不二次确认（邮件 / 提醒事项 / 信息 / 文件 都不问），
  iOS 对误删的答案是**撤销**而不是确认——确认只对"手滑"有用，对"点错了"没用。
- iOS 上还有个副作用：`.swipeActions` 里的 `Button(role: .destructive)` 会让
  SwiftUI **乐观地**把整行划走（它假设这行马上要消失），确认期间数据没变，
  List 重画时行又回来了——就是那个"先消失再加回来"。

**刻意不接 `UndoManager`**（不注册撤销、不集成「编辑 > 撤销」）：
那套东西要维护的不变量不少（撤销/重做两个方向必须互相注册、分组跟 `groupsByEvent`
的交互、反向操作时的下标漂移），而它换来的只是 "⌘Z" 一种入口——
恰好又是**最没有可发现性**的那一种。这里用一个可见的提示条，
`UndoManager` 完全不碰。macOS 侧的唯一额外代价是那 8 秒里状态栏的
「撤销」按钮带 `.keyboardShortcut("z")`；提示条消失后快捷键也跟着没了，
不会抢文本框自己的 ⌘Z。

撤销必须把规则插回**原来的下标**：规则集是有序的，顺序会影响命中结果。

行的排版：正则占两行（一行里不管怎么截都看不出是哪条），替换目标占一行且**从中间截**
（`https://addons.mozilla.org/en-US/…addon/$1/` 两头都在）。单个开关放尾端，
跟「设置」一致；放前面会跟正文抢左边缘，一列文字参差不齐。

### 关于沙盒

已经实测：**沙盒不影响剪贴板轮询**（Flutter 版就是沙盒的）。entitlements 只需：

```xml
com.apple.security.app-sandbox                        = true
com.apple.security.network.client                     = true   <!-- followRedirect -->
com.apple.security.files.user-selected.read-write     = true   <!-- 导入导出 -->
```

副作用：沙盒下读不到别的 app 的 preferences，所以规则迁移里「扫 plist 文件」
那两步会被拒（自动退化为只查 `UserDefaults`）。这恰好是正确的——
真实升级场景里原生版与 Flutter 版**共用 bundle id，共享同一个容器**。

> 启用沙盒会把规则文件从 `~/Library/Application Support/` 换到
> `~/Library/Containers/<bundleID>/Data/Library/Application Support/`，
> 开发期已有数据会变得读不到。

## 数据与存储

### 规则存在文件里，不用 UserDefaults

```
~/Library/Application Support/LinkPure/rules.json
```

```json
{ "version": 1, "rules": [ { "rule": {...}, "enabled": true, "testUrl": "..." } ] }
```

**为什么不用 `UserDefaults`（踩过的坑）**：它是**按 bundle id 分域**的。
开发期只要换一次 bundle id，就等于换了一个全新的空库；升级/改名/多环境共存时也一样。
当时表现就是“规则每次打开都是空的”，而且**毫无痕迹**。
文件路径与 bundle id 无关，也更好备份、迁移、调试。

> 解码同时接受带 `version` 的对象和**裸数组**（历史上出现过的形状）。

### Flutter 版规则迁移

发布时原生版会**替换**App Store 上的 Flutter 版（同一 bundle id），
但两者的存储键不同：

| | 位置 |
|---|---|
| Flutter 版 | `UserDefaults` 键 `flutter.local_rules`（JSON **字符串**） |
| 原生版 | `Application Support/LinkPure/rules.json` |

所以首次启动时（本地规则文件不存在）会**自动迁入**旧数据，
来源按优先级依次尝试：

1. `UserDefaults.standard[flutter.local_rules]`
   —— 两个平台都适用；iOS 上共用 bundle id 时会共享容器，升级替换后直接命中
2. `~/Library/Preferences/<legacyID>.plist`（仅 macOS）
3. `~/Library/Containers/<legacyID>/Data/Library/Preferences/<legacyID>.plist`（仅 macOS）

`<legacyID>` 依次尝试 `com.rxliuli.linkpure2`、`com.rxliuli.linkpure`。
迁移是**幂等的**：本地文件一旦存在就走加载，不会重复迁。

Flutter 版的 `LocalRule` 形状（`{"rule":{...},"enabled":bool}`）与本仓库完全一致，
包括 `removeParams` 型规则（那种规则存得下、只是导不出）。

## 状态

| 部分 | 状态 |
|---|---|
| `LinkPureCore` | ✅ 1053/1053 向量通过 |
| macOS app | ✅ 可用（菜单栏常驻 / 剪贴板监听 / 改写写回 / 通知 / 规则管理 / 导入导出 / URL 测试 / 开机自启 / **沙盒已开**） |
| iOS app | ✅ 可用（规则管理 / 使用方式引导 / `CleanURLTextIntent` 已注册给 Shortcuts） |
| 多语言一致性 | ✅ Dart / Rust / Swift 三个实现零分歧 |

### 两个平台的已知欠账

**macOS**

- ~~App Sandbox 关闭~~ → ✅ 已开启并实测（剪贴板轮询不受影响）
- ~~无开机自启~~ → ✅ 已实现（`SMAppService`）
- 通知横幅需在干净环境验证（当前开发机的通知权限库已被反复重建弄脏）
- 无 Sparkle 更新
- 菜单栏图标用的是裁剪后的彩色 artwork；要做单色模板图需单独设计矢量稿

**iOS**

- ~~规则列表最多展示 300 条内置规则~~ → ✅ 已去掉（`List` 本来就是懒加载的，
  截断只会制造"搜不到但其实有"）
- 未做 App Store 相关配置（隐私清单、截图等）

## 发布注意

### bundle id（已定）

| 配置 | 两个平台 |
|---|---|
| Debug | `com.rxliuli.linkpure2.dev` |
| **Release** | **`com.rxliuli.linkpure2`** |

`com.rxliuli.linkpure2` 是 Flutter 版在 App Store 上的记录，
**iOS 与 macOS 共用同一个 bundle id（Universal Purchase）**。
原生版要作为更新替换上去，**必须复用它**：

- ✅ 复用 → 老用户能收到更新，保留评分 / 评论 / 下载量
- ❌ 不复用 → 变成两个独立 App，从零开始

注意 macOS 与 iOS 的 Release bundle id **必须相同**——这是 Universal Purchase 的硬性要求
（Apple 文档：“uses the same Apple ID (an app identifier), SKU, and bundle ID as the iOS app”）。

Debug 加 `.dev` 是为了能与 App Store 版共存，且避开开发机上被污染的通知权限记录。

### 分发前还缺

| 项 | 说明 |
|---|---|
| ~~macOS App Sandbox~~ | ✅ **已开启**（见「关于沙盒」）；上架 Mac App Store 的前提已满足 |
| ~~开机自启~~ | ✅ 已实现（`SMAppService`） |
| 分发签名 | 现在是 `Apple Development`；正式分发要用 `Apple Distribution` / `3rd Party Mac Developer Application` |
| iOS 上架材料 | 隐私清单、App Store 截图等 |
| 自动更新 | 未接 Sparkle |
| 迁移的真实场景验证 | 目前只在 dev bundle id 下验过；发布前应用 Release 配置 + 真正升级一次 Flutter 版再走一遍 |

## 与 Flutter 版的关系

Flutter 版仍是规则库与 conformance 向量的**唯一来源**（single source of truth）。
本仓库通过 `Scripts/sync-spec.sh` 做 vendored 拷贝，从而能自包含构建。

长期看，`Spec/`（规则库 + 向量）应该独立成一个仓库或 submodule，由各端共同引用。
