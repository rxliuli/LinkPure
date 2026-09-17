import AppIntents
import Foundation
import LinkPureCore

/// 用当前规则清洗一个 URL（不做任何有效性判断之外的处理）。
enum RuleEngine {
    static func currentRules() -> [Rule] {
        let user = RuleStore.loadUserRules().filter(\.enabled).map(\.rule)
        let shared = (try? RulesManager.loadBundledRules(includeRedirects: true)) ?? []
        return user + shared
    }

    /// 返回清洗结果；无规则命中时原样返回。
    static func clean(_ url: String) async -> String {
        guard UrlCleaner.isValidUrl(url) else { return url }
        let cleaner = UrlCleaner(rules: currentRules(), follower: URLSessionRedirectFollower())
        let result = await cleaner.check(url)
        return result.status == .matched ? result.url : url
    }
}

/// 给 Shortcut / Siri 用的**纯函数** intent：字符串进，字符串出。
///
/// ## 为什么是这个形态
///
/// 这形状不是随便定的，是实测逼出来的（见 LinkPure 仓库的 conformance 与探针工程）：
///
/// 1. **iOS 上任何后台上下文都读不到系统剪贴板。**
///    `ControlWidget` 里 `UIPasteboard.general` 不是"被拒绝"，而是**另一块空的 pasteboard**
///    （`numberOfItems == 0`，`detectedValues` 直接抛 `PBErrorDomain Code=4`）。
///    因此 ControlWidget 这条路是死的。
/// 2. **`AppShortcutsProvider` 也救不了**：App Shortcut 只能包装你自己的一个 intent，
///    **装不下 `Get Clipboard` 这种系统动作**；而 intent 自己在后台又读不到。
/// 3. 所以唯一可行的形态是：**让 Shortcuts 自己去读剪贴板**，把字符串当参数传进来。
///
/// 对应的工作流：
/// ```
/// 获取剪贴板（系统读） → Clean URL Text（本 intent） → 拷贝到剪贴板（系统写）
/// ```
/// 用户把它挂到控制中心 / 轻点背面 / Siri 即可。
///
/// 故意**不**推荐挂到锁定屏幕：这个工作流要读剪贴板，而锁屏态下的剪贴板
/// 本来就不可靠（iOS 会拦住后台静默读取），而且「锁着的手机也能跑一个会读
/// 剪贴板的动作」这个语义本身就不该鼓励。
struct CleanURLTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Clean URL Text"

    static var description = IntentDescription(
        "Receives a URL string and returns it with tracking parameters removed. Never reads or writes the clipboard."
    )

    /// 不要拉起 app —— 读/写剪贴板由 Shortcuts 负责。
    static var openAppWhenRun: Bool = false

    @Parameter(title: "URL", description: "The URL text to clean")
    var url: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: await RuleEngine.clean(url))
    }
}
