import AppKit
import SwiftUI
import UniformTypeIdentifiers
import LinkPureCore

/// 侧边栏里的两个分区。
///
/// 刻意**不叫** `Section`：那是 SwiftUI 的视图类型，同名会把 `Section("…") { }` 挡住。
///
/// `title` / `searchPrompt` 刻意用 `LocalizedStringKey` 而不是 `String`：
/// 变量形式的 `String` 会走 `Label(_:systemImage:)` 的**非本地化**重载，
/// 字面量看着一样、实际不进 String Catalog。踩过一次就会静默失效。
private enum Pane: CaseIterable, Identifiable, Hashable {
    case mine
    case builtin

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .mine: "My Rules"
        case .builtin: "Built-in Rules"
        }
    }

    var icon: String {
        switch self {
        case .mine: "square.and.pencil"
        case .builtin: "books.vertical"
        }
    }

    var searchPrompt: LocalizedStringKey {
        switch self {
        case .mine: "Search my rules"
        case .builtin: "Search built-in rules"
        }
    }
}

/// 窗口级动作，供「文件」菜单里的菜单项调用。
///
/// 菜单挂在 **Scene** 上（`LinkPureApp`），而 `isImporting` / `editingTarget` 这些状态
/// 活在 **View** 里，两者之间没有直接引用路径。`FocusedValues` 就是为这件事准备的：
/// 由当前窗口把自己的能力"公告"出去，`Commands` 侧读到就启用菜单项、读不到就置灰——
/// 于是"没有窗口时菜单项变灰"这种行为是自动的，不用手工同步。
struct RuleActions {
    var createRule: () -> Void
    var importRules: () -> Void
    var exportRules: () -> Void
    /// 没有规则可导出时为 false（菜单项跟着置灰）
    var canExport: Bool
    /// 删掉当前选中的规则。
    var deleteSelection: () -> Void
    /// 选中数量。0 = 菜单项置灰（也顺便让 ⌘⌫ 在没有选中时不抢文本框）。
    var selectedRuleCount: Int
}

private struct RuleActionsKey: FocusedValueKey {
    typealias Value = RuleActions
}

extension FocusedValues {
    var ruleActions: RuleActions? {
        get { self[RuleActionsKey.self] }
        set { self[RuleActionsKey.self] = newValue }
    }
}

/// 规则管理主窗口。
///
/// 布局交给系统容器（`NavigationSplitView` + toolbar + sidebar），而不是自己摆：
///
///   - 分区导航 → **sidebar**：拿到活的半透明材质、系统列宽、`⌃⌘S` 折叠
///   - 搜索 → **`.searchable`**：搜索框进工具栏，`⌘F` / `Esc` / 焦点环全部白送
///   - 新增/导入/导出 → **toolbar item**：高度、间距、hover、溢出折叠由系统决定
///   - 状态行 → **`.navigationSubtitle`**：进标题栏副标题，不再占掉窗口底部一条
///   - 1061 条内置规则 → **`Table`**：列头可点排序、列宽可拖、自动虚拟化
///
/// 自己摆一个 `VStack` 也能做出"看起来一样"的界面，但那只是抄了配色，
/// 上面这些**行为**一条都拿不到。
///
/// 分工（与 Flutter 版一致）：
///   - **My Rules**：用户自建，可增删改、可启用/禁用
///   - **Built-in Rules**：1061 条只读共享规则库，只可浏览/搜索，不可管理
///
/// 文案：**英文是 source language**（App Store 上原版就是纯英文），
/// 中文由 `Localizable.xcstrings` 提供翻译。见 `Apps/Shared/Localizable.xcstrings`。
struct MainWindowView: View {
    @ObservedObject var model: AppModel

