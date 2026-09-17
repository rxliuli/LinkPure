import Foundation
import LinkPureCore

#if os(macOS)
import AppKit
#endif

/// 应用状态（macOS / iOS 共用）。
///
/// 数据模型与 Flutter 版对齐：
///   `enabledRules = 启用中的用户规则 + 全部共享规则`（用户规则优先）
/// 共享规则库是**只读**的，不参与启用/禁用。
///
/// 平台差异只在初始化时体现：
///   - macOS：启动剪贴板监听（可后台读剪贴板 → 真正的"零操作自动改写"）
///   - iOS：**不监听**。系统不允许后台读剪贴板，自动改写在这个平台上不存在；
///     取而代之的是 `CleanURLTextIntent` + 快捷指令（见 ShortcutGuideView）。
///
/// 关于"监听开关"：**故意不提供**。macOS 上监听本来就该常驻，
/// 不想用直接退出 app 即可——多一个暂停态只会制造"怎么不生效了"的隐性故障。
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sharedRules: [Rule] = []
    @Published private(set) var userRules: [LocalRule] = []
    @Published private(set) var loadError: String?
    @Published var lastRewritten: (from: String, to: String)?
    @Published var rewriteCount = 0
    /// 规则集版本号：任何改动（启用/禁用、增删、导入）都会 +1。
    ///
    /// UI 的“测试”靠它触发重算——否则改了规则开关，已显示的结果会变成陈旧的（实际踩到过）。
    @Published private(set) var rulesetRevision = 0

    #if os(macOS)
    private let monitor = ClipboardMonitor()
    #endif

    var enabledRules: [Rule] {
        userRules.filter(\.enabled).map(\.rule) + sharedRules
    }

    var enabledUserRuleCount: Int { userRules.filter(\.enabled).count }

    init() {
        do {
            sharedRules = try RulesManager.loadBundledRules(includeRedirects: true)
        } catch {
            // 会直接显示在 UI 里（空状态那一行），所以是面向用户的文案。
            loadError = String(localized: "Could not load the rule library: \(error.localizedDescription)")
        }
        userRules = RuleStore.loadUserRules()

        #if os(macOS)
        monitor.handler = { [weak self] text in
            guard let self, UrlCleaner.isValidUrl(text) else { return nil }
            let cleaner = UrlCleaner(rules: self.enabledRules, follower: URLSessionRedirectFollower())
            let result = await cleaner.check(text)
            guard result.status == .matched, result.url != text else { return nil }
            return result.url
        }
        monitor.onRewritten = { [weak self] from, to in
            guard let self else { return }
            self.rewriteCount += 1
            self.lastRewritten = (from, to)
            NotificationService.post(title: String(localized: "URL Rewritten"), body: to)
        }
        monitor.start()
        NotificationService.bootstrap()
        #endif
    }

    // MARK: - 用户规则

    func upsertUserRule(_ rule: Rule, testUrl: String? = nil) {
        if let i = userRules.firstIndex(where: { $0.id == rule.id }) {
            userRules[i].rule = rule
            userRules[i].testUrl = testUrl
        } else {
            userRules.append(LocalRule(rule: rule, enabled: true, testUrl: testUrl))
        }
        RuleStore.saveUserRules(userRules)
        rulesetRevision += 1
    }

    func setEnabled(_ local: LocalRule, _ enabled: Bool) {
        guard let i = userRules.firstIndex(where: { $0.id == local.id }) else { return }
        userRules[i].enabled = enabled
        RuleStore.saveUserRules(userRules)
        rulesetRevision += 1
    }

    func deleteUserRule(_ local: LocalRule) {
        userRules.removeAll { $0.id == local.id }
        RuleStore.saveUserRules(userRules)
        rulesetRevision += 1
    }

    func replaceUserRules(_ rules: [LocalRule]) {
        userRules = rules
        RuleStore.saveUserRules(userRules)
        rulesetRevision += 1
    }

    // MARK: - 导入导出

    func exportRules() throws -> String {
        try RuleExchange.export(userRules)
    }

    func importRules(_ json: String, merge: Bool) throws {
        replaceUserRules(try RuleExchange.import(json, merge: merge, into: userRules))
    }

    // MARK: - 测试

    /// 编辑器「测试」用的规则集：把草稿规则放进*当前会生效*的规则集里。
    ///
    /// 注意：即使草稿本身当前是禁用状态，也按“启用它”来试——
    /// 用户想知道的是“保存后这个 URL 会变成什么”。
    func rulesetForTesting(draft: Rule) -> [Rule] {
        let active = userRules.filter(\.enabled).map(\.rule)
        return RuleComposition.withDraft(draft, in: active) + sharedRules
    }

    func test(_ url: String) async -> MatchResult? {
        guard UrlCleaner.isValidUrl(url) else { return nil }
        let cleaner = UrlCleaner(rules: enabledRules, follower: URLSessionRedirectFollower())
        return await cleaner.check(url)
    }
}
