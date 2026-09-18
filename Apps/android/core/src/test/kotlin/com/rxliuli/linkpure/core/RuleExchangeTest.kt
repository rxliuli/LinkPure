package com.rxliuli.linkpure.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * 规则文件的**跨实现兼容性**。
 *
 * 这组测试存在的理由：格式不是我们自己说了算的——同一份 `rules.json`
 * 还要能被 Swift 侧（`RuleFile` / `LocalRule` 的 `Codable`）和 Flutter 侧读。
 * 曾经踩过：kotlinx.serialization 默认会把等于默认值的字段省略，
 * 于是 `enabled` / `version` 没写出来，而 Swift 那边这两个属性非可选、无默认值，
 * `Codable` 遇到缺键直接解码失败——**Kotlin 写出来的文件 Swift 读不了**。
 */
class RuleExchangeTest {

    private val substituted = LocalRule(
        rule = Rule(
            id = "01KB0000000000000000000001",
            regexFilter = "^https://example\\.com",
            regexSubstitution = "https://example.org",
        ),
    )

    private val removeParams = LocalRule(
        rule = Rule(
            id = "01KB0000000000000000000002",
            regexFilter = "^https://foo\\.com",
            removeParams = listOf("utm_x", "\$3p"),
        ),
        enabled = false,
    )

    @Test
    fun ruleFileAlwaysWritesVersionAndEnabled() {
        val json = RuleFileCodec.encode(listOf(substituted, removeParams))

        // 关键断言：不能依赖「解码器的默认值」
        assertTrue(json.contains("\"version\""), "缺 version 键，Swift 的 RuleFile 解不了")
        assertTrue(json.contains("\"enabled\""), "缺 enabled 键，Swift 的 LocalRule 解不了")
        assertFalse(json.contains("\"testUrl\""), "testUrl 是 nil，不该写出来")

        assertEquals(listOf(substituted, removeParams), RuleFileCodec.decode(json))
    }

    @Test
    fun decodeAcceptsBareArray() {
        // Flutter 版存在 SharedPreferences 里的就是裸数组
        val bare = """
            [{"rule":{"id":"a","regexFilter":"^https://x","regexSubstitution":"https://y"},
              "enabled":true}]
        """.trimIndent()
        val rules = RuleFileCodec.decode(bare)
        assertEquals(1, rules.size)
        assertEquals("a", rules[0].id)
        assertTrue(rules[0].enabled)
    }

    @Test
    fun decodeAcceptsObjectForm() {
        val obj = """{"version":1,"rules":[
            {"rule":{"id":"a","regexFilter":"^https://x","regexSubstitution":"https://y"}}
        ]}"""
        val rules = RuleFileCodec.decode(obj)
        assertEquals(1, rules.size)
        // enabled 缺省应当是 true
        assertTrue(rules[0].enabled)
    }

    @Test
    fun exportUsesFlutterCompatibleShape() {
        val result = RuleExchange.export(listOf(substituted, removeParams))

        // 只有 regexSubstitution 型能导出，另一条记在 skipped 里（不报错）
        assertEquals(listOf(removeParams.id), result.skipped)
        assertTrue(result.json.contains("\"from\""))
        assertTrue(result.json.contains("\"to\""))
        assertTrue(result.json.contains("\"enabled\""))
        assertFalse(result.json.contains(removeParams.id))

        // 导出的东西能原样导回来
        val roundTrip = RuleExchange.`import`(result.json, merge = false, existing = emptyList())
        assertEquals(1, roundTrip.size)
        assertEquals(substituted.rule.regexFilter, roundTrip[0].rule.regexFilter)
        assertEquals(substituted.rule.regexSubstitution, roundTrip[0].rule.regexSubstitution)
    }

    @Test
    fun importMergeKeepsExistingAndSkipsDuplicates() {
        val json = """
            [{"id":"a","from":"^https://x","to":"https://y","enabled":true},
             {"id":"b","from":"^https://p","to":"https://q","enabled":false}]
        """.trimIndent()
        val existing = listOf(substituted.copy(rule = substituted.rule.copy(id = "a")))

        val merged = RuleExchange.`import`(json, merge = true, existing = existing)
        assertEquals(listOf("a", "b"), merged.map { it.id })
        // 已存在的 a 保留原样，没被导入内容覆盖
        assertEquals(existing[0].rule, merged[0].rule)

        val replaced = RuleExchange.`import`(json, merge = false, existing = existing)
        assertEquals(listOf("a", "b"), replaced.map { it.id })
        assertEquals("^https://x", replaced[0].rule.regexFilter)
    }

    @Test
    fun importRejectsNonArray() {
        val error = runCatching {
            RuleExchange.`import`("""{"rules":[]}""", merge = false, existing = emptyList())
        }.exceptionOrNull()
        assertTrue(error is RuleExchangeException, "非数组应当报错，实际：$error")
    }

    @Test
    fun flutterMigrationDecodesPluginShape() {
        // Flutter 版 Rule.toJson() 还会带一个 test 字段，我们应当忽略它
        val payload = """
            [{"rule":{"id":"01KB","regexFilter":"^https://x",
                      "regexSubstitution":"https://y",
                      "test":[{"from":"a","to":"b"}]},
              "enabled":true}]
        """.trimIndent()
        val rules = FlutterRuleMigration.decode(payload)
        assertEquals(1, rules?.size)
        assertEquals("01KB", rules!![0].id)
    }

    @Test
    fun flutterMigrationRejectsGarbage() {
        assertEquals(null, FlutterRuleMigration.decode("not json"))
        assertEquals(null, FlutterRuleMigration.decode("[]"))
    }

    @Test
    fun newUserRuleIdIsUlidShapedAndSortable() {
        val alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
        val a = RulesManager.newUserRuleId(now = 1_000_000_000_000)
        val b = RulesManager.newUserRuleId(now = 2_000_000_000_000)
        assertEquals(26, a.length)
        assertTrue(a.all { it in alphabet }, "含 Crockford Base32 之外的字符：$a")
        // 字典序 = 时间顺序
        assertTrue(a < b, "$a 应当排在 $b 前面")
    }
}
