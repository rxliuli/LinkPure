package com.rxliuli.linkpure.core

import java.util.Optional
import java.util.concurrent.ConcurrentHashMap
import java.util.regex.Pattern

enum class CheckStatus(val wire: String) {
    MATCHED("matched"),
    NOT_MATCHED("notMatched"),
    CIRCULAR_REDIRECT("circularRedirect"),
    INFINITE_REDIRECT("infiniteRedirect"),
    ;

    companion object {
        fun fromWire(value: String): CheckStatus? = entries.firstOrNull { it.wire == value }
    }
}

data class MatchResult(
    val status: CheckStatus,
    /** `matched` 时为改写后的 URL；`notMatched` 时**等于输入**（规范规定）。 */
    val url: String,
    val chain: List<String>,
)

/**
 * 跟随重定向（`followRedirect` 规则用）。
 *
 * 抽成接口是为了让测试注入假实现——网络调用不能进 golden 向量。
 * 真实实现（见 `app` 模块）应放在 IO 线程上跑。
 */
fun interface RedirectFollower {
    suspend fun follow(url: String): String?
}

/**
 * 规则引擎。行为契约见 LinkPure 仓库的 `conformance/README.md`。
 *
 * **正则风味**：规范要求 `\d` / `\w` / `\s` 按 **ASCII** 解释。
 * Java 的 `Pattern` 默认就是 ASCII（`\d` = `[0-9]`、`\w` = `[a-zA-Z_0-9]`），
 * 因此**不需要** Swift 那边 `asciiRewrite()` 那种改写。
 * 唯一的风险是有人用 `-Djava.util.regex.UNICODE_CHARACTER_CLASS=true` 全局打开 Unicode 语义
 * —— `05-regex-flavor.json` 那 9 条向量就是盯着这件事的。
 */
