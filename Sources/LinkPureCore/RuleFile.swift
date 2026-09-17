import Foundation

/// 规则文件的磁盘格式（`Application Support/LinkPure/rules.json`）。
///
/// 为什么不用 `UserDefaults`：**它是按 bundle id 分域的**，
/// 一旦 bundle id 变化（开发期很常见）或需要跨版本迁移，数据就"凭空消失"。
/// 文件更可控，也便于备份/调试。
public struct RuleFile: Codable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var rules: [LocalRule]

    public init(version: Int = RuleFile.currentVersion, rules: [LocalRule]) {
        self.version = version
        self.rules = rules
    }
}

/// 规则数据的解码 —— 要能读懂**历史上出现过的几种形状**。
public enum RuleFileCodec {
    /// 依次尝试：
    ///   1. `{"version": 1, "rules": [...]}`  ← 本文件格式
    ///   2. `[{...}, {...}]`                  ← 裸数组（Flutter 版的 `flutter.local_rules` 就是这种）
    public static func decode(_ data: Data) throws -> [LocalRule] {
        let decoder = JSONDecoder()
        if let file = try? decoder.decode(RuleFile.self, from: data) {
            return file.rules
        }
        return try decoder.decode([LocalRule].self, from: data)
    }

    public static func encode(_ rules: [LocalRule]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        return try encoder.encode(RuleFile(rules: rules))
    }
}

/// 从 Flutter 版迁移用户规则。
///
/// Flutter 版把规则存在 `UserDefaults` 的 **`flutter.local_rules`** 键下，
/// 值是 JSON **字符串**，内容是一个数组：
///
/// ```json
/// [{"rule":{"id":"01kb…","regexFilter":"…","regexSubstitution":"…"},"enabled":true}]
/// ```
///
/// 形状与本仓库的 `LocalRule` 完全一致，所以可以直接解码——
/// 但**必须显式做一次迁移**，否则原生版替换上去之后老用户的规则就丢了。
public enum FlutterRuleMigration {
    /// 旧版可能用过的 bundle id（规则数据在它们的域/容器里）。
    public static let legacyBundleIDs = [
        "com.rxliuli.linkpure2",   // 当前 App Store 记录
        "com.rxliuli.linkpure",    // 更早的 id
    ]

    public static let defaultsKey = "flutter.local_rules"

    /// 解码 Flutter 版存在 UserDefaults 里的 JSON 字符串。
    public static func decode(_ json: String) -> [LocalRule]? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let rules = try? JSONDecoder().decode([LocalRule].self, from: data) else { return nil }
        return rules.isEmpty ? nil : rules
    }

    /// 收集所有候选来源里的原始 JSON 字符串（按优先级）。
    ///
    /// - `UserDefaults.standard`：两个平台都试。
    ///   iOS 上原生版与 Flutter 版共用 bundle id 时会**共享容器**，
    ///   所以升级替换后这一句能直接读到。
    /// - 直接扫 plist 文件：仅 macOS。iOS 沙盒里读不到别的 app 的容器，
    ///   也没必要——上面那句已经覆盖了。
    public static func collectLegacyJSON() -> [String] {
        var found: [String] = []

        if let s = UserDefaults.standard.string(forKey: defaultsKey) {
            found.append(s)
        }

        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates: [URL] = []
        for id in legacyBundleIDs {
            candidates.append(
                home.appendingPathComponent("Library/Preferences/\(id).plist")
            )
            candidates.append(
                home.appendingPathComponent(
                    "Library/Containers/\(id)/Data/Library/Preferences/\(id).plist"
                )
            )
        }
        for url in candidates {
            guard let dict = NSDictionary(contentsOf: url),
                  let s = dict[defaultsKey] as? String,
                  !found.contains(s)
            else { continue }
            found.append(s)
        }
        #endif

        return found
    }

    /// 找出第一份能成功解码的旧规则。
    public static func rules() -> [LocalRule]? {
        for json in collectLegacyJSON() {
            if let rules = decode(json) { return rules }
        }
        return nil
    }
}
