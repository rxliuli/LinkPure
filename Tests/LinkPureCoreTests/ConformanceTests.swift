import XCTest
@testable import LinkPureCore

/// 用 LinkPure 仓库 conformance/ 下的**语言无关向量**验证本实现。
///
/// 这些向量同时被 Dart（参考实现）与 Rust（独立实现）跑过；
/// 三者零分歧 = 规范真正可执行。
final class ConformanceTests: XCTestCase {

    func testAllConformanceVectors() async throws {
        let shared = try RulesManager.loadBundledRuleSet()
        let outcome = try await VectorRunner.run(shared: shared)

        for (file, cases, failed) in outcome.perFile {
            print("\(failed == 0 ? "ok  " : "FAIL") \(file)  (\(cases) cases, \(failed) failed)")
        }
        if !outcome.failures.isEmpty {
            print("\n--- failures (first 30) ---")
            for f in outcome.failures.prefix(30) { print("  • \(f)") }
        }
        print("\nTOTAL: \(outcome.total) cases, \(outcome.failed) failed")

        XCTAssertEqual(
            outcome.failed, 0,
            "\(outcome.failed) of \(outcome.total) conformance vectors failed"
        )
    }

    /// 规则库本身应当能被解析出来，且规模合理。
    func testBundledRuleSetLoads() throws {
        let set = try RulesManager.loadBundledRuleSet()
        XCTAssertGreaterThan(set.rules.count, 1000, "规则库看起来没被正确打包")
        XCTAssertTrue(set.rules.allSatisfy { !$0.regexFilter.isEmpty })
    }

    /// 编辑器用的同步快算 `checkLocally` 只应该“算不了返回 nil”，
    /// **不应该算出跟 `check` 不一样的结果**。
    ///
    /// 两个循环是分开写的（一个要 await、一个不能 await），这条测试就是防它们跑偏：
    /// 拿全部一致性向量同时跑两条路径，只要都能算出来就必须逐字段相等。
    func testLocalFastPathAgreesWithAsync() async throws {
        let shared = try RulesManager.loadBundledRuleSet()
        guard let dir = Bundle.module.url(forResource: "Vectors", withExtension: nil) else {
            return XCTFail("Vectors 丢了")
        }
        let files = try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var compared = 0
        var total = 0
        for file in files {
            let doc = try JSONDecoder().decode(VectorFile.self, from: Data(contentsOf: file))
            for c in doc.cases {
                total += 1
                var rules: [Rule]
                if let inline = c.rules {
                    rules = inline
                } else if let ref = c.ruleRef {
                    rules = shared.rules.filter { $0.id == ref }
                } else {
                    rules = shared.rules
                }
                // followRedirect 在向量里被剥离（要联网），本地快算也正好算不了它
                rules = rules.filter { $0.followRedirect != true }

                let cleaner = UrlCleaner(rules: rules)
                let async = await cleaner.check(c.input)
                guard let local = cleaner.checkLocally(c.input) else {
                    XCTFail("\(file.lastPathComponent) :: \(c.name ?? "(unnamed)") 没配 follower 却在同步路径放弃")
                    continue
                }
                compared += 1
                XCTAssertEqual(
                    local, async,
                    "\(file.lastPathComponent) :: \(c.name ?? "(unnamed)") 同步/异步结果不一致"
                )
            }
        }
        XCTAssertEqual(compared, total, "每个向量都该比到")
    }

    /// `checkLocally` 只在“配了 follower 且正好需要它”时才放弃。
    /// 其余情况必须给结果——而且与 `check` 一模一样。
    func testLocalFastPathGivesUpOnlyWhenFollowerWouldBeNeeded() async {
        let rules = [
            Rule(id: "redirect", regexFilter: "^https://a\\.com", followRedirect: true),
            Rule(id: "never", regexFilter: "^https://a\\.com", regexSubstitution: "https://b.com"),
        ]

        // 没配 follower（编辑器就是这样）：跟随重定向那一步等于“不改写”，
        // 于是第一条规则被跳过、第二条命中——本地能算，不该放弃。
        let plain = UrlCleaner(rules: rules)
        let local = plain.checkLocally("https://a.com/x")
        let async = await plain.check("https://a.com/x")
        XCTAssertEqual(local, async)
        XCTAssertEqual(local?.url, "https://b.com")

        // 配了 follower：答案在网络上，同步路径必须交给异步路径
        let networked = UrlCleaner(rules: rules, follower: StubFollower(answer: "https://c.com"))
        XCTAssertNil(networked.checkLocally("https://a.com/x"))

        // 不命中那条规则时照常给结果
        XCTAssertEqual(
            plain.checkLocally("https://c.com/x"),
            MatchResult(status: .notMatched, url: "https://c.com/x", chain: [])
        )
    }
}

private struct StubFollower: RedirectFollower {
    let answer: String
    func follow(_ url: String) async -> String? { answer }
}
