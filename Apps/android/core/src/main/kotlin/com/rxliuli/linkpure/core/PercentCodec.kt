package com.rxliuli.linkpure.core

import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

/**
 * 两种 percent-decode，语义不同，规范里明确区分（见 conformance/README.md 第 5、6 条）：
 *
 * - **捕获组**用 [decodeComponent]：**不**把 `+` 当空格（对应 Dart `Uri.decodeComponent`）
 * - **query 参数名**用 [decodeQueryComponent]：`+` → 空格（对应 Dart `Uri.decodeQueryComponent`，
 *   与浏览器表单一致）
 *
 * 注意**不要**用 `java.net.URLDecoder`：
 * 它总是把 `+` 当空格，用在捕获组上会与 Dart 参考实现分歧。
 *
 * 解码失败（非法转义 / 非法 UTF-8 序列）时**原样返回**，
 * 与 Swift 的 `removingPercentEncoding ?? s` 对齐；Dart 侧是 try/catch 后原样返回。
 */
internal object PercentCodec {

    fun decodeComponent(s: String): String = runCatching { decode(s, plusAsSpace = false) }.getOrDefault(s)

    fun decodeQueryComponent(s: String): String = runCatching { decode(s, plusAsSpace = true) }.getOrDefault(s)

    private fun decode(s: String, plusAsSpace: Boolean): String {
        val out = StringBuilder(s.length)
        val bytes = ArrayList<Byte>(8)

        fun flush() {
            if (bytes.isEmpty()) return
            out.append(decodeUtf8Strict(bytes.toByteArray()))
            bytes.clear()
        }

        var i = 0
        while (i < s.length) {
            val c = s[i]
            when {
                c == '%' -> {
                    if (i + 2 >= s.length) throw IllegalArgumentException("截断的转义序列")
                    val hi = Character.digit(s[i + 1], 16)
                    val lo = Character.digit(s[i + 2], 16)
                    if (hi < 0 || lo < 0) throw IllegalArgumentException("非法转义序列")
                    bytes.add(((hi shl 4) or lo).toByte())
                    i += 3
                }

                plusAsSpace && c == '+' -> {
                    flush()
                    out.append(' ')
                    i++
                }

                else -> {
                    flush()
                    out.append(c)
                    i++
                }
            }
        }
        flush()
        return out.toString()
    }

    /**
     * 严格 UTF-8：遇到非法字节序列**抛异常**而不是替换成 U+FFFD。
     * 这样调用方会退回到原串，和 Dart/Swift 的行为一致。
     */
    private fun decodeUtf8Strict(bytes: ByteArray): String {
        val decoder = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        return decoder.decode(ByteBuffer.wrap(bytes)).toString()
    }
}
