package com.rxliuli.linkpure.core

import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * 拿 LinkPure（Flutter）仓库 `conformance/` 下的语言无关向量验证本实现。
 *
 * 这一条测试是**整个 core 模块存在的意义**：引擎只有两三百行，
 * 值钱的是那 1053 条把行为钉死的向量。向量全绿 = Kotlin 版与 Dart/Rust/Swift 零分歧。
 */
class ConformanceTest {

    @Test
    fun allVectorsPass() = runBlocking {
        val shared = RulesManager.loadBundledRuleSet()
        val outcome = VectorRunner.run(shared)

        for ((file, cases, failed) in outcome.perFile) {
            println("${if (failed == 0) "ok  " else "FAIL"} $file  ($cases cases, $failed failed)")
        }
        if (outcome.failures.isNotEmpty()) {
            println("\n--- failures (first 30) ---")
            outcome.failures.take(30).forEach { println("  • $it") }
        }
        println("\nTOTAL: ${outcome.total} cases, ${outcome.failed} failed")

        assertEquals(0, outcome.failed, "${outcome.failed} / ${outcome.total} 条一致性向量失败")
    }

    /** 规则库本身应当能被解析出来，且规模合理。 */
    @Test
    fun bundledRuleSetLoads() {
        val set = RulesManager.loadBundledRuleSet()
        assertTrue(set.rules.size > 1000, "规则库看起来没被正确打包：${set.rules.size} 条")
        assertTrue(set.rules.all { it.regexFilter.isNotEmpty() }, "有规则的 regexFilter 是空的")
    }

    /**
     * 编辑器用的同步快算 [UrlCleaner.checkLocally] 只应该「算不了返回 null」，
     * **不应该算出跟 [UrlCleaner.check] 不一样的结果**。
     *
     * 两个循环是分开写的，这条测试就是防它们跑偏：拿全部向量同时跑两条路径，
     * 只要都能算出来就必须逐字段相等。
     */
    @Test
    fun localFastPathAgreesWithAsync() = runBlocking {
        val shared = RulesManager.loadBundledRuleSet()
        var compared = 0
        var total = 0

        for ((fileName, doc) in VectorRunner.loadFiles()) {
            for (c in doc.cases) {
                total++
                val rules = VectorRunner.resolveRules(c, shared, stripRedirects = true)
                val cleaner = UrlCleaner(rules = rules)

                val async = cleaner.check(c.input)
                val local = cleaner.checkLocally(c.input)
                if (local == null) {
                    throw AssertionError("$fileName :: ${c.name} 没配 follower 却在同步路径放弃")
                }
                compared++
                assertEquals(local, async, "$fileName :: ${c.name} 同步/异步结果不一致")
            }
        }
        println("checkLocally 与 check 在 $compared / $total 条向量上逐字段一致")
        assertEquals(total, compared)
    }
}
