import XCTest
@testable import LinkPureCore

/// 向量之外的行为断言：这些是 UI 直接依赖的细节。
final class EngineBehaviorTests: XCTestCase {

    private func rules() throws -> [Rule] {
        try RulesManager.loadBundledRules(includeRedirects: false)
    }

    /// 多步改写时 chain 必须包含每一步（UI 的「改写链」就靠它）。
    func testChainRecordsEveryStep() async throws {
        // 第一步：解包 google 重定向 → 得到带 utm 的 URL
        // 第二步：内置的全局参数规则去掉 utm
        let input = "https://www.google.com/url?q=https%3A%2F%2Fexample.com%2Fpage%3Futm_source%3Dnl"
        let result = await UrlCleaner(rules: try rules()).check(input)

        print("status = \(result.status.rawValue)")
        print("result = \(result.url)")
        for (i, u) in result.chain.enumerated() { print("  [\(i)] \(u)") }

        XCTAssertEqual(result.status, .matched)
        XCTAssertGreaterThan(result.chain.count, 1, "应当是多步改写")
        XCTAssertEqual(result.url, result.chain.last)
    }

    /// 无命中时 chain 为空，且 url 等于输入（UI 靠这个判断"没有规则命中"）。
    func testNotMatchedHasEmptyChain() async throws {
        let input = "https://example.com/plain"
        let result = await UrlCleaner(rules: try rules()).check(input)
        XCTAssertEqual(result.status, .notMatched)
        XCTAssertTrue(result.chain.isEmpty)
        XCTAssertEqual(result.url, input)
    }

    /// 循环重定向：chain 里会出现重复项，UI 会把最后一环标红。
    func testCircularRedirectChain() async throws {
        let a = Rule(id: "A", regexFilter: "^https://a\\.com", regexSubstitution: "https://b.com")
        let b = Rule(id: "B", regexFilter: "^https://b\\.com", regexSubstitution: "https://a.com")
        let result = await UrlCleaner(rules: [a, b]).check("https://a.com/")
        XCTAssertEqual(result.status, .circularRedirect)
        XCTAssertFalse(result.chain.isEmpty)
        print("circular chain = \(result.chain)")
    }

    /// 无限改写：chain 会被截断到上限，UI 只显示前几条。
    func testInfiniteRedirectChain() async throws {
        let growing = Rule(
            id: "grow",
            regexFilter: "^(https://example\\.com/.*)$",
            regexSubstitution: "$1x"
        )
        let result = await UrlCleaner(rules: [growing]).check("https://example.com/")
        XCTAssertEqual(result.status, .infiniteRedirect)
        print("infinite chain = \(result.chain)")
    }

    /// 用户规则带 testUrl，编解码后必须还在（编辑器要回填）。
    func testLocalRuleRoundTripsTestUrl() throws {
        let original = LocalRule(
            rule: Rule(id: "r", regexFilter: "^https://a\\.com", regexSubstitution: "https://b.com"),
            enabled: false,
            testUrl: "https://a.com/x"
        )
        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([LocalRule].self, from: data)
        XCTAssertEqual(decoded.first?.testUrl, "https://a.com/x")
        XCTAssertEqual(decoded.first?.enabled, false)
    }

