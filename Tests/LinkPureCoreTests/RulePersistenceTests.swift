import XCTest
@testable import LinkPureCore

/// 规则持久化与迁移。
final class RulePersistenceTests: XCTestCase {

    /// 文件格式的往返。
    func testRuleFileRoundTrip() throws {
        let rules = [
            LocalRule(
                rule: Rule(id: "a", regexFilter: "^https://a\\.com", regexSubstitution: "https://b.com"),
                enabled: true,
                testUrl: "https://a.com/x"
            ),
            LocalRule(
                rule: Rule(id: "b", regexFilter: "^https://c\\.com", removeParams: ["utm_source"]),
                enabled: false
            ),
        ]
        let data = try RuleFileCodec.encode(rules)
        let decoded = try RuleFileCodec.decode(data)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].id, "a")
        XCTAssertEqual(decoded[0].testUrl, "https://a.com/x")
        XCTAssertFalse(decoded[1].enabled)
        // removeParams 型规则（无法导出成 from→to）也要能存下来
        XCTAssertEqual(decoded[1].rule.removeParams, ["utm_source"])
    }

    /// 解码必须同时接受"带 version 的对象"和"裸数组"。
    func testDecodeAcceptsBareArray() throws {
        let bare = """
        [{"rule":{"id":"x","regexFilter":"^https://x\\\\.com","regexSubstitution":"https://y.com"},"enabled":true}]
        """
        let decoded = try RuleFileCodec.decode(Data(bare.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].id, "x")
    }

    // MARK: - 导入导出

    /// 导出要带上测试 URL，导入要能拿回来——它是规则的一部分（"上次验证用的输入"），
    /// 丢了就得重新拼一个 URL 才能再验一次。
    func testExportImportKeepsTestUrl() throws {
        let rules = [
            LocalRule(
                rule: Rule(id: "a", regexFilter: "^https://youtu\\.be/(\\w+)$", regexSubstitution: "https://www.youtube.com/watch?v=$1"),
                enabled: true,
                testUrl: "https://youtu.be/jGTCHlxhtak?si=abc"
            ),
            LocalRule(
                rule: Rule(id: "b", regexFilter: "^https://x\\.com", regexSubstitution: "https://y.com"),
                enabled: false
            ),
        ]

        let json = try RuleExchange.export(rules)
        XCTAssertTrue(json.contains("testUrl"), "导出的 JSON 里应该有 testUrl")

        let back = try RuleExchange.import(json, merge: false, into: [])
        XCTAssertEqual(back.count, 2)
        XCTAssertEqual(back[0].testUrl, "https://youtu.be/jGTCHlxhtak?si=abc")
        XCTAssertNil(back[1].testUrl, "没填过测试 URL 的规则不该凭空长出一个")
        XCTAssertFalse(back[1].enabled)
    }

    /// 反向兼容：Flutter 版导出的 JSON 里没有 testUrl，必须照常读进来。
    func testImportAcceptsFlutterExportWithoutTestUrl() throws {
        let flutter = """
        [{"id":"a","from":"^https://a\\\\.com","to":"https://b.com","enabled":true}]
        """
        let rules = try RuleExchange.import(flutter, merge: false, into: [])
        XCTAssertEqual(rules.count, 1)
        XCTAssertNil(rules[0].testUrl)
    }

    // MARK: - Flutter 迁移

    /// 这条 JSON 是从本机 `com.rxliuli.linkpure2.plist` 的
    /// `flutter.local_rules` 里原样抄出来的，确保格式对得上。
    private let realFlutterJSON = """
    [{"rule":{"id":"01kb2cwf0mdqw5335t6zr1z9dw","regexFilter":"^https://youtube\\\\.com/shorts/([^?]+)","regexSubstitution":"https://youtube.com/watch?v=$1"},"enabled":true}]
    """

    func testMigratesRealFlutterPayload() throws {
        let rules = try XCTUnwrap(
            FlutterRuleMigration.decode(realFlutterJSON),
            "必须能解析 Flutter 版真实存在过的数据"
        )
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0].id, "01kb2cwf0mdqw5335t6zr1z9dw")
        XCTAssertEqual(rules[0].rule.regexFilter, #"^https://youtube\.com/shorts/([^?]+)"#)
        XCTAssertEqual(rules[0].rule.regexSubstitution, "https://youtube.com/watch?v=$1")
        XCTAssertTrue(rules[0].enabled)
    }

    /// 迁移过来的规则必须真的能工作（不只是解析成功）。
    func testMigratedRuleActuallyCleans() async throws {
        let rules = try XCTUnwrap(FlutterRuleMigration.decode(realFlutterJSON))
        let result = await UrlCleaner(rules: rules.map(\.rule))
            .check("https://youtube.com/shorts/abc123")
        XCTAssertEqual(result.status, .matched)
        XCTAssertEqual(result.url, "https://youtube.com/watch?v=abc123")
    }

    /// Flutter 版里 `removeParams` 型规则也要能迁（那种规则存得下、只是导不出）。
    func testMigratesRemoveParamsRule() throws {
        let json = """
        [{"rule":{"id":"p","regexFilter":"^https://a\\\\.com","removeParams":["utm_source"]},"enabled":false}]
        """
        let rules = try XCTUnwrap(FlutterRuleMigration.decode(json))
        XCTAssertEqual(rules[0].rule.removeParams, ["utm_source"])
        XCTAssertFalse(rules[0].enabled)
    }

    /// 空数组 / 垃圾数据不应被当成"迁移成功"。
    func testRejectsEmptyOrGarbage() {
        XCTAssertNil(FlutterRuleMigration.decode("[]"))
        XCTAssertNil(FlutterRuleMigration.decode("not json"))
        XCTAssertNil(FlutterRuleMigration.decode("{}"))
    }
}
