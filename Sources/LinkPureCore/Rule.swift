import Foundation

/// 一条 URL 改写规则。
///
/// 字段与 `assets/shared-rules.json`（即 LinkPure 的规则库）一一对应，
/// 因此这个类型同时也是**跨语言数据契约**的一部分。
public struct Rule: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let regexFilter: String
    public let regexSubstitution: String?
    public let removeParams: [String]?
    public let followRedirect: Bool?

    public init(
        id: String,
        regexFilter: String,
        regexSubstitution: String? = nil,
        removeParams: [String]? = nil,
        followRedirect: Bool? = nil
    ) {
        self.id = id
        self.regexFilter = regexFilter
        self.regexSubstitution = regexSubstitution
        self.removeParams = removeParams
        self.followRedirect = followRedirect
    }
}

extension Rule {
    /// 新用户规则的 id：ULID（26 字符 Crockford Base32，前 48 位时间戳 + 80 位随机）。
    ///
    /// 与 Flutter 版的 `Ulid().toString()` 同构，好处有两个：
    ///   - **字典序 = 创建顺序**，列表顺序天然稳定；
    ///   - 时间戳之外还有随机位，**同一秒内连续新增也不会撞 id**
    ///     （旧实现 `custom-\(秒级时间戳)` 会，撞了之后 `upsert` 会把前一条覆盖掉）。
    ///
    /// id 是内部标识（编辑定位、导入导出按 id 去重），不在界面上展示。
    public static func newUserRuleID(now: Date = Date()) -> String {
        // Crockford Base32：去掉 I/L/O/U，避免读写出歧义
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        var value = UInt64((now.timeIntervalSince1970 * 1000).rounded())
        var chars = Array(repeating: Character("0"), count: 26)

        // 时间戳 48 位 → 前 10 个字符
        for i in stride(from: 9, through: 0, by: -1) {
            chars[i] = alphabet[Int(value & 0x1F)]
            value >>= 5
        }
        // 随机 80 位 → 后 16 个字符
        for i in 10..<26 {
            chars[i] = alphabet[Int(UInt8.random(in: 0...31))]
        }
        return String(chars)
    }
}

/// 规则集（规则库文件的顶层结构）。
public struct RuleSet: Codable, Sendable {
    public let name: String
    public let description: String
    public let rules: [Rule]

    public init(name: String, description: String, rules: [Rule]) {
        self.name = name
        self.description = description
        self.rules = rules
    }
}

public enum LinkPureError: Error {
    case resourceMissing(String)
}