    /// 旧数据（没有 testUrl 字段）必须仍能解码——不能因为加字段就丢用户规则。
    func testLocalRuleDecodesLegacyJSONWithoutTestUrl() throws {
        let legacy = """
        [{"rule":{"id":"r","regexFilter":"^https://a\\\\.com","regexSubstitution":"https://b.com"},"enabled":true}]
        """
        let decoded = try JSONDecoder().decode([LocalRule].self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertNil(decoded.first?.testUrl)
    }

    // MARK: - 内置的 youtu.be 短链规则

    /// 内置规则库里必须带 youtu.be 短链 → 观看页 的改写。
    ///
    /// 这两条是 Swift 侧先加的（上游 Flutter 的规则源里还没有），而
    /// `Resources/shared-rules.json` 是 vendored 文件、`Scripts/sync-spec.sh`
    /// 会整体覆盖。**故意写成断言而不是向量**：向量目录也会被同步 rm -rf，
    /// 放这里才能在“同步后规则没了”时直接报红，而不是悄悄少个功能。
    func testBundledRulesRewriteYoutuBeShortLinks() async throws {
        let rules = try RulesManager.loadBundledRules(includeRedirects: false)
        let ids = Set(rules.map(\.id))
        XCTAssertTrue(ids.contains("linkpure-youtu.be-short-link"))
        XCTAssertTrue(ids.contains("linkpure-youtu.be-short-link-query"))

        let cleaner = UrlCleaner(rules: rules)

        // 裸短链
        let bare = await cleaner.check("https://youtu.be/jGTCHlxhtak")
        XCTAssertEqual(bare.status, .matched)
        XCTAssertEqual(bare.url, "https://www.youtube.com/watch?v=jGTCHlxhtak")

        // 带 query（App 里“复制链接”就是这个形状）：
        // 跟踪参数由既有的参数规则清掉，但 t= 这种有实际意义的参数必须留下——
        // 所以不能写成“看到 ? 就把 query 整段丢掉”。
        let withQuery = await cleaner.check("https://youtu.be/jGTCHlxhtak?si=Y3-TPEk0Q30Tp6P_&t=30")
        XCTAssertEqual(withQuery.status, .matched)
        XCTAssertEqual(withQuery.url, "https://www.youtube.com/watch?v=jGTCHlxhtak&t=30")

        // 已经是有意义的观看页时不应该被再改一次（幂等）
        let already = await cleaner.check("https://www.youtube.com/watch?v=jGTCHlxhtak&t=30")
        XCTAssertEqual(already.url, "https://www.youtube.com/watch?v=jGTCHlxhtak&t=30")
    }

    /// 编辑器弹窗的“打开前预览”：能同步算的必须在弹窗出现前就给结果，
    /// 否则弹窗会先画一帧空的、再长高，看起来就是闪烁。
    func testEditorPreviewIsComputedBeforeSheetOpens() throws {
        let stripper = Rule(id: "strip", regexFilter: "^https://youtu\\.be/", removeParams: ["si"])
        let draft = Rule(
            id: "draft",
            regexFilter: "^https://youtu\\.be/(\\w+)$",
            regexSubstitution: "https://www.youtube.com/watch?v=$1"
        )
        let ruleset = RuleComposition.withDraft(draft, in: [stripper])

        let preview = try XCTUnwrap(
            RuleEditingPreview.compute(
                draft: draft,
                testUrl: "https://youtu.be/jGTCHlxhtak?si=Y3-TPEk0Q30Tp6P_",
                ruleset: ruleset
            ),
            "纯本地规则应该在弹窗出现前就能算出来"
        )
        XCTAssertEqual(preview.status, .matched)
        XCTAssertEqual(preview.url, "https://www.youtube.com/watch?v=jGTCHlxhtak")
        XCTAssertEqual(preview.chain.count, 2)
    }

    /// 算不了的情况必须安静地返回 nil（让编辑器走异步路径），而不是算个错的。
    func testEditorPreviewGivesUpWhenItCannotKnow() {
        let draft = Rule(id: "d", regexFilter: "^https://a\\.com", regexSubstitution: "https://b.com")
        let ruleset = [draft]

        XCTAssertNil(RuleEditingPreview.compute(draft: draft, testUrl: nil, ruleset: ruleset))
        XCTAssertNil(RuleEditingPreview.compute(draft: draft, testUrl: "   ", ruleset: ruleset))
        XCTAssertNil(RuleEditingPreview.compute(draft: draft, testUrl: "不是 URL", ruleset: ruleset))
    }

    /// 内置规则库里有 13 条 `followRedirect`（短链展开），会联网——
    /// 但**编辑器用的 cleaner 不配 follower**，所以它们在这里等同于
    /// “这一步不改写”，不能被当成“算不了”而让弹窗晚一步才画出结果。
    func testEditorPreviewSkipsRedirectRulesInsteadOfBailingOut() throws {
        let redirect = Rule(id: "r", regexFilter: "^https://a\\.com", followRedirect: true)
        let draft = Rule(id: "d", regexFilter: "^https://a\\.com", regexSubstitution: "https://b.com")

        // 前一条是重定向规则，但它不改写 → 继续看下一条 → 草稿生效
        let composed = try XCTUnwrap(
            RuleEditingPreview.compute(draft: draft, testUrl: "https://a.com/x", ruleset: [redirect, draft])
        )
        XCTAssertEqual(composed.url, "https://b.com")

        // 只有那条重定向规则 → 相当于没有规则命中（与异步测试一致）
        let alone = try XCTUnwrap(
            RuleEditingPreview.compute(draft: redirect, testUrl: "https://a.com/x", ruleset: [redirect])
        )
        XCTAssertEqual(alone.status, .notMatched)
        XCTAssertEqual(alone.url, "https://a.com/x")
    }

    // MARK: - 编辑器"测试"的规则集组合

    /// **回归**：只测草稿规则会得出与实际不符的结论。
    /// 真实场景：别的规则先把 query 去掉，草稿规则才可能匹配上。
    func testDraftMustBeTestedTogetherWithOtherRules() async throws {
        let stripper = Rule(
            id: "strip", regexFilter: "^https://youtu\\.be/", removeParams: ["si"]
        )
        let draft = Rule(
            id: "draft",
            regexFilter: "^https://youtu\\.be/(\\w+)$",
            regexSubstitution: "https://www.youtube.com/watch?v=$1"
        )
        let input = "https://youtu.be/jGTCHlxhtak?si=Y3-TPEk0Q30Tp6P_"

        // ① 只测草稿 → 不命中（因为 $ 锚点 + 还有 query）
        let isolated = await UrlCleaner(rules: [draft]).check(input)
        XCTAssertEqual(isolated.status, .notMatched, "单独测就是刚才那个不一致的根源")

        // ② 草稿放进完整规则集 → 命中，且是两步链
        let composed = RuleComposition.withDraft(draft, in: [stripper])
        let result = await UrlCleaner(rules: composed).check(input)
        XCTAssertEqual(result.status, .matched)
        XCTAssertEqual(result.url, "https://www.youtube.com/watch?v=jGTCHlxhtak")
        XCTAssertEqual(result.chain.count, 2)

        // ③ 弹窗首帧用的**同步快算**必须给出同一个结果——
        //    否则会先画一帧“无结果”、再长高，就是那次闪烁。
        let composedCleaner = UrlCleaner(rules: composed)
        XCTAssertEqual(composedCleaner.checkLocally(input), result)
    }

    /// 编辑已有规则：**原位替换**，不改变优先级顺序。
    func testWithDraftReplacesInPlace() {
        let a = Rule(id: "a", regexFilter: "x", removeParams: ["p"])
        let b = Rule(id: "b", regexFilter: "y", removeParams: ["q"])
        let draft = Rule(id: "a", regexFilter: "z", removeParams: ["r"])

        let result = RuleComposition.withDraft(draft, in: [a, b])
        XCTAssertEqual(result.map(\.id), ["a", "b"])
        XCTAssertEqual(result[0].regexFilter, "z")
    }

    /// 新增规则：**放到最前**，让新规则优先。
    func testWithDraftPrependsWhenNew() {
        let a = Rule(id: "a", regexFilter: "x", removeParams: ["p"])
        let draft = Rule(id: "new", regexFilter: "z", removeParams: ["r"])

        let result = RuleComposition.withDraft(draft, in: [a])
        XCTAssertEqual(result.map(\.id), ["new", "a"])
    }
}
