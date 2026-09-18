import Foundation

public enum CheckStatus: String, Sendable {
    case matched
    case notMatched
    case circularRedirect
    case infiniteRedirect
}

public struct MatchResult: Sendable, Equatable {
    public let status: CheckStatus
    /// `matched` 时为改写后的 URL；`notMatched` 时等于输入。
    public let url: String
    public let chain: [String]

    public init(status: CheckStatus, url: String, chain: [String]) {
        self.status = status
        self.url = url
        self.chain = chain
    }
}

/// 跟随重定向（`followRedirect` 规则用）。
/// 抽成协议是为了让测试可以注入假实现——网络调用不能进 golden 向量。
public protocol RedirectFollower: Sendable {
    func follow(_ url: String) async -> String?
}

/// 规则引擎。行为契约见 LinkPure 仓库的 `conformance/README.md`。
public struct UrlCleaner: Sendable {
    public let rules: [Rule]
    private let follower: RedirectFollower?

    /// 一条 URL 最多被改写几次（超过就判定无限重定向）。
    private static let maxRedirects = 5

    public init(rules: [Rule], follower: RedirectFollower? = nil) {
        self.rules = rules
        self.follower = follower
    }

    // MARK: - 主流程

    public func check(_ url: String) async -> MatchResult {
        guard Self.isValidUrl(url) else {
            return MatchResult(status: .notMatched, url: url, chain: [])
        }

        var current = url
        var chain: [String] = []

        for _ in 0..<Self.maxRedirects {
            var matched = false
            for rule in rules {
                guard let outcome = matchWithRuleLocally(rule, current) else { continue }
                let newUrl: String
                switch outcome {
                case .url(let u):
                    newUrl = u
                case .needsNetwork:
                    // 只有 followRedirect 需要联网；没有 follower 时与原行为一致：
                    // 视为“未改变”，继续看下一条规则。
                    guard let follower else { continue }
                    newUrl = await follower.follow(current) ?? current
                }
                // 幂等：匹配但没改变 URL，不算命中，继续看下一条规则
                guard !newUrl.isEmpty, newUrl != current else { continue }

                if chain.contains(newUrl) {
                    return MatchResult(status: .circularRedirect, url: newUrl, chain: chain)
                }
                chain.append(newUrl)
                current = newUrl
                matched = true
                break
            }
            if !matched {
                return chain.isEmpty
                    ? MatchResult(status: .notMatched, url: url, chain: [])
                    : MatchResult(status: .matched, url: current, chain: chain)
            }
        }
        return MatchResult(status: .infiniteRedirect, url: current, chain: chain)
    }

    /// **不联网的同步快算**：拿不到答案时返回 nil。
    ///
    /// 规则的匹配/替换/删参数本来就是同步的，只有 `followRedirect` 要联网。
    /// 界面能用它把“打开弹窗”和“算改写链”分开：本地能算的规则在弹窗出现前
    /// 就算完，弹窗第一帧就带着结果画出来——否则弹窗会先以“没有结果”的高度
    /// 出现、拿到结果后再长高一次，肉眼就是一次闪烁。
    ///
    /// 只有**配了 follower**（要真去跟随重定向）且正好命中那种规则时才返回 nil；
    /// 没有 follower 时（编辑器就是这种，等于“这一步不改写”）结果完全确定，
    /// 照常返回。
    ///
    /// 语义与 `check` 一致：返回非 nil 时结果与 `check` **逐字段相等**
    /// （`ConformanceTests.testLocalFastPathAgreesWithAsync` 拿全部向量盯着）。
    public func checkLocally(_ url: String) -> MatchResult? {
        guard Self.isValidUrl(url) else {
            return MatchResult(status: .notMatched, url: url, chain: [])
        }

        var current = url
        var chain: [String] = []

        for _ in 0..<Self.maxRedirects {
            var matched = false
            for rule in rules {
                guard let outcome = matchWithRuleLocally(rule, current) else { continue }
                let newUrl: String
                switch outcome {
                case .url(let u):
                    newUrl = u
                case .needsNetwork:
                    // 没配 follower → 这一步不改写（与 check 一致）；
                    // 配了 → 答案在网络上，同步路径放弃。
                    guard follower != nil else { continue }
                    return nil
                }
                guard !newUrl.isEmpty, newUrl != current else { continue }

                if chain.contains(newUrl) {
                    return MatchResult(status: .circularRedirect, url: newUrl, chain: chain)
                }
                chain.append(newUrl)
                current = newUrl
                matched = true
                break
            }
            if !matched {
                return chain.isEmpty
                    ? MatchResult(status: .notMatched, url: url, chain: [])
                    : MatchResult(status: .matched, url: current, chain: chain)
            }
        }
        return MatchResult(status: .infiniteRedirect, url: current, chain: chain)
    }

    // MARK: - 单条规则

    enum LocalOutcome {
        case url(String)
        /// 命中，但要跟随重定向才能得到结果（联网）
        case needsNetwork
    }

    /// 单条规则的**同步**部分：正则是否命中 + 就地改写。
    /// 返回 nil 表示规则没命中。`check` 与 `checkLocally` 共用它，避免两条路径跑偏。
    func matchWithRuleLocally(_ rule: Rule, _ url: String) -> LocalOutcome? {
        guard let regex = Self.compile(rule.regexFilter) else { return nil }
        guard regex.firstMatch(in: url, options: [], range: Self.fullRange(url)) != nil else {
            return nil
        }
        if let sub = rule.regexSubstitution, !sub.isEmpty {
            return .url(Self.applyRegexSubstitution(rule, url))
        }
        if let params = rule.removeParams, !params.isEmpty {
            return .url(Self.removeQueryParameters(url, params))
        }
        if rule.followRedirect == true {
            return .needsNetwork
        }
        return .url(url)
    }

