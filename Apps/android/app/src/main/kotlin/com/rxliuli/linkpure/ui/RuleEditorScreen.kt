package com.rxliuli.linkpure.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.rxliuli.linkpure.core.CheckStatus
import com.rxliuli.linkpure.core.LocalRule
import com.rxliuli.linkpure.core.MatchResult
import com.rxliuli.linkpure.core.Rule
import com.rxliuli.linkpure.core.RuleComposition
import com.rxliuli.linkpure.core.RuleEditingPreview
import com.rxliuli.linkpure.core.RulesManager
import com.rxliuli.linkpure.core.UrlCleaner
import com.rxliuli.linkpure.data.HttpRedirectFollower
import com.rxliuli.linkpure.data.RuleStore
import kotlinx.coroutines.delay
import java.util.regex.Pattern

/**
 * 规则编辑器。
 *
 * **只编辑「一个正则 + 一个替换目标」**——这就是用户规则的全部模型，与 Flutter
 * （`rule_edit_page.dart` 里根本没有 `removeParams`）和 iOS/macOS 的 `RuleEditorView`
 * 三者一致。
 *
 * `removeParams` / `followRedirect` 是**内置规则库用的机制**：引擎支持、列表里只读展示
 * （「removes utm_x」），但从不给用户编。少了这个约束，用户能造出一种**永远导不出去**的
 * 规则（导出格式只能表达 from→to），那是个陷阱。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RuleEditorScreen(initial: LocalRule?, onSave: (LocalRule) -> Unit, onClose: () -> Unit) {
    val isNew = initial == null

    // 新建时就把 id 定下来：ULID 的字典序 = 创建顺序，列表顺序天然稳定
    val id = remember { initial?.id ?: RulesManager.newUserRuleId() }

    var filter by remember { mutableStateOf(initial?.rule?.regexFilter.orEmpty()) }
    var substitution by remember { mutableStateOf(initial?.rule?.regexSubstitution.orEmpty()) }
    var testUrl by remember { mutableStateOf(initial?.testUrl.orEmpty()) }

    val regexError = remember(filter) {
        if (filter.isEmpty()) {
            null
        } else {
            runCatching { Pattern.compile(filter) }.exceptionOrNull()?.let { it.message ?: "Invalid regular expression" }
        }
    }

    // 编辑器不碰的字段原样带回去，不能默默丢掉（iOS/macOS 的 RuleEditorView 也保留了
    // removeParams）。不过这类规则 Save 是灰的，所以实际上只在「原样打开又原样关闭」时走到。
    val draft = remember(filter, substitution) {
        Rule(
            id = id,
            regexFilter = filter,
            regexSubstitution = substitution,
            removeParams = initial?.rule?.removeParams,
            followRedirect = initial?.rule?.followRedirect,
        )
    }

    // 与 iOS/macOS 的 `canSave` 一致：替换目标为空就不让存。
    // 删参数型规则因此是只读的——它本来就只该由内置规则库提供。
    val canSave = filter.isNotEmpty() && regexError == null && substitution.isNotEmpty()

    val removesParams = !initial?.rule?.removeParams.isNullOrEmpty()

    // 打开编辑器的第一帧就把结果算好，免得先以「没有结果」的高度画一次再长高（肉眼是一次闪烁）。
    // 草稿要放进**完整规则集**里测——只测草稿本身会与真实行为不一致。
    val ruleset = remember(draft) { RuleComposition.withDraft(draft, RuleStore.rulesForCleaning()) }
    var preview by remember(ruleset, testUrl) {
        mutableStateOf(RuleEditingPreview.compute(testUrl, ruleset))
    }

    // 然后再用**异步路径**覆盖一次：同步的 checkLocally 不配 follower，
    // 所以命中 `followRedirect` 规则时它只会给出「没有匹配」。
    // iOS 的 `RuleEditorView` 也是这个两步（预先同步算 + `.task` 里 await check）。
    // 加 250ms 防抖：LaunchedEffect 的 key 一变就取消重开，打字时不会把网络打爆。
    LaunchedEffect(ruleset, testUrl) {
        val text = testUrl.trim()
        if (text.isEmpty() || !UrlCleaner.isValidUrl(text)) return@LaunchedEffect
        delay(250)
        preview = UrlCleaner(ruleset, HttpRedirectFollower()).check(text)
    }

    Column(Modifier.fillMaxSize()) {
        TopAppBar(
            title = { Text(if (isNew) "New rule" else "Edit rule") },
            navigationIcon = {
                IconButton(onClick = onClose) {
                    Icon(Icons.Filled.ArrowBack, contentDescription = "Cancel")
                }
            },
            actions = {
                TextButton(
                    onClick = {
                        onSave(
                            LocalRule(
                                rule = draft,
                                enabled = initial?.enabled ?: true,
                                testUrl = testUrl.ifBlank { null },
                            ),
                        )
                    },
                    enabled = canSave,
                ) { Text("Save") }
            },
        )

        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedTextField(
                value = filter,
                onValueChange = { filter = it },
                label = { Text("When the URL matches") },
                isError = regexError != null,
                supportingText = {
                    Text(regexError ?: "Regular expression, matched anywhere. Case-insensitive; \\d and \\w are ASCII-only.")
                },
                textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier.fillMaxWidth(),
            )

            OutlinedTextField(
                value = substitution,
                onValueChange = { substitution = it },
                label = { Text("Replace with") },
                isError = removesParams,
                supportingText = {
                    Text(
                        if (removesParams) {
                            "This rule removes query params — a built-in-library mechanism. " +
                                "Custom rules are from→to, so it can't be saved from here."
                        } else {
                            "Use \$1, \$2 … for capture groups. They are percent-decoded first."
                        },
                    )
                },
                textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                modifier = Modifier.fillMaxWidth(),
            )

            Card {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Test against the full ruleset", style = MaterialTheme.typography.titleSmall)
                    OutlinedTextField(
                        value = testUrl,
                        onValueChange = { testUrl = it },
                        label = { Text("Test URL") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    // preview 是委托属性（by remember { mutableStateOf }），做不了 smart cast
                    val result = preview
                    when {
                        testUrl.isBlank() -> Text(
                            "Paste a URL to check this rule together with the built-in ones.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )

                        result == null -> MessageRow(
                            icon = Icons.Filled.Info,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            title = "Not a valid http(s) URL",
                        )

                        else -> TestResultView(result)
                    }
                }
            }
        }
    }
}

/**
 * 测试结果。
 *
 * **重点是重写链（`MatchResult.chain`），不只是一个最终结果。**
 * 写规则的时候真正要回答的问题是「哪些规则按什么顺序依次命中了」——
 * 比如你自己那条没生效、其实是排在后面的内置规则先改掉了 URL。
 * 参考实现（Redirector）和 Swift 侧的 `RuleTestResultView` 都是这么展示的。
 */
