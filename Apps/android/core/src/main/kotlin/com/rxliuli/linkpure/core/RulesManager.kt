package com.rxliuli.linkpure.core

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.json.Json
import kotlin.random.Random

/**
 * 全局 JSON 配置。
 *
 * - `ignoreUnknownKeys`：规则库/向量文件里有 `comment`、`title` 之类我们不需要的字段
 * - `explicitNulls = false`：输出时省略 null（与 Swift 的 `JSONEncoder` 默认行为一致）
 * - `encodeDefaults = true`：**不能省**。Swift 的 `LocalRule` / `RuleFile` 里 `enabled`、
 *   `version` 都是非可选、无默认值的属性，`Codable` 遇到缺键会**直接解码失败**——
 *   省了默认值就等于写出一份 Swift 读不了的规则文件。
 */
@OptIn(ExperimentalSerializationApi::class)
internal val LinkPureJson = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    encodeDefaults = true
    prettyPrint = true
    prettyPrintIndent = "  "
}

object RulesManager {

    /** 加载打进包里的共享规则库。 */
    fun loadBundledRuleSet(): RuleSet {
        val stream = RulesManager::class.java.getResourceAsStream("/shared-rules.json")
            ?: throw LinkPureError.ResourceMissing("shared-rules.json")
        return LinkPureJson.decodeFromString(stream.readBytes().decodeToString())
    }

    fun loadBundledRules(includeRedirects: Boolean = true): List<Rule> {
        val set = loadBundledRuleSet()
        if (includeRedirects) return set.rules
        return set.rules.filter { it.followRedirect != true }
    }

    /**
     * 新用户规则的 id：ULID（26 字符 Crockford Base32，前 48 位时间戳 + 80 位随机）。
     *
     * 与 Flutter 版的 `Ulid().toString()` 同构，好处有两个：
     *   - **字典序 = 创建顺序**，列表顺序天然稳定；
     *   - 时间戳之外还有随机位，**同一毫秒内连续新增也不会撞 id**。
     */
    fun newUserRuleId(now: Long = System.currentTimeMillis(), random: Random = Random.Default): String {
        val alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
        var value = now
        val chars = CharArray(26) { '0' }

        // 时间戳 48 位 → 前 10 个字符
        for (i in 9 downTo 0) {
            chars[i] = alphabet[(value and 0x1FL).toInt()]
            value = value shr 5
        }
        // 随机 80 位 → 后 16 个字符
        for (i in 10 until 26) {
            chars[i] = alphabet[random.nextInt(32)]
        }
        return String(chars)
    }
}
