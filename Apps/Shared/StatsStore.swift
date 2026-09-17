import Foundation
import os

/// 运行统计的持久化（目前只有「累计改写次数」）。
///
/// **单独一个文件，不跟规则混在 `rules.json` 里。** 理由不是性能，是爆炸半径：
///
///   - `rules.json` 是**用户数据**——要能导出、备份、手改，写坏了用户就丢规则；
///   - 统计只是遥测，最坏情况是"计数归零"，不影响任何功能。
///
/// 混在一起的话，统计这条写盘路径出问题会连规则一起毁掉。分开之后还顺带省掉了
/// 给 `RuleFile` 加字段 / 动 `version` / 维持 `RuleFileCodec` 那几条兼容分支的麻烦。
///
/// **写在每次改写之后**，不攒着定时刷。触发路径是"用户手动复制一个会被改写的 URL"，
/// 本来就不可能高频；立即写的好处是崩溃 / 被强杀也不丢计数。真遇到连续同步
///（Universal Clipboard 从 iPhone 推过来）再加合并写也不迟。
enum StatsStore {
    private static let log = Logger(subsystem: "com.rxliuli.linkpure", category: "stats")

    /// 同目录（`Application Support/LinkPure/`），方便跟规则一起备份或清理
    static var fileURL: URL? {
        RuleStore.directory?.appendingPathComponent("stats.json")
    }

    static func load() -> RunStats {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else {
            return RunStats()
        }
        do {
            return try JSONDecoder().decode(RunStats.self, from: try Data(contentsOf: url))
        } catch {
            // 统计不是关键数据：读坏了按 0 计，不要因此报错或阻塞启动。
            //
            // 注意这里的容错**不是**靠 `RunStats` 的属性默认值——Swift 合成的
            // `Decodable` 不会用默认值，缺字段会直接抛 `keyNotFound`（实测过）。
            // 所以以后给 RunStats 加字段时，旧文件会走这条分支归零；
            // 对一个计数器可以接受，真要保留就把解码改成 `decodeIfPresent`。
            log.error("load failed, counting from 0: \(String(describing: error), privacy: .public)")
            return RunStats()
        }
    }

    static func save(_ stats: RunStats) {
        guard let directory = RuleStore.directory, let url = fileURL else {
            log.error("save: no container directory available")
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            // `.atomic`：写一半被杀不会留下半个 JSON
            try JSONEncoder().encode(stats).write(to: url, options: .atomic)
        } catch {
            // 计数写失败不该打断正在进行的改写，更不该弹给用户
            log.error("save failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// 运行统计。所有字段都有默认值，所以 `RunStats()` 就是"全零"。
struct RunStats: Codable, Sendable {
    /// 累计改写次数（跨启动累计，不是本次会话）
    var rewriteCount: Int = 0
}