@Composable
private fun TestResultView(result: MatchResult, chainLimit: Int = 6) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        when (result.status) {
            CheckStatus.MATCHED -> {
                MessageRow(
                    icon = Icons.Filled.CheckCircle,
                    tint = MaterialTheme.colorScheme.primary,
                    title = "Rewrite chain (${result.chain.size} steps)",
                )
                UrlChain(result.chain, limit = chainLimit)
            }

            CheckStatus.NOT_MATCHED -> MessageRow(
                icon = Icons.Filled.Info,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                title = "No matching rules found for this URL",
            )

            CheckStatus.CIRCULAR_REDIRECT -> {
                MessageRow(
                    icon = Icons.Filled.Refresh,
                    tint = MaterialTheme.colorScheme.error,
                    title = "Circular redirect",
                )
                UrlChain(result.chain, highlightLast = true, limit = chainLimit)
            }

            CheckStatus.INFINITE_REDIRECT -> {
                MessageRow(
                    icon = Icons.Filled.Warning,
                    tint = MaterialTheme.colorScheme.error,
                    title = "Maximum redirect limit exceeded",
                )
                UrlChain(result.chain, limit = 3)
            }
        }
    }
}

@Composable
private fun UrlChain(urls: List<String>, highlightLast: Boolean = false, limit: Int? = null) {
    val shown = if (limit == null) urls else urls.take(limit)
    val hidden = urls.size - shown.size

    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        shown.forEachIndexed { index, url ->
            val bad = highlightLast && index == shown.lastIndex
            Text(
                url,
                style = MaterialTheme.typography.bodySmall,
                fontFamily = FontFamily.Monospace,
                modifier = Modifier
                    .fillMaxWidth()
                    .background(
                        color = if (bad) {
                            MaterialTheme.colorScheme.errorContainer
                        } else {
                            MaterialTheme.colorScheme.surfaceVariant
                        },
                        shape = RoundedCornerShape(6.dp),
                    )
                    .padding(horizontal = 8.dp, vertical = 6.dp),
            )
        }
        if (hidden > 0) {
            Text(
                "… $hidden more step${if (hidden == 1) "" else "s"}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun MessageRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    tint: androidx.compose.ui.graphics.Color,
    title: String,
) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(18.dp))
        Text(title, style = MaterialTheme.typography.bodyMedium)
    }
}
