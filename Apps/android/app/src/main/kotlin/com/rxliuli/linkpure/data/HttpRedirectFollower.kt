package com.rxliuli.linkpure.data

import com.rxliuli.linkpure.core.RedirectFollower
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL

/**
 * `followRedirect` 规则用：手动逐跳请求，不自动跟随。
 *
 * 只在**命中短链规则**时才会被调用（见 `Cleaner`），所以这里超时给得比较短。
 */
class HttpRedirectFollower(
    private val maxRedirects: Int = 10,
    private val connectTimeoutMs: Int = 2500,
    private val readTimeoutMs: Int = 2500,
) : RedirectFollower {

    override suspend fun follow(url: String): String? = withContext(Dispatchers.IO) {
        runCatching {
            var current = url
            for (i in 0 until maxRedirects) {
                val conn = URL(current).openConnection() as HttpURLConnection
                val next = try {
                    conn.instanceFollowRedirects = false
                    conn.requestMethod = "GET"
                    conn.connectTimeout = connectTimeoutMs
                    conn.readTimeout = readTimeoutMs
                    val code = conn.responseCode
                    if (code in 300..399) {
                        conn.getHeaderField("Location")?.let {
                            // Location 可能是相对路径
                            URL(URL(current), it).toString()
                        }
                    } else {
                        null
                    }
                } finally {
                    conn.disconnect()
                }
                if (next == null) return@runCatching current
                current = next
            }
            current
        }.getOrNull() // 网络/超时等错误 → 视为规则不匹配
    }
}
