package com.rxliuli.linkpure.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxState
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.rxliuli.linkpure.core.LocalRule
import com.rxliuli.linkpure.core.Rule
import com.rxliuli.linkpure.data.RuleStore

/**
 * 两个列表的切换。用 `TabRow` 而不是自己摆两个按钮——
 * 它自带选中指示器、水波纹和横向滚动，而且位置和高度由系统定。
 */
@Composable
fun RulesTabContent(
    query: String,
    onEdit: (LocalRule) -> Unit,
    onDelete: (LocalRule) -> Unit,
) {
    // 一旦在搜索，就跨两个列表一起搜，并把 tab 藏起来。
    // 用户点搜索时脑子里是「找一条规则」，不是「在当前这个列表里找」——
    // 在「我的规则」里搜 youtube 却提示「没有匹配」，而内置库里明明有一堆，那是蠢的。
    if (query.isNotBlank()) {
        SearchResults(query, onEdit, onDelete)
        return
    }

    var tab by remember { mutableIntStateOf(0) }

    Column(Modifier.fillMaxSize()) {
        TabRow(selectedTabIndex = tab) {
            Tab(
                selected = tab == 0,
                onClick = { tab = 0 },
                text = { Text("My rules (${RuleStore.userRules.size})") },
            )
            Tab(
                selected = tab == 1,
                onClick = { tab = 1 },
                text = { Text("Built-in (${RuleStore.bundledRules.size})") },
            )
        }

        AnimatedContent(
            targetState = tab,
            transitionSpec = {
                val slide = tween<androidx.compose.ui.unit.IntOffset>(durationMillis = 200)
                val fade = tween<Float>(durationMillis = 200)
                if (targetState > initialState) {
                    (slideInHorizontally(slide) { it / 3 } + fadeIn(fade)) togetherWith
                        (slideOutHorizontally(slide) { -it / 3 } + fadeOut(fade))
                } else {
                    (slideInHorizontally(slide) { -it / 3 } + fadeIn(fade)) togetherWith
                        (slideOutHorizontally(slide) { it / 3 } + fadeOut(fade))
                }
            },
            label = "tab",
        ) { index ->
            if (index == 0) UserRulesList(onEdit, onDelete) else BuiltinRulesList()
        }
    }
}

@Composable
private fun SearchResults(
    query: String,
    onEdit: (LocalRule) -> Unit,
    onDelete: (LocalRule) -> Unit,
) {
    val q = query.trim()
    val mine = RuleStore.userRules.filter { ruleMatches(it.rule, q) }
    val builtin = remember(q) { RuleStore.bundledRules.filter { ruleMatches(it, q) } }

    if (mine.isEmpty() && builtin.isEmpty()) {
        EmptyState("No rules match “$q”.")
        return
    }

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (mine.isNotEmpty()) {
            item { ListHeader("My rules") }
            items(mine, key = { "u:${it.id}" }) { local ->
                SwipeToDelete(onDelete = { onDelete(local) }, modifier = Modifier.animateItem()) {
                    UserRuleRow(local, onClick = { onEdit(local) })
                }
            }
        }
        if (builtin.isNotEmpty()) {
            item { ListHeader("Built-in") }
            items(builtin, key = { "b:${it.id}" }) { BuiltinRuleRow(it) }
        }
    }
}

@Composable
private fun ListHeader(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = 4.dp, start = 4.dp),
    )
}

@Composable
private fun UserRulesList(onEdit: (LocalRule) -> Unit, onDelete: (LocalRule) -> Unit) {
    val rules = RuleStore.userRules

    if (rules.isEmpty()) {
        EmptyState("No custom rules yet.\nThe built-in library already covers 1000+ sites.")
        return
    }

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item {
            // 与 iOS 的 Section 头一致：一眼看出有几条在生效
            ListHeader("${RuleStore.enabledUserRuleCount} / ${rules.size} enabled")
        }
        items(rules, key = { it.id }) { local ->
            SwipeToDelete(onDelete = { onDelete(local) }, modifier = Modifier.animateItem()) {
                UserRuleRow(local, onClick = { onEdit(local) })
            }
        }
    }
}

