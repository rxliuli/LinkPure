package com.rxliuli.linkpure.ui

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import com.rxliuli.linkpure.core.LocalRule
import com.rxliuli.linkpure.core.RuleExchange
import com.rxliuli.linkpure.core.RuleExchangeException
import com.rxliuli.linkpure.data.RuleStore
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * 撤销条的时长。
 *
 * Material 只给了 Short(4s) / Long(10s)，都不是想要的数。iOS 用的是 6 秒
 * （`IOSRulesView.swift: showUndoHint`），macOS 8 秒——**10 秒确实太长**：
 * 用户早就走了，那条东西还赖在屏幕上。
 */
private const val UNDO_MILLIS = 6_000L

/** 当前在哪一屏。列表以外都是「进了一层」，返回键统一回到列表。 */
private sealed interface Screen {
    data object Rules : Screen

    data object NewRule : Screen

    data class EditRule(val local: LocalRule) : Screen

    data object Guide : Screen

    data object About : Screen
}

/**
 * 主界面。
 *
 * 布局刻意全部交给系统容器——这是 Swift 侧 README 里立下的规矩，
 * 第一版我违反了（用 LazyColumn 把说明、测试、两排按钮、列表手工堆成一摞，
 * 结果「How to use」占了四成屏幕，真正的列表被挤到折叠线以下）。
 *
 * | 意图 | 容器 |
 * |---|---|
 * | 当前在哪一屏 | [AnimatedContent]（列表 ↔ 编辑 / 说明 / 关于） |
 * | 切「我的规则 / 内置规则库」 | `TabRow` |
 * | 搜索 | 顶栏里的搜索图标，展开成顶栏内的输入框 |
 * | 新建 | `FloatingActionButton` |
 * | 导入 / 导出 / 使用说明 / 关于 | 顶栏的溢出菜单 |
 * | 删除 | 列表里**滑动**（立即删 + 撤销条） |
 * | 反馈 | `Snackbar` |
 *
 * **每一屏的 app bar 都画在 [AnimatedContent] 里面**，不能挂在 `Scaffold.topBar` 上：
 * 编辑器那一屏的 topBar 是空的（它自带 app bar），挂在 Scaffold 上会让 padding
 * 在切换时从「112px 顶栏」跳到 0——横向滑动的同时整个页面向上一顶，很怪。
 */
