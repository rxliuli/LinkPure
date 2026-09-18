package com.rxliuli.linkpure.clean

import com.rxliuli.linkpure.core.CheckStatus
import com.rxliuli.linkpure.core.MatchResult
import com.rxliuli.linkpure.core.UrlCleaner
import com.rxliuli.linkpure.data.HttpRedirectFollower
import com.rxliuli.linkpure.data.RuleStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * 清洗一次。这是 app 的全部业务逻辑——其余都是壳。
 */
object Cleaner {

    /**
     * 短链展开最多等这么久。
     *
     * 只有**命中 `followRedirect` 规则**时才可能走进这条路（13 条，都是短链展开），
     * 其余情况 `checkLocally` 当场就有答案、完全不联网。
     * 超时就用「不联网」的结果兜底——宁可少展开一个短链，也不要让选区卡在那里。
     */
    private const val NETWORK_TIMEOUT_MS = 1500L

    data class Outcome(
        val input: String,
        val output: String,
        val status: CheckStatus,
        /** 通知里显示的一句话，例如 "3 params removed"。没变化时为空。 */
        val summary: String,
    ) {
        val isUrl: Boolean get() = UrlCleaner.isValidUrl(input)

        val changed: Boolean get() = status == CheckStatus.MATCHED && output != input
    }

    suspend fun clean(text: String): Outcome = withContext(Dispatchers.IO) {
        if (!UrlCleaner.isValidUrl(text)) {
            return@withContext Outcome(text, text, CheckStatus.NOT_MATCHED, "")
        }

        val rules = RuleStore.rulesForCleaning()
        if (rules.isEmpty()) {
            return@withContext Outcome(text, text, CheckStatus.NOT_MATCHED, "")
        }

        val withNetwork = UrlCleaner(rules, HttpRedirectFollower())
        val result = withNetwork.checkLocally(text)
            // null = 命中了要联网的规则。给它一个上限，超时就退回不联网的结果。
            ?: withTimeoutOrNull(NETWORK_TIMEOUT_MS) { withNetwork.check(text) }
            ?: UrlCleaner(rules, null).checkLocally(text)
            ?: MatchResult(CheckStatus.NOT_MATCHED, text, emptyList())

        Outcome(text, result.url, result.status, summarize(text, result.url, result.status))
    }

    private fun summarize(input: String, output: String, status: CheckStatus): String {
        if (status != CheckStatus.MATCHED || output == input) return ""
        val removed = queryParamCount(input) - queryParamCount(output)
        // 只在「去了几个参数」时补一句。
        // 曾经在 removed == 0 时回一句「URL rewritten」——那只是在把 URL 重复一遍，
        // 而且通知里显示 URL 才是正事。
        return if (removed > 0) "$removed param${if (removed == 1) "" else "s"} removed" else ""
    }

    private fun queryParamCount(url: String): Int {
        val start = url.indexOf('?')
        if (start < 0) return 0
        val hash = url.indexOf('#')
        val end = if (hash < 0) url.length else hash
        if (end <= start + 1) return 0
        return url.substring(start + 1, end).split('&').count { it.isNotEmpty() }
    }
}
