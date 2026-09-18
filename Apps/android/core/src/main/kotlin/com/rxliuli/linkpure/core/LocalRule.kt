package com.rxliuli.linkpure.core

import kotlinx.serialization.Serializable

/**
 * 用户自定义规则 = 规则本体 + 启用开关。
 *
 * 与 Flutter 版的 `LocalRule` 对应：**共享规则库是只读的**，不可启用/禁用；
 * 只有用户规则带 enabled 状态。
 */
@Serializable
data class LocalRule(
    val rule: Rule,
    val enabled: Boolean = true,
    /** 编辑时用的测试 URL。**不参与匹配**，只是记住上次验证用的输入（参照 Redirector）。 */
    val testUrl: String? = null,
) {
    val id: String get() = rule.id
}

/**
 * 规则文件的磁盘格式。
 *
 * 为什么不用 `SharedPreferences`：它是**按包名/进程分域**的，
 * 一旦包名变化（开发期很常见）或需要跨版本迁移，数据就「凭空消失」——
 * 与 Swift 侧避开 `UserDefaults` 是同一个理由。
 */
@Serializable
data class RuleFile(
    val version: Int = CURRENT_VERSION,
    val rules: List<LocalRule>,
) {
    companion object {
        const val CURRENT_VERSION = 1
    }
}

/** 规则数据的解码 —— 要能读懂**历史上出现过的几种形状**。 */
object RuleFileCodec {

    /**
     * 依次尝试：
     *   1. `{"version": 1, "rules": [...]}`  ← 本实现的文件格式
     *   2. `[{...}, {...}]`                  ← 裸数组（Flutter 版的 `flutter.local_rules` 就是这种）
     */
    fun decode(text: String): List<LocalRule> {
        runCatching { LinkPureJson.decodeFromString<RuleFile>(text) }
            .getOrNull()
            ?.let { return it.rules }
        return LinkPureJson.decodeFromString(text)
    }

    fun encode(rules: List<LocalRule>): String = LinkPureJson.encodeToString(RuleFile(rules = rules))
}

/**
 * 导入/导出的交换格式。
 *
 * 与 Flutter 版保持一致：**只有 `regexSubstitution` 类型的规则可以导出**
 * （`removeParams` / `followRedirect` 表达不了 from→to 结构）。
 */
@Serializable
data class ExportedRule(
    val id: String,
    val from: String,
    val to: String,
    val enabled: Boolean = true,
    /** 编辑时用的测试 URL。Flutter 版的导出没有这一项，缺省为 null，两边文件仍互相可读。 */
    val testUrl: String? = null,
)

class RuleExchangeException(message: String) : Exception(message)

/**
 * 导出的结果。
 *
 * [skipped] 是导不出去的规则 id：`removeParams` / `followRedirect` 型表达不了 from→to 结构。
 * 刻意**不报错**——Flutter 参考实现也是跳过的（`.where((r) => r.regexSubstitution != null)`），
 * 而 Swift 侧现在是抛异常，结果是「有一条删参数规则就整包导不出去」。
 * 把数量告诉用户比直接拦住他有用。
 */
data class ExportResult(val json: String, val skipped: List<String>)

object RuleExchange {

    /** 导出用户规则为 JSON。导不出去的记在 [ExportResult.skipped] 里。 */
    fun export(rules: List<LocalRule>): ExportResult {
        val exported = ArrayList<ExportedRule>(rules.size)
        val skipped = ArrayList<String>()
        for (local in rules) {
            val to = local.rule.regexSubstitution
            if (to.isNullOrEmpty()) {
                skipped.add(local.rule.id)
                continue
            }
            exported.add(
                ExportedRule(
                    id = local.rule.id,
                    from = local.rule.regexFilter,
                    to = to,
                    enabled = local.enabled,
                    testUrl = local.testUrl,
                ),
            )
        }
        return ExportResult(LinkPureJson.encodeToString(exported), skipped)
    }