    @State private var pane: Pane = .mine
    @State private var userSearch = ""
    @State private var builtinSearch = ""
    @State private var testURL = ""
    @State private var testResult: MatchResult?
    @State private var testNotAUrl = false
    @State private var editingTarget: EditorTarget?
    @State private var deletedRules: [DeletedRule] = []
    @State private var undoHintTimer: Task<Void, Never>?
    @State private var message: String?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var exportDoc = JSONDocument(text: "[]")
    @State private var selectedBuiltinRule: Rule.ID?
    /// 我的规则里选中的行。用 `Set`（而不是单个 ID）多选是白送的：
    /// ⌘点 切换、⇧点 连选、⇧↑↓ 扩展全由系统实现。
    @State private var selectedUserRules = Set<LocalRule.ID>()
    @Environment(\.openSettings) private var openSettingsAction
    /// `Table` 只把列头点击写回这里，排数据得自己来（见 `builtinList`）。
    @State private var builtinSortOrder = [KeyPathComparator(\Rule.id)]

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 820, minHeight: 520)
        .focusedSceneValue(\.ruleActions, ruleActions)
        .sheet(item: $editingTarget) { target in
            RuleEditorView(
                rule: target.rule,
                testUrl: target.testUrl,
                initialResult: target.preview,
                rulesetProvider: { model.rulesetForTesting(draft: $0) }
            ) { updated, testUrl in
                model.upsertUserRule(updated, testUrl: testUrl)
            }
        }
        // 删除**不弹确认**：macOS 的规矩是 confirm 留给"撤销不了"的操作
        // （Safari 清历史、关闭未保存的文稿），而删一条规则就是一次数组插入
        // 就能恢复的事。Finder 移到废纸篓、Xcode 删文件、Mail 删邮件也都不问。
        // 恢复入口是状态栏那条 8 秒提示（见 `showUndoHint(for:)`），
        // 刻意没有去接 `UndoManager`——理由写在 `delete(_:)` 的注释里。
        .fileExporter(
            isPresented: $isExporting,
            document: exportDoc,
            contentType: .json,
            defaultFilename: "LinkPure-Rules"
        ) { result in
            if case .failure(let e) = result {
                message = String(localized: "Export failed: \(e.localizedDescription)")
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json]
        ) { result in
            handleImport(result)
        }
    }

    // MARK: - 侧边栏

    private var sidebar: some View {
        List(selection: paneSelection) {
            ForEach(Pane.allCases) { item in
                Label(item.title, systemImage: item.icon)
                    .tag(item)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 176, ideal: 196, max: 280)
        // 「Settings…」放侧边栏底部。
        //
        // 位置的理由：macOS 上侧边栏底部就是放**应用级**东西的地方（跟列表内容不同层级），
        // 而且这里正好有一大片空白要填。
        //
        // 存在的理由更要紧：这是个**菜单栏 app**，用户习惯在状态栏图标的
        // 下拉菜单里找设置——把入口**只**放那儿，等于要求他先去够屏幕顶上的图标。
        // 主窗口既然开着，设置就该在里面点得到。（app 菜单里的 ⌘, 仍然有效。）
        .safeAreaInset(edge: .bottom, spacing: 0) { sidebarFooter }
    }

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: showSettings) {
                Label("Settings…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open settings (⌘,)")
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    /// 设置窗口归系统管，但**把 app 拉到最前**得自己做——
    /// 否则从菜单里点完，窗口开在别人后面，看起来像没反应。
    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettingsAction()
    }

    /// `List(selection:)` 单选用的是 `Optional` 绑定，而 `pane` 不该有"没选中"的状态，
    /// 所以在中间转一道：往外给 `Optional`，往里拒绝 nil。
    private var paneSelection: Binding<Pane?> {
        Binding(get: { pane }, set: { if let value = $0 { pane = value } })
    }

    // MARK: - 主区域

    private var detail: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) { testBar }
            .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
            // 两个分区各自记住自己的搜索词，但共用一个搜索框——
            // 搜索框的**位置**由系统决定（工具栏右侧），这里只提供文本。
            .searchable(text: searchText, prompt: pane.searchPrompt)
            .navigationTitle(pane.title)
            .navigationSubtitle(statusSubtitle)
            .toolbar { toolbarContent }
    }

    private var searchText: Binding<String> {
        switch pane {
        case .mine: $userSearch
        case .builtin: $builtinSearch
        }
    }

    /// 用 `Text` 而不是拼好的 `String`：复数变化（1 URL / 5 URLs）是由
    /// String Catalog 里的 plural 规则在**取词时**决定的，一旦自己拼成 `String`
    /// 就脱离本地化系统了。
    private var statusSubtitle: Text {
        if let err = model.loadError { return Text(err) }
        // 刻意做**短**：标题栏副标题旁边还挤着三个工具栏按钮和一个搜索框，
        // 900pt 宽的窗口里放不下更长的句子。计数放在底部状态栏（那里有的是宽度）。
        return Text("\(model.rewriteCount) URLs rewritten")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // 内置规则库是只读的，工具栏上不该出现写操作
        if pane == .mine {
            ToolbarItemGroup {
                Button {
                    openEditor(newRule(), testUrl: nil)
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .help("Add a rule (⌘N)")

                Button {
                    isImporting = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import from JSON (⌘I)")

                Button {
                    doExport()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(model.userRules.isEmpty)
                .help("Export as JSON (⌘E)")
            }
        }
    }

    // MARK: - 测试条

    private var testBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)

                TextField("Paste URL here…", text: $testURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .labelsHidden()

                if !testURL.isEmpty {
                    Button {
                        testURL = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tertiary)
                    .help("Clear")
                }
            }

            if testNotAUrl {
                RuleTestResultView.invalid()
            } else if let testResult {
                RuleTestResultView(result: testResult)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // 这条测试栏浮在列表上方（`safeAreaInset`），必须是不透明的，
        // 否则滚动时列表内容会从它下面透出来。
        .background(.background)
        .overlay(alignment: .bottom) { Divider() }
        // 输入即测；并且规则集一变（启用/禁用、增删、导入）也重算——
        // 否则改了开关，已显示的结果会变成陈旧的。
        .task(id: "\(testURL)|\(model.rulesetRevision)") { await runTest() }
    }

    private func runTest() async {
        let trimmed = testURL.trimmingCharacters(in: .whitespacesAndNewlines)
        testNotAUrl = false
        testResult = nil
        // 空输入不报错——窗口刚打开时不该直接甩一句"Not a URL"
        guard !trimmed.isEmpty else { return }
        guard let r = await model.test(trimmed) else {
            testNotAUrl = true
            return
        }
        testResult = r
    }

    // MARK: - 状态栏

    private var statusBar: some View {
        HStack(spacing: 6) {
            if !deletedRules.isEmpty {
                Image(systemName: "trash")
                // 复数交给 String Catalog（英文 "1 rule" / "5 rules"），
                // 不要写成 `count == 1 ? "…" : "…"`——那是把**中文**的
                // 量词习惯硬编码进控制流，换语言就得改代码。
                Text("Deleted \(deletedRules.count) rules")
                Button("Undo") { undoDelete() }
                    .buttonStyle(.link)
                    // 提示条只在刚删完的 8 秒里存在，所以这个快捷键也就是
                    // "那 8 秒内 ⌘Z 可用"——正是用户会去按它的时候。
                    // 提示条消失后快捷键也跟着没了，不会抢文本框自己的 ⌘Z。
                    .keyboardShortcut("z")
            } else if let message {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                Button {
                    self.message = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Dismiss")
            } else {
                Text(pane == .mine
                    ? "Built-in rules are always active"
                    : "Built-in rules are read-only")
            }

            Spacer()

            if pane == .mine {
                Text("\(model.enabledUserRuleCount) / \(model.userRules.count) enabled")
            } else {
                Text("\(filteredBuiltinRules.count) rules")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        // `.bar` 是系统的工具栏/状态栏材质，跟着窗口失焦、暗色模式自动变——
        // 手糊一个 `Color.gray.opacity(0.1)` 就拿不到这些。
        .background(.bar)
    }

    // MARK: - 内容分发

    @ViewBuilder
    private var content: some View {
        switch pane {
        case .mine: mineList
        case .builtin: builtinList
        }
    }

    // MARK: - 我的规则

    private var filteredUserRules: [LocalRule] {
        let q = userSearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.userRules }
        return model.userRules.filter {
            $0.rule.id.lowercased().contains(q) || $0.rule.regexFilter.lowercased().contains(q)
        }
    }

    @ViewBuilder
    private var mineList: some View {
        if model.userRules.isEmpty {
            emptyState
        } else {
            List(selection: $selectedUserRules) {
                ForEach(filteredUserRules) { local in
                    userRuleRow(local)
                }
                // 有了选中，方向键导航、右键菜单作用于选中集都自动成立。
                .onDelete { offsets in
                    delete(offsets.map { filteredUserRules[$0] })
                }
            }
            .listStyle(.inset)
            // 右键菜单挂在**列表**上而不是每一行：这样它作用于**选中集**，
            // 跟高亮保持一致。挂在行上的话，选中 A 再去右键 B，菜单里的删除
            // 会删 B 而高亮在 A —— 那种不一致比完全没有选中还糟。
            .contextMenu(forSelectionType: LocalRule.ID.self) { ids in
                userRuleMenu(for: ids)
            } primaryAction: { ids in
                // 双击 = 编辑。这是 macOS 的"激活"手势（Finder / Xcode / 邮件都是），
                // 也是内置规则库那个 Table 已经在用的（那边是复制正则）。
                if let local = singleUserRule(in: ids) {
                    openEditor(local.rule, testUrl: local.testUrl)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No custom rules yet", systemImage: "square.and.pencil")
        } description: {
            Text("Paste a URL above to try the built-in rules, or add one of your own.")
        } actions: {
            Button("Add Rule") { openEditor(newRule(), testUrl: nil) }
        }
        // `ContentUnavailableView` 是按**内容取尺寸**的，不会自己撑满。
        // 漏了这句，整个 detail 列（测试条 + 空状态 + 状态栏）就变成一个
        // "内容大小的块"，被 NavigationSplitView 在中间居中——上下各留一大片空白。
        // 有规则时这里是 `List`，天然撑满，所以只有空状态看得出来。
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 规则行。
    ///
    /// **没有行内编辑/删除按钮** —— 动作全在右键菜单 + 双击 + 键盘，
    /// 见 `mineList`。这样跟同一窗口里的「内置规则库」表格一致（那个本来就没有
    /// 行内按钮），且长正则能多出一截宽度（那两个图标占了尾部约 60pt）。
    private func userRuleRow(_ local: LocalRule) -> some View {
        HStack(spacing: 10) {
            // 标签给 VoiceOver 用（`labelsHidden` 只是不画出来）；
            // 也不要写成空串 `Toggle("")`——那会往 String Catalog 里塞一个空 key。
            Toggle("Rule enabled", isOn: Binding(
                get: { local.enabled },
                set: { model.setEnabled(local, $0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .help(local.enabled ? "Enabled" : "Disabled")

            VStack(alignment: .leading, spacing: 2) {
                // 主行是**规则本身**（匹配正则），不是内部 id：
                // id 是新建时自动生成的（ULID / 旧的 custom-<时间戳>），
                // 对用户毫无意义，只在悬停时给出，方便导出后对账。
                Text(local.rule.regexFilter)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    // 禁用的规则整行变淡：一眼能看出哪些在生效，
                    // 不用去读左边的复选框。
                    .foregroundStyle(local.enabled ? .primary : .secondary)
                    .help("Rule ID: \(local.rule.id)")
                if let to = local.rule.regexSubstitution {
                    Text("→ \(to)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(local.enabled ? .secondary : .tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 2)
    }

    /// 右键菜单。按选中数量决定给哪几项——跟 Finder 一样，只在单选时给"编辑/复制"。
    @ViewBuilder
    private func userRuleMenu(for ids: Set<LocalRule.ID>) -> some View {
        if let local = singleUserRule(in: ids) {
            Button("Edit…") { openEditor(local.rule, testUrl: local.testUrl) }
        }
        if !ids.isEmpty {
            Button("Enable") { setEnabled(ids, true) }
            Button("Disable") { setEnabled(ids, false) }
            Divider()
            if let local = singleUserRule(in: ids) {
                Button("Copy Regular Expression") { copyToPasteboard(local.rule.regexFilter) }
            }
            Button(ids.count == 1 ? "Delete Rule" : "Delete \(ids.count) Rules", role: .destructive) {
                deleteRules(ids)
            }
        }
    }

    /// 选中集里唯一那条（多选时返回 nil）。
    private func singleUserRule(in ids: Set<LocalRule.ID>) -> LocalRule? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return model.userRules.first { $0.id == id }
    }

    private func setEnabled(_ ids: Set<LocalRule.ID>, _ enabled: Bool) {
        for local in model.userRules where ids.contains(local.id) {
            model.setEnabled(local, enabled)
        }
    }

    /// 按 id 删。传的是**列表原序**（`model.userRules` 的顺序），
    /// 这样 `delete` 记下的下标才能被撤销正确插回。
    private func deleteRules(_ ids: Set<LocalRule.ID>) {
        delete(model.userRules.filter { ids.contains($0.id) })
    }

    // MARK: - 内置规则库（只读）

    private var filteredBuiltinRules: [Rule] {
        let q = builtinSearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.sharedRules }
        return model.sharedRules.filter {
            $0.id.lowercased().contains(q) || $0.regexFilter.lowercased().contains(q)
        }
    }

    /// 1061 条用 `Table` 而不是 `List`：列头点一下就排序、列宽能拖、行自动虚拟化。
    /// 内置规则库是**查"哪条规则会咬我"的地方**，排序和列宽是核心操作，不是装饰。
    ///
    /// 排序是自己做的（`sorted(using:)`）：`Table` 只负责把用户的点击写回
    /// `sortOrder`，**不会**替你排数据。
    private var builtinList: some View {
        Table(
            filteredBuiltinRules.sorted(using: builtinSortOrder),
            selection: $selectedBuiltinRule,
            sortOrder: $builtinSortOrder
        ) {
            TableColumn("Rule ID", value: \.id) { rule in
                Text(rule.id)
                    .lineLimit(1)
            }
            .width(min: 180, ideal: 260, max: 420)

            TableColumn("Regular Expression", value: \.regexFilter) { rule in
                Text(rule.regexFilter)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .contextMenu(forSelectionType: Rule.ID.self) { ids in
            if let rule = singleRule(in: ids) {
                Button("Copy Regular Expression") { copyToPasteboard(rule.regexFilter) }
                Button("Copy Rule ID") { copyToPasteboard(rule.id) }
            }
        } primaryAction: { ids in
            // 双击 = 复制正则
            if let rule = singleRule(in: ids) { copyToPasteboard(rule.regexFilter) }
        }
    }

    private func singleRule(in ids: Set<Rule.ID>) -> Rule? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return model.sharedRules.first { $0.id == id }
    }

    // MARK: - 动作

    /// 给 `LinkPureApp` 的菜单用（见 `RuleActions`）。
    private var ruleActions: RuleActions {
        RuleActions(
            createRule: { openEditor(newRule(), testUrl: nil) },
            importRules: { isImporting = true },
            exportRules: { doExport() },
            canExport: !model.userRules.isEmpty,
            deleteSelection: {
                guard !selectedUserRules.isEmpty else { return }
                deleteRules(selectedUserRules)
            },
            selectedRuleCount: selectedUserRules.count
        )
    }

    /// 打开编辑器。**预览在弹窗出现前就算好**（见 `EditorTarget`），
    /// 否则弹窗会先画一帧“没有结果”的样子再长高，看起来像闪烁。
    private func openEditor(_ rule: Rule, testUrl: String?) {
        editingTarget = EditorTarget(
            rule: rule,
            testUrl: testUrl,
            rulesetForTesting: model.rulesetForTesting
        )
    }

    private func newRule() -> Rule {
        Rule(
            id: Rule.newUserRuleID(),
            regexFilter: "",
            regexSubstitution: ""
        )
    }

    // MARK: - 删除

    /// 删除。**不弹确认**——macOS 上 confirm 是留给"撤销不了"的操作的，
    /// 而删除一条规则就是一次数组插入就能恢复的事。
    ///
    /// 这里刻意**不碰 `UndoManager`**（不注册撤销、不集成「编辑 > 撤销」）：
    /// 那套东西要维护的不变量很多（撤销 / 重做两个方向必须互相注册、
    /// 分组跟 `groupsByEvent` 的交互、反向操作时的下标漂移……），
    /// 而它换来的只是 "⌘Z" 一种入口，**又恰好是最没有可发现性的那一种**。
    /// 这个应用的真实需求是：删错了能找回来，而且**看得见**能找回来。
    /// 一个 8 秒的提示条就够，没必要搞一套撤销栈。
    private func delete(_ rules: [LocalRule]) {
        guard !rules.isEmpty else { return }

        var removed: [DeletedRule] = []
        for rule in rules {
            guard let index = model.userRules.firstIndex(where: { $0.id == rule.id }) else { continue }
            model.deleteUserRule(rule)
            removed.append(DeletedRule(rule: rule, index: index))
        }
        showUndoHint(for: removed)
    }

    // MARK: - 删除提示 / 撤销

    /// 刚删掉的规则 + 它**原来在列表里的位置**。
    ///
    /// 位置必须记：规则集是**有序**的（用户规则排在共享规则前面、
    /// 新规则优先级最高），顺序会改变命中结果，插回末尾等于偷偷改了规则语义。
    private struct DeletedRule {
        let rule: LocalRule
        let index: Int
    }

    private func showUndoHint(for removed: [DeletedRule]) {
        guard !removed.isEmpty else { return }
        withAnimation(.snappy) { deletedRules = removed }

        // 上一条的计时器要先取消，否则连续删两条时会被前一个计时器提前收起
        undoHintTimer?.cancel()
        undoHintTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { deletedRules = [] }
        }
    }

    private func undoDelete() {
        guard !deletedRules.isEmpty else { return }
        var rules = model.userRules
        // 按下标升序插回，否则多选时后面的下标会逐个失效
        for item in deletedRules.sorted(by: { $0.index < $1.index }) {
            rules.insert(item.rule, at: min(item.index, rules.count))
        }
        model.replaceUserRules(rules)

        undoHintTimer?.cancel()
        withAnimation(.snappy) { deletedRules = [] }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func doExport() {
        do {
            exportDoc = JSONDocument(text: try model.exportRules())
            isExporting = true
        } catch {
            message = String(localized: "Export failed: \(error.localizedDescription)")
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let e):
            message = String(localized: "Import failed: \(e.localizedDescription)")
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let json = try String(contentsOf: url, encoding: .utf8)
                try model.importRules(json, merge: true)
                message = String(localized: "Rules imported successfully")
            } catch {
                message = String(localized: "Import failed: \(error.localizedDescription)")
            }
        }
    }
}