class UrlCleaner(
    private val rules: List<Rule>,
    private val follower: RedirectFollower? = null,
) {

    suspend fun check(url: String): MatchResult {
        if (!isValidUrl(url)) return notMatched(url)

        var current = url
        val chain = ArrayList<String>()

        repeat(MAX_REDIRECTS) {
            var matched = false
            for (rule in rules) {
                val outcome = matchWithRuleLocally(rule, current) ?: continue
                val newUrl: String = when (outcome) {
                    is LocalOutcome.Rewritten -> outcome.url
                    LocalOutcome.NeedsNetwork -> {
                        // 只有 followRedirect 要联网。没配 follower 时与原行为一致：
                        // 视为「这一步不改写」，继续看下一条规则。
                        val f = follower ?: continue
                        f.follow(current) ?: current
                    }
                }
                // 幂等：命中但没改变 URL，不算命中，继续看下一条规则
                if (newUrl.isEmpty() || newUrl == current) continue

                if (chain.contains(newUrl)) {
                    return MatchResult(CheckStatus.CIRCULAR_REDIRECT, newUrl, chain.toList())
                }
                chain.add(newUrl)
                current = newUrl
                matched = true
                break
            }
            if (!matched) {
                return if (chain.isEmpty()) {
                    notMatched(url)
                } else {
                    MatchResult(CheckStatus.MATCHED, current, chain.toList())
                }
            }
        }
        return MatchResult(CheckStatus.INFINITE_REDIRECT, current, chain.toList())
    }

    /**
     * **不联网的同步快算**：拿不到答案时返回 null。
     *
     * 规则的匹配/替换/删参数本来就同步，只有 `followRedirect` 要联网。
     * 界面用它在弹窗出现**前**把结果算好，免得弹窗先以「没有结果」的高度出现、
     * 拿到结果后再长高一次——肉眼就是一次闪烁。
     *
     * 只有**配了 follower**（要真去跟随重定向）且正好命中那种规则时才返回 null；
     * 没配 follower 时结果完全确定，照常返回。
     *
     * 语义与 [check] 一致：返回非 null 时结果**逐字段相等**
     * （`ConformanceTest.localFastPathAgreesWithAsync` 拿全部向量盯着）。
     */
    fun checkLocally(url: String): MatchResult? {
        if (!isValidUrl(url)) return notMatched(url)

        var current = url
        val chain = ArrayList<String>()

        repeat(MAX_REDIRECTS) {
            var matched = false
            for (rule in rules) {
                val outcome = matchWithRuleLocally(rule, current) ?: continue
                val newUrl: String = when (outcome) {
                    is LocalOutcome.Rewritten -> outcome.url
                    LocalOutcome.NeedsNetwork -> {
                        // 没配 follower → 这一步不改写（与 check 一致）；
                        // 配了 → 答案在网络上，同步路径放弃。
                        if (follower != null) return null
                        continue
                    }
                }
                if (newUrl.isEmpty() || newUrl == current) continue

                if (chain.contains(newUrl)) {
                    return MatchResult(CheckStatus.CIRCULAR_REDIRECT, newUrl, chain.toList())
                }
                chain.add(newUrl)
                current = newUrl
                matched = true
                break
            }
            if (!matched) {
                return if (chain.isEmpty()) {
                    notMatched(url)
                } else {
                    MatchResult(CheckStatus.MATCHED, current, chain.toList())
                }
            }
        }
        return MatchResult(CheckStatus.INFINITE_REDIRECT, current, chain.toList())
    }

    // MARK: 单条规则

    private sealed interface LocalOutcome {
        data class Rewritten(val url: String) : LocalOutcome

        /** 命中，但要跟随重定向才能得到结果（联网） */
        data object NeedsNetwork : LocalOutcome
    }

    /**
     * 单条规则的**同步**部分：正则是否命中 + 就地改写。
     * 返回 null 表示规则没命中。[check] 与 [checkLocally] 共用它，避免两条路径跑偏。
     */
    private fun matchWithRuleLocally(rule: Rule, url: String): LocalOutcome? {
        val regex = compile(rule.regexFilter) ?: return null
        if (!regex.matcher(url).find()) return null

        val sub = rule.regexSubstitution
        if (!sub.isNullOrEmpty()) return LocalOutcome.Rewritten(applyRegexSubstitution(rule, url))

        val params = rule.removeParams
        if (!params.isNullOrEmpty()) return LocalOutcome.Rewritten(removeQueryParameters(url, params))

        if (rule.followRedirect == true) return LocalOutcome.NeedsNetwork

        return LocalOutcome.Rewritten(url)
    }

    // MARK: 正则替换

    private fun applyRegexSubstitution(rule: Rule, url: String): String {
        val regex = compile(rule.regexFilter) ?: return url
        val m = regex.matcher(url)
        if (!m.find()) return url

        var result = rule.regexSubstitution ?: ""
        for (i in 1..m.groupCount()) {
            // 未参与匹配的捕获组返回 null → 空串（与 Dart 的 `?? ''` 一致）
            val captured = m.group(i) ?: ""
            // 捕获组先 percent-decode（**不**把 '+' 当空格）；保留原大小写
            result = result.replace("\$$i", PercentCodec.decodeComponent(captured))
        }
        return result
    }

    // MARK: 参数移除

    /**
     * 按**原始 query 串**逐对处理：不折叠重复参数、不改变顺序、不重新编码、
     * 不省略默认端口；参数全空时去掉整个 `?`（即便后面还有 `#fragment`）。
     */
    private fun removeQueryParameters(url: String, paramsToRemove: List<String>): String {
        val qIndex = url.indexOf('?')
        if (qIndex < 0) return url

        val head = url.substring(0, qIndex)
        var rest = url.substring(qIndex + 1)

        var fragment = ""
        val fIndex = rest.indexOf('#')
        if (fIndex >= 0) {
            fragment = rest.substring(fIndex)
            rest = rest.substring(0, fIndex)
        }
        if (rest.isEmpty()) return url

        val kept = ArrayList<String>()
        var removed = false
        for (pair in rest.split("&")) {
            if (pair.isEmpty()) continue
            val eq = pair.indexOf('=')
            val rawKey = if (eq < 0) pair else pair.substring(0, eq)
            if (paramMatches(PercentCodec.decodeQueryComponent(rawKey), paramsToRemove)) {
                removed = true
            } else {
                kept.add(pair)
            }
        }
        if (!removed) return url

        val out = StringBuilder(head)
        if (kept.isNotEmpty()) {
            out.append('?').append(kept.joinToString("&"))
        }
        out.append(fragment)
        return out.toString()
    }

    /**
     * **先精确匹配，再试正则**：参数名本身可能含 `$` `(` 等字符（Branch 的 `$3p` /
     * `$deep_link`），它们是字面量，不能被误当正则（`$` 是行尾锚点 → 会永久失效）。
     * 参数名匹配**区分大小写**（与规则匹配不同）。
     */
    private fun paramMatches(key: String, patterns: List<String>): Boolean {
        for (pattern in patterns) {
            if (key == pattern) return true
            if (!containsRegexMeta(pattern)) continue
            val re = compile(pattern, caseInsensitive = false) ?: continue
            if (re.matcher(key).find()) return true
        }
        return false
    }

    // MARK: 工具

    private fun notMatched(url: String) = MatchResult(CheckStatus.NOT_MATCHED, url, emptyList())

    companion object {
        /** 一条 URL 最多被改写几次（超过就判定无限重定向）。 */
        private const val MAX_REDIRECTS = 5

        private const val REGEX_META = "^$()[]{}*+?|\\"

        private val SCHEME_EXTRA = charArrayOf('+', '-', '.')

        /** 编译缓存：1061 条规则 × 最多 5 轮迭代，不缓存的话每条 URL 要编译五千次。 */
        private val patternCache = ConcurrentHashMap<String, Optional<Pattern>>()

        private fun containsRegexMeta(s: String): Boolean = s.any { it in REGEX_META }

        /**
         * 规则匹配**大小写不敏感**（与 Redirector 一致）。
         *
         * Java 的 `CASE_INSENSITIVE` 单独使用时只做 ASCII 折叠（要 `UNICODE_CASE` 才是
         * Unicode 折叠）—— 这正是规范想要的，与 `\d`/`\w` 的 ASCII 语义一致。
         */
        internal fun compile(pattern: String, caseInsensitive: Boolean = true): Pattern? {
            val key = (if (caseInsensitive) "i\u0000" else "s\u0000") + pattern
            return patternCache.computeIfAbsent(key) {
                try {
                    Optional.of(
                        Pattern.compile(pattern, if (caseInsensitive) Pattern.CASE_INSENSITIVE else 0),
                    )
                } catch (_: Exception) {
                    // 非法正则 → 视为不匹配，不崩溃
                    Optional.empty()
                }
            }.orElse(null)
        }

        /**
         * 仅 `http` / `https` 视为 URL（规范第 1 条）。
         *
         * 与 Dart 的 `Uri.parse(text).hasScheme` 对齐：scheme 大小写不敏感，
         * 且**不要求**后面有 `://`（`http:foo` 在 Dart 里也算有 scheme）。
         */
        fun isValidUrl(text: String): Boolean {
            val colon = text.indexOf(':')
            if (colon <= 0) return false

            val scheme = text.substring(0, colon)
            if (!scheme[0].isLetter()) return false
            for (c in scheme) {
                if (!c.isLetterOrDigit() && c !in SCHEME_EXTRA) return false
            }
            return scheme.equals("http", ignoreCase = true) || scheme.equals("https", ignoreCase = true)
        }
    }
}