    /** 从 JSON 导入；[merge] = true 时按 id 去重合并，否则整体替换。 */
    fun `import`(text: String, merge: Boolean, existing: List<LocalRule>): List<LocalRule> {
        val decoded = runCatching { LinkPureJson.decodeFromString<List<ExportedRule>>(text) }
            .getOrElse { throw RuleExchangeException("JSON 格式不正确：期望一个规则数组") }

        val incoming = decoded.map { exported ->
            LocalRule(
                rule = Rule(
                    id = exported.id,
                    regexFilter = exported.from,
                    regexSubstitution = exported.to,
                ),
                enabled = exported.enabled,
                testUrl = exported.testUrl,
            )
        }
        if (!merge) return incoming

        val result = existing.toMutableList()
        val ids = result.map { it.id }.toMutableSet()
        for (rule in incoming) {
            if (ids.add(rule.id)) result.add(rule)
        }
        return result
    }
}

/**
 * 规则集组合：把草稿规则放进完整规则集里。
 *
 * 用于编辑器的「测试」——**不能只测草稿规则本身**，否则会与真实行为不一致
 * （别的规则可能先把 URL 改成草稿能匹配的样子）。语义与 Redirector 一致：
 *   - 编辑已有规则 → **原位替换**（保留它的优先级位置）
 *   - 新增规则 → **放到最前**（新规则优先）
 */
object RuleComposition {
    fun withDraft(draft: Rule, rules: List<Rule>): List<Rule> {
        val index = rules.indexOfFirst { it.id == draft.id }
        if (index < 0) return listOf(draft) + rules
        val copy = rules.toMutableList()
        copy[index] = draft
        return copy
    }
}

/**
 * 编辑器弹窗的**打开前预览**。
 *
 * 弹窗的内容在出现的那一帧就完成布局：若让编辑器自己在协程里算，
 * 弹窗会先以「没有结果」的高度出现、拿到结果后再长高一次——肉眼就是一次闪烁。
 * 所以先在这里同步算一把。
 *
 * 放在 core 而不是视图里，是为了能直接测。
 */
object RuleEditingPreview {

    /**
     * 返回 null = **算不出预览**：测试 URL 为空或不合法。
     *
     * 注意：命中了 `followRedirect` 的规则**不算**算不出——编辑器用的 cleaner
     * 本来就不配 follower（不能因为打开个弹窗就去联网），那条规则等同「这一步不改写」。
     *
     * @param ruleset **已经组好的**规则集（草稿已按优先级放进去，见 [RuleComposition.withDraft]）。
     */
    fun compute(testUrl: String?, ruleset: List<Rule>): MatchResult? {
        val trimmed = testUrl?.trim().orEmpty()
        if (trimmed.isEmpty() || !UrlCleaner.isValidUrl(trimmed)) return null
        return UrlCleaner(rules = ruleset).checkLocally(trimmed)
    }
}

/**
 * 从 Flutter 版迁移用户规则。
 *
 * Flutter 版把规则存在 `SharedPreferences` 的 **`flutter.local_rules`** 键下，
 * 值是 JSON **字符串**，内容是一个数组：
 *
 * ```json
 * [{"rule":{"id":"01kb…","regexFilter":"…","regexSubstitution":"…"},"enabled":true}]
 * ```
 *
 * 形状与本实现的 [LocalRule] 完全一致，所以可以直接解码——
 * 但**必须显式做一次迁移**，否则原生版替换上去之后老用户的规则就丢了。
 *
 * 读取 `SharedPreferences` 那一步依赖 Android，放在 `app` 模块；
 * 这里只放与平台无关的解码。
 */
object FlutterRuleMigration {

    const val DEFAULT_KEY = "flutter.local_rules"

    fun decode(json: String): List<LocalRule>? {
        val rules = runCatching { LinkPureJson.decodeFromString<List<LocalRule>>(json) }.getOrNull()
        return rules?.takeIf { it.isNotEmpty() }
    }
}
