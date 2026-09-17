import Foundation
import LinkPureCore
import os

/// 用户规则的持久化。
///
/// **存在 `Application Support/LinkPure/rules.json`，不再用 `UserDefaults`。**
///
/// 原因（踩过的坑）：`UserDefaults` 按 **bundle id 分域**，
/// 开发期换 bundle id、或将来做跨版本迁移，数据都会"凭空消失"且毫无痕迹。
/// 文件路径由 `Application Support` 决定，与 bundle id 无关，也更好备份与调试。
enum RuleStore {
    private static let log = Logger(subsystem: "com.rxliuli.linkpure", category: "store")

    /// 测试可覆盖存放目录
    static var directoryOverride: URL?

    static var directory: URL? {
        if let directoryOverride { return directoryOverride }
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return base.appendingPathComponent("LinkPure", isDirectory: true)
    }

    static var fileURL: URL? {
        directory?.appendingPathComponent("rules.json")
    }

    static func loadUserRules() -> [LocalRule] {
        if let url = fileURL, FileManager.default.fileExists(atPath: url.path) {
            do {
                let rules = try RuleFileCodec.decode(try Data(contentsOf: url))
                log.error("load: \(rules.count, privacy: .public) 条 ← \(url.path, privacy: .public)")
                return rules
            } catch {
                // 不能静默吞掉，否则表现就是"规则凭空消失"
                log.error("load 解码失败：\(String(describing: error), privacy: .public)")
                return []
            }
        }

        // 文件不存在 = 首次运行 → 尝试从 Flutter 版迁入
        if let migrated = FlutterRuleMigration.rules() {
            log.error("migrate: 从 Flutter 版迁入 \(migrated.count, privacy: .public) 条")
            saveUserRules(migrated)
            return migrated
        }

        log.error("load: 无规则文件，也没有可迁移的旧数据（首次运行）")
        return []
    }

    static func saveUserRules(_ rules: [LocalRule]) {
        guard let directory, let url = fileURL else {
            log.error("save: 拿不到存放路径")
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            let data = try RuleFileCodec.encode(rules)
            try data.write(to: url, options: .atomic)
            log.error("save: \(rules.count, privacy: .public) 条 → \(url.path, privacy: .public)")
        } catch {
            log.error("save 失败：\(String(describing: error), privacy: .public)")
        }
    }
}
