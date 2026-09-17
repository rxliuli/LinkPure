import Foundation

/// 用户自定义规则 = 规则本体 + 启用开关。
///
/// 与 Flutter 版的 `LocalRule` 对应：**共享规则库是只读的**，不可启用/禁用；
/// 只有用户规则带 enabled 状态。
public struct LocalRule: Codable, Sendable, Identifiable, Equatable {
    public var rule: Rule
    public var enabled: Bool
    /// 编辑时用的测试 URL。**不参与匹配**，只是记住上次验证用的输入
    /// （参照 Redirector 的 testUrl 字段）。
    public var testUrl: String?

    public var id: String { rule.id }

    public init(rule: Rule, enabled: Bool = true, testUrl: String? = nil) {
        self.rule = rule
        self.enabled = enabled
        self.testUrl = testUrl
    }
}

/// 导入/导出的交换格式。
///
/// 与 Flutter 版保持一致：**只有 `regexSubstitution` 类型的规则可以导出**
/// （`removeParams` / `followRedirect` 类型表达不了 from→to 结构）。
public struct ExportedRule: Codable, Sendable {
    public let id: String
    public let from: String
    public let to: String
    public let enabled: Bool
    /// 编辑时用的测试 URL（可选）。
    ///
    /// Flutter 版的导出没有这一项，读到时缺省为 nil，所以两边的文件仍然互相可读；
    /// 只是经 Flutter 再导出会丢掉它。字段名与 Redirector 一致。
    public let testUrl: String?

    public init(id: String, from: String, to: String, enabled: Bool, testUrl: String? = nil) {
        self.id = id
        self.from = from
        self.to = to
        self.enabled = enabled
        self.testUrl = testUrl
    }
}

public enum RuleExchangeError: Error, LocalizedError {
    case notExportable(String)
    case invalidFormat

    public var errorDescription: String? {
        switch self {
        case .notExportable(let id):
            return "规则「\(id)」不是 regexSubstitution 类型，无法导出"
        case .invalidFormat:
            return "JSON 格式不正确：期望一个规则数组"
        }
    }
}

/// 规则集组合：把草稿规则放进完整规则集里。
///
/// 用于编辑器的「测试」——**不能只测草稿规则本身**，
/// 否则会与真实行为不一致（别的规则可能先把 URL 改成草稿能匹配的样子）。
/// 语义与 Redirector 的 RuleDialog 一致：
///   - 编辑已有规则 → **原位替换**（保留它的优先级位置）
///   - 新增规则 → **放到最前**（新规则优先）
public enum RuleComposition {
    public static func withDraft(_ draft: Rule, in rules: [Rule]) -> [Rule] {
        if let index = rules.firstIndex(where: { $0.id == draft.id }) {
            var copy = rules
            copy[index] = draft
            return copy
        }
        return [draft] + rules
    }
}

/// 编辑器弹窗的**打开前预览**。
///
/// 弹窗（`.sheet`）的内容在出现的那一帧就完成布局：若让编辑器自己在 `.task` 里算，
/// 弹窗会先以“没有结果”的高度出现、拿到结果后再长高一次——肉眼就是一次闪烁。
/// 所以先在这里同步算一把。
///
/// 放在 `LinkPureCore` 而不是视图里，是为了能直接测：视图代码进不了单测。
public enum RuleEditingPreview {
    /// 返回 nil = **算不出预览**：测试 URL 为空或不合法
    /// （编辑器自己会画“不是有效的 URL”或什么都不画）。
    ///
    /// 注意：命中了 `followRedirect` 的规则**不算**算不出——编辑器用的 cleaner
    /// 本来就不配 follower（不能因为打开个弹窗就去联网），那条规则等同
    /// “这一步不改写”，跟编辑器里的异步测试行为一致。
    ///
    /// - Parameter ruleset: **已经组好的**规则集（草稿已按优先级放进去，
    ///   见 `RuleComposition.withDraft`），语义与编辑器的异步测试一致。
    public static func compute(draft: Rule, testUrl: String?, ruleset: [Rule]) -> MatchResult? {
        let trimmed = (testUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, UrlCleaner.isValidUrl(trimmed) else { return nil }
        return UrlCleaner(rules: ruleset).checkLocally(trimmed)
    }
}

public enum RuleExchange {
    /// 导出用户规则为 JSON（只导出 regexSubstitution 类型）。
    public static func export(_ rules: [LocalRule]) throws -> String {
        var exported: [ExportedRule] = []
        for local in rules {
            guard let to = local.rule.regexSubstitution else {
                throw RuleExchangeError.notExportable(local.rule.id)
            }
            exported.append(
                ExportedRule(
                    id: local.rule.id,
                    from: local.rule.regexFilter,
                    to: to,
                    enabled: local.enabled,
                    testUrl: local.testUrl
                )
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(exported)
        return String(decoding: data, as: UTF8.self)
    }

    /// 从 JSON 导入；`merge = true` 时按 id 去重合并，否则整体替换。
    public static func `import`(_ json: String, merge: Bool, into existing: [LocalRule]) throws -> [LocalRule] {
        guard let data = json.data(using: .utf8) else { throw RuleExchangeError.invalidFormat }
        guard let decoded = try? JSONDecoder().decode([ExportedRule].self, from: data) else {
            throw RuleExchangeError.invalidFormat
        }
        let incoming = decoded.map { exported in
            LocalRule(
                rule: Rule(
                    id: exported.id,
                    regexFilter: exported.from,
                    regexSubstitution: exported.to
                ),
                enabled: exported.enabled,
                testUrl: exported.testUrl
            )
        }
        guard merge else { return incoming }

        var result = existing
        for rule in incoming where !result.contains(where: { $0.id == rule.id }) {
            result.append(rule)
        }
        return result
    }
}