    // MARK: - 正则替换

    static func applyRegexSubstitution(_ rule: Rule, _ url: String) -> String {
        guard let regex = compile(rule.regexFilter) else { return url }
        let ns = url as NSString
        guard let match = regex.firstMatch(
            in: url, options: [], range: NSRange(location: 0, length: ns.length)
        ) else { return url }

        var result = rule.regexSubstitution ?? ""
        for i in 1..<match.numberOfRanges {
            let r = match.range(at: i)
            let captured = (r.location == NSNotFound) ? "" : ns.substring(with: r)
            // 捕获组先做 percent-decode（不做 '+' → 空格）
            result = result.replacingOccurrences(of: "$\(i)", with: decodeComponent(captured))
        }
        return result
    }

    // MARK: - 参数移除

    /// 按**原始 query 串**逐对处理：不折叠重复参数、不改变顺序、不重新编码、
    /// 不省略默认端口；参数全空时去掉整个 `?`（即便后面还有 `#fragment`）。
    static func removeQueryParameters(_ url: String, _ paramsToRemove: [String]) -> String {
        guard let qIndex = url.firstIndex(of: "?") else { return url }
        let head = String(url[url.startIndex..<qIndex])
        var rest = String(url[url.index(after: qIndex)...])

        var fragment = ""
        if let fIndex = rest.firstIndex(of: "#") {
            fragment = String(rest[fIndex...])
            rest = String(rest[rest.startIndex..<fIndex])
        }
        if rest.isEmpty { return url }

        var kept: [String] = []
        var removed = false
        for pair in rest.split(separator: "&", omittingEmptySubsequences: false) {
            let pair = String(pair)
            if pair.isEmpty { continue }
            let rawKey = pair.firstIndex(of: "=").map { String(pair[pair.startIndex..<$0]) } ?? pair
            if paramMatches(decodeQueryKey(rawKey), paramsToRemove) {
                removed = true
            } else {
                kept.append(pair)
            }
        }
        if !removed { return url }

        var out = head
        if !kept.isEmpty { out += "?" + kept.joined(separator: "&") }
        out += fragment
        return out
    }

    /// **先精确匹配，再试正则**：参数名本身可能含 `$` `(` 等字符（Branch 的 `$3p` /
    /// `$deep_link`），它们是字面量，不能被误当正则（`$` 是行尾锚点 → 会永久失效）。
    /// 参数名匹配**区分大小写**（与规则匹配不同）。
    static func paramMatches(_ key: String, _ patterns: [String]) -> Bool {
        for pattern in patterns {
            if key == pattern { return true }
            guard containsRegexMeta(pattern) else { continue }
            if let re = compile(pattern, caseInsensitive: false),
               re.firstMatch(in: key, options: [], range: fullRange(key)) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - 正则编译

    /// 规则匹配**大小写不敏感**（与 Redirector 一致）。
    static func compile(_ pattern: String, caseInsensitive: Bool = true) -> NSRegularExpression? {
        try? NSRegularExpression(
            pattern: pattern,
            options: caseInsensitive ? [.caseInsensitive] : []
        )
    }

    /// 把 `\d` / `\w` / `\s` 等简写改写成显式 ASCII 字符类。
    ///
    /// Swift 走的 ICU 默认是 **Unicode** 语义，与 Dart/JS 不一致；
    /// 规范要求 ASCII（见 conformance/README.md 第 3 条）。
    static func asciiRewrite(_ pattern: String) -> String {
        var out = ""
        let chars = Array(pattern)
        var i = 0
        while i < chars.count {
            if chars[i] == "\\", i + 1 < chars.count {
                switch chars[i + 1] {
                case "d": out += "[0-9]"
                case "D": out += "[^0-9]"
                case "w": out += "[0-9A-Za-z_]"
                case "W": out += "[^0-9A-Za-z_]"
                case "s": out += "[\\t\\n\\u{0B}\\f\\r ]"
                case "S": out += "[^\\t\\n\\u{0B}\\f\\r ]"
                default:
                    out.append("\\")
                    out.append(chars[i + 1])
                }
                i += 2
            } else {
                out.append(chars[i])
                i += 1
            }
        }
        return out
    }

    // MARK: - 工具

    static func containsRegexMeta(_ s: String) -> Bool {
        let meta: Set<Character> = ["^", "$", "(", ")", "[", "]", "{", "}", "*", "+", "?", "|", "\\"]
        return s.contains { meta.contains($0) }
    }

    /// 与 Dart `Uri.decodeComponent` 一致：**不**把 `+` 当空格。
    static func decodeComponent(_ s: String) -> String {
        s.removingPercentEncoding ?? s
    }

    /// query key 用 form 风格解码（`+` → 空格），与 Dart `Uri.decodeQueryComponent` 一致。
    static func decodeQueryKey(_ s: String) -> String {
        let plus = s.replacingOccurrences(of: "+", with: " ")
        return plus.removingPercentEncoding ?? plus
    }

    public static func isValidUrl(_ text: String) -> Bool {
        guard let r = text.range(of: "://") else { return false }
        let scheme = text[text.startIndex..<r.lowerBound].lowercased()
        return scheme == "http" || scheme == "https"
    }

    static func fullRange(_ s: String) -> NSRange {
        NSRange(s.startIndex..<s.endIndex, in: s)
    }
}
