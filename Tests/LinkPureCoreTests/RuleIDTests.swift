import XCTest
@testable import LinkPureCore

/// 用户规则 id 的生成规则。
///
/// id 不展示在界面上，但它承担**编辑定位**与**导入导出按 id 去重合并**两件事，
/// 所以"稳定、唯一、可排序"必须由测试兜住。
final class RuleIDTests: XCTestCase {

    private let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    func testFormatIsULID() {
        let id = Rule.newUserRuleID()
        XCTAssertEqual(id.count, 26)

        let lower = Set(id.lowercased())
        let illegal = lower.subtracting(Set("0123456789abcdefghjkmnpqrstvwxyz"))
        XCTAssertTrue(illegal.isEmpty, "出现了 Crockford Base32 之外的字符：\(illegal)")

        // Flutter 版的 Ulid 也是大写，大小写混合会让排序与去重出现"近重复"
        XCTAssertEqual(id, id.uppercased())
    }

    /// 旧实现 `custom-<秒级时间戳>` 在同一秒内新增两条会得到同一个 id，
    /// 保存时后一条会把前一条覆盖掉。随机位必须让这种情况不再发生。
    func testSameSecondIDsAreUnique() {
        let now = Date()
        let ids = Set((0..<5_000).map { _ in Rule.newUserRuleID(now: now) })
        XCTAssertEqual(ids.count, 5_000)
    }

    /// 时间戳前缀可解回生成时间，且字典序 = 时间序（列表顺序因此天然稳定）。
    func testTimestampPrefixSortsChronologically() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let early = Rule.newUserRuleID(now: base)
        let late = Rule.newUserRuleID(now: base.addingTimeInterval(60))
        XCTAssertLessThan(early, late)

        // 前 10 个字符 = 48 位毫秒时间戳
        var ms: UInt64 = 0
        for c in early.prefix(10) {
            ms = ms << 5 | UInt64(alphabet.firstIndex(of: c)!)
        }
        XCTAssertEqual(Double(ms) / 1000, base.timeIntervalSince1970, accuracy: 0.001)
    }
}
