package com.rxliuli.linkpure.core

import kotlinx.serialization.Serializable

/**
 * 一条 URL 改写规则。
 *
 * 字段与 `shared-rules.json`（规则库）一一对应，因此这个类型同时也是
 * **跨语言数据契约**的一部分——Dart / Rust / Swift / Kotlin 四份实现共用它。
 */
@Serializable
data class Rule(
    val id: String,
    val regexFilter: String,
    val regexSubstitution: String? = null,
    val removeParams: List<String>? = null,
    val followRedirect: Boolean? = null,
)

/** 规则库文件的顶层结构。 */
@Serializable
data class RuleSet(
    val name: String = "",
    val description: String = "",
    val rules: List<Rule>,
)

sealed class LinkPureError(message: String) : Exception(message) {
    class ResourceMissing(val name: String) : LinkPureError("缺少资源：$name")
}
