package com.rxliuli.linkpure.core

import kotlinx.serialization.Serializable
import java.io.File

// MARK: - 向量格式（见 LinkPure(Flutter) 仓库 conformance/README.md）

@Serializable
internal data class VectorFile(
    val version: Int = 1,
    val name: String? = null,
    val comment: String? = null,
    val cases: List<VectorCase> = emptyList(),
)

@Serializable
internal data class VectorCase(
    val name: String? = null,
    val comment: String? = null,
    val rules: List<Rule>? = null,
    val ruleRef: String? = null,
    val ruleset: String? = null,
    val input: String,
    val expect: Expect? = null,
) {
    @Serializable
    internal data class Expect(val status: String, val output: String)
}

/**
 * 用 LinkPure 仓库 `conformance/` 下的**语言无关向量**验证本实现。
 *
 * 这些向量同时被 Dart（参考实现）、Rust 与 Swift 跑过；零分歧 = 规范真正可执行。
 */
internal object VectorRunner {

    data class Outcome(
        val total: Int,
        val failed: Int,
        val failures: List<String>,
        /** (文件名, 用例数, 失败数) */
        val perFile: List<Triple<String, Int, Int>>,
    )

    /**
     * 向量文件目录。
     *
     * 1. 系统属性 `linkpure.vectorsDir` —— `core/build.gradle.kts` 里的 `syncVectors` 指过来
     * 2. 回退：从工作目录往上找 `Tests/LinkPureCoreTests/Vectors`（IDE 里直接跑测试时）
     *
     * 向量**不打包进产物**——它们只是测试数据，没必要进 APK。
     */
    private fun vectorDir(): File {
        System.getProperty("linkpure.vectorsDir")
            ?.let { File(it) }
            ?.takeIf { it.isDirectory }
            ?.let { return it }

        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, "Tests/LinkPureCoreTests/Vectors")
            if (candidate.isDirectory) return candidate
            dir = dir.parentFile
        }
        throw LinkPureError.ResourceMissing("向量目录 Tests/LinkPureCoreTests/Vectors")
    }

    /** 全部向量文件，按文件名排序。 */
    fun loadFiles(): List<Pair<String, VectorFile>> {
        val files = vectorDir().listFiles { f: File -> f.extension == "json" }
            ?: throw LinkPureError.ResourceMissing("向量目录不是目录：${vectorDir()}")
        return files.sortedBy { it.name }.map { it.name to parse(it.readText()) }
    }

    private fun parse(text: String): VectorFile = LinkPureJson.decodeFromString(text)

    /**
     * 规则集解析优先级：`rules`（内联） > `ruleRef`（单条共享规则） > 默认整库。
     */
    fun resolveRules(case: VectorCase, shared: RuleSet, stripRedirects: Boolean): List<Rule> {
        val rules = when {
            case.rules != null -> case.rules
            case.ruleRef != null -> shared.rules.filter { it.id == case.ruleRef }
            else -> shared.rules
        }
        // followRedirect 依赖网络，不进 golden 向量；runner 默认剔除这类规则。
        return if (stripRedirects) rules.filter { it.followRedirect != true } else rules
    }

    suspend fun run(shared: RuleSet, stripRedirects: Boolean = true): Outcome {
        var total = 0
        var failed = 0
        val failures = ArrayList<String>()
        val perFile = ArrayList<Triple<String, Int, Int>>()

        for ((fileName, doc) in loadFiles()) {
            var fileFailed = 0
            for (c in doc.cases) {
                total++
                val rules = resolveRules(c, shared, stripRedirects)
                val result = UrlCleaner(rules = rules).check(c.input)
                val expect = c.expect ?: continue

                // notMatched 时规范规定 output 等于 input，本实现直接返回输入，无需归一化
                if (result.status.wire != expect.status || result.url != expect.output) {
                    failed++
                    fileFailed++
                    failures.add(
                        """
                        $fileName :: ${c.name ?: "(未命名)"}
                                input : ${c.input}
                                expect: ${expect.status}  ${expect.output}
                                actual: ${result.status.wire}  ${result.url}
                        """.trimIndent(),
                    )
                }
            }
            perFile.add(Triple(fileName, doc.cases.size, fileFailed))
        }
        return Outcome(total, failed, failures, perFile)
    }
}