@Composable
fun RulesScreen() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }

    var screen: Screen by remember { mutableStateOf(Screen.Rules) }
    var searching by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    var menuOpen by remember { mutableStateOf(false) }
    var undoDismissJob by remember { mutableStateOf<Job?>(null) }

    fun notify(message: String) {
        scope.launch { snackbarHostState.showSnackbar(message) }
    }

    /** 删东西一律「立即执行 + 给一条撤销」，不弹二次确认。 */
    fun undoable(message: String, undo: () -> Unit) {
        // 上一条的计时器要先取消，否则连续删两条时会被前一个计时器提前收起
        undoDismissJob?.cancel()
        scope.launch {
            val shown = launch {
                val result = snackbarHostState.showSnackbar(
                    message = message,
                    actionLabel = "Undo",
                    withDismissAction = true,
                    // 用 Indefinite + 自己计时：Material 没有 6 秒这一档
                    duration = SnackbarDuration.Indefinite,
                )
                if (result == SnackbarResult.ActionPerformed) undo()
            }
            undoDismissJob = launch {
                delay(UNDO_MILLIS)
                snackbarHostState.currentSnackbarData?.dismiss()
            }
            shown.join()
        }
    }

    val exportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json"),
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val result = RuleExchange.export(RuleStore.userRules.toList())
        val wrote = runCatching {
            context.contentResolver.openOutputStream(uri)?.use { it.write(result.json.toByteArray()) }
        }.isSuccess
        if (!wrote) {
            notify("Couldn't write that file")
            return@rememberLauncherForActivityResult
        }
        val exported = RuleStore.userRules.size - result.skipped.size
        notify(
            if (result.skipped.isEmpty()) {
                "Exported $exported rule${plural(exported)}"
            } else {
                "Exported $exported, skipped ${result.skipped.size} (only from→to rules can be exported)"
            },
        )
    }

    val importLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val text = runCatching {
            context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
        }.getOrNull()
        if (text.isNullOrBlank()) {
            notify("Couldn't read that file")
            return@rememberLauncherForActivityResult
        }

        // 固定 merge：合并永远不会破坏已有规则，而「想替换」先删掉再导就是了。
        // macOS 与 iOS 两边也都是写死 merge: true、不弹选择。
        val snapshot = RuleStore.userRules.toList()
        val imported = runCatching {
            RuleExchange.`import`(text, merge = true, existing = snapshot)
        }.getOrElse { error ->
            notify(
                if (error is RuleExchangeException) {
                    "That file isn't a LinkPure rules file"
                } else {
                    "Import failed: ${error.message}"
                },
            )
            return@rememberLauncherForActivityResult
        }

        val added = imported.size - snapshot.size
        if (added <= 0) {
            notify("Nothing new to import")
        } else {
            RuleStore.replaceAll(imported)
            RuleStore.save()
            undoable("Imported $added rule${plural(added)}") { RuleStore.replaceAll(snapshot) }
        }
    }

    fun deleteRule(local: LocalRule) {
        val removed = RuleStore.removeWithIndex(local.id) ?: return
        undoable("Rule deleted") { RuleStore.insertAt(removed.first, removed.second) }
    }

    // 系统返回键：只要不在列表页就退回列表，而不是退出 app
    BackHandler(enabled = screen !is Screen.Rules) {
        screen = Screen.Rules
    }

    Scaffold(
        floatingActionButton = {
            if (screen is Screen.Rules) {
                FloatingActionButton(onClick = { screen = Screen.NewRule }) {
                    Icon(Icons.Filled.Add, contentDescription = "New rule")
                }
            }
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        AnimatedContent(
            targetState = screen,
            transitionSpec = {
                val forward = initialState is Screen.Rules && targetState !is Screen.Rules
                val fade = tween<Float>(durationMillis = 220)
                val slide = tween<androidx.compose.ui.unit.IntOffset>(durationMillis = 220)
                if (forward) {
                    (slideInHorizontally(slide) { it } + fadeIn(fade)) togetherWith
                        (slideOutHorizontally(slide) { -it / 4 } + fadeOut(fade))
                } else {
                    (slideInHorizontally(slide) { -it / 4 } + fadeIn(fade)) togetherWith
                        (slideOutHorizontally(slide) { it } + fadeOut(fade))
                }
            },
            modifier = Modifier.padding(padding).fillMaxSize(),
            label = "screen",
        ) { target ->
            when (target) {
                is Screen.Rules -> Column(Modifier.fillMaxSize()) {
                    RulesTopBar(
                        searching = searching,
                        query = query,
                        menuOpen = menuOpen,
                        onQuery = { query = it },
                        onOpenSearch = { searching = true },
                        onCloseSearch = {
                            searching = false
                            query = ""
                        },
                        onMenuOpen = { menuOpen = it },
                        onGuide = {
                            menuOpen = false
                            screen = Screen.Guide
                        },
                        onAbout = {
                            menuOpen = false
                            screen = Screen.About
                        },
                        onImport = {
                            menuOpen = false
                            importLauncher.launch(arrayOf("*/*"))
                        },
                        onExport = {
                            menuOpen = false
                            if (RuleStore.userRules.isEmpty()) {
                                notify("No custom rules to export")
                            } else {
                                exportLauncher.launch("linkpure-rules.json")
                            }
                        },
                    )
                    RulesTabContent(
                        query = query,
                        onEdit = { screen = Screen.EditRule(it) },
                        onDelete = ::deleteRule,
                    )
                }

                is Screen.NewRule -> RuleEditorScreen(
                    initial = null,
                    onSave = {
                        RuleStore.upsert(it)
                        screen = Screen.Rules
                    },
                    onClose = { screen = Screen.Rules },
                )

                is Screen.EditRule -> RuleEditorScreen(
                    initial = target.local,
                    onSave = {
                        RuleStore.upsert(it)
                        screen = Screen.Rules
                    },
                    onClose = { screen = Screen.Rules },
                )

                is Screen.Guide -> Column(Modifier.fillMaxSize()) {
                    SimpleTopBar(title = "How to use", onBack = { screen = Screen.Rules })
                    GuideScreen()
                }

                is Screen.About -> Column(Modifier.fillMaxSize()) {
                    SimpleTopBar(title = "About", onBack = { screen = Screen.Rules })
                    AboutScreen()
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RulesTopBar(
    searching: Boolean,
    query: String,
    menuOpen: Boolean,
    onQuery: (String) -> Unit,
    onOpenSearch: () -> Unit,
    onCloseSearch: () -> Unit,
    onMenuOpen: (Boolean) -> Unit,
    onGuide: () -> Unit,
    onAbout: () -> Unit,
    onImport: () -> Unit,
    onExport: () -> Unit,
) {
    val userRules = RuleStore.userRules

    if (searching) {
        // 展开搜索就自动聚焦——不然用户还得再点一下输入框
        val focusRequester = remember { FocusRequester() }
        LaunchedEffect(Unit) { focusRequester.requestFocus() }

        TopAppBar(
            navigationIcon = {
                IconButton(onClick = onCloseSearch) {
                    Icon(Icons.Filled.Close, contentDescription = "Close search")
                }
            },
            title = {
                TextField(
                    value = query,
                    onValueChange = onQuery,
                    placeholder = { Text("Search rules") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().focusRequester(focusRequester),
                )
            },
        )
        return
    }

    TopAppBar(
        title = {
            Column {
                Text("LinkPure", style = MaterialTheme.typography.titleLarge)
                Text(
                    "${userRules.size} custom · ${RuleStore.bundledRules.size} built-in",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        actions = {
            IconButton(onClick = onOpenSearch) {
                Icon(Icons.Filled.Search, contentDescription = "Search")
            }
            Box {
                IconButton(onClick = { onMenuOpen(true) }) {
                    Icon(Icons.Filled.MoreVert, contentDescription = "More")
                }
                DropdownMenu(expanded = menuOpen, onDismissRequest = { onMenuOpen(false) }) {
                    DropdownMenuItem(text = { Text("How to use") }, onClick = onGuide)
                    DropdownMenuItem(text = { Text("Import rules…") }, onClick = onImport)
                    DropdownMenuItem(text = { Text("Export rules…") }, onClick = onExport)
                    DropdownMenuItem(text = { Text("About") }, onClick = onAbout)
                }
            }
        },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SimpleTopBar(title: String, onBack: () -> Unit) {
    TopAppBar(
        title = { Text(title) },
        navigationIcon = {
            IconButton(onClick = onBack) {
                Icon(Icons.Filled.Close, contentDescription = "Back")
            }
        },
    )
}

internal fun plural(n: Int): String = if (n == 1) "" else "s"