@Composable
private fun BuiltinRulesList() {
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(RuleStore.bundledRules, key = { it.id }) { BuiltinRuleRow(it) }
    }
}

@Composable
private fun EmptyState(message: String) {
    Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
        Text(
            message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/**
 * 滑动删除。
 *
 * 删除只在这里做——行内不再放删除按钮，长按菜单也砍了。
 * 后者原本 5 项里有 3 项与行内控件/点整行重复（Edit / Enable / Delete），
 * 在**没有多选**的移动端，长按菜单只是重复动作的集散地（macOS 那边是
 * `contextMenu(forSelectionType:)`，作用于选中集，那才叫「上下文」菜单）。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeToDelete(
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    val density = LocalDensity.current
    // 这里刻意**不用** rememberSwipeToDismissBoxState：
    // 它内部是 rememberSaveable，而 LazyColumn 会按 item key 保存每一行的状态。
    // 于是「滑掉 → 删除 → 撤销恢复」时，同 key 的那一行会把「已滑出」的位置一起恢复回来，
    // 表现为内容滑到屏幕外、只剩背景色——规则回来了，但看起来是坏的。
    // 用 remember 就不会被保存，重新插回来时总是从 Settled 开始。
    val currentOnDelete by rememberUpdatedState(onDelete)
    val state = remember(density) {
        SwipeToDismissBoxState(
            initialValue = SwipeToDismissBoxValue.Settled,
            density = density,
            confirmValueChange = { value ->
                if (value == SwipeToDismissBoxValue.EndToStart) currentOnDelete()
                value == SwipeToDismissBoxValue.EndToStart
            },
            positionalThreshold = { distance -> distance * 0.5f },
        )
    }

    SwipeToDismissBox(
        state = state,
        modifier = modifier,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Box(
                Modifier
                    .fillMaxSize()
                    .background(
                        MaterialTheme.colorScheme.errorContainer,
                        RoundedCornerShape(12.dp),
                    )
                    .padding(horizontal = 20.dp),
                contentAlignment = Alignment.CenterEnd,
            ) {
                Text("Delete", color = MaterialTheme.colorScheme.onErrorContainer)
            }
        },
    ) {
        content()
    }
}

/** 点整行进编辑器；滑动删除。次要动作不另开入口（见 [SwipeToDelete] 的说明）。 */
@Composable
private fun UserRuleRow(local: LocalRule, onClick: () -> Unit) {
    Card(onClick = onClick) {
        Row(
            Modifier.fillMaxWidth().padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    local.rule.regexFilter,
                    style = MaterialTheme.typography.bodyMedium,
                    fontFamily = FontFamily.Monospace,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    describeTarget(local.rule),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Switch(
                checked = local.enabled,
                onCheckedChange = { RuleStore.setEnabled(local.id, it) },
            )
        }
    }
}

/**
 * 内置规则行（只读）。
 *
 * 文案包在 [SelectionContainer] 里：内置规则打不开编辑器，**长按选中复制是拿到它
 * 那条正则的唯一路径**——用系统原生的文本交互，而不是自造一个长按菜单。
 */
@Composable
private fun BuiltinRuleRow(rule: Rule) {
    Card {
        SelectionContainer {
            Column(
                Modifier.fillMaxWidth().padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    rule.regexFilter,
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    describeTarget(rule),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

internal fun describeTarget(rule: Rule): String {
    // 先落到局部变量：跨模块的 public 属性做不了 smart cast
    val substitution = rule.regexSubstitution
    val params = rule.removeParams
    return when {
        !substitution.isNullOrEmpty() -> "→ $substitution"
        !params.isNullOrEmpty() -> "removes ${params.joinToString(", ")}"
        rule.followRedirect == true -> "follows redirect"
        else -> "(no action)"
    }
}

private fun ruleMatches(rule: Rule, q: String): Boolean =
    rule.id.contains(q, ignoreCase = true) ||
        rule.regexFilter.contains(q, ignoreCase = true) ||
        rule.regexSubstitution?.contains(q, ignoreCase = true) == true ||
        rule.removeParams?.any { it.contains(q, ignoreCase = true) } == true
