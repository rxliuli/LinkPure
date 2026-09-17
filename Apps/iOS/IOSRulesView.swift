import SwiftUI
import UIKit
import UniformTypeIdentifiers
import LinkPureCore

/// 规则管理。
///
/// 与 macOS 版同一套数据模型，分工也一样：
///   - **我的规则**：用户自建，可增删改、可启用/禁用
///   - **内置规则库**：只读共享规则，只可浏览/搜索
///
/// 但 iOS 的原生约定和 macOS **不一样**，不能照搬那边的做法：
///
///   - **没有 hover**，`.help()` 在 iPhone 上是死的（什么都不显示）。
///     要露出次要信息只能用**长按菜单**。
///   - **行是触摸目标**：整行可点才是最自然的"进详情"。只有 swipe action
///     等于把编辑藏起来了——没人会主动去试从右往左划。
///   - **`List` 本身是懒加载的**（UICollectionView 撑的），
///     macOS 上那种"只渲染前 N 条"的裁剪在这里是多余的。
struct IOSRulesView: View {
    @ObservedObject var model: AppModel

    /// `title` / `searchPrompt` 用 `LocalizedStringKey` 而不是 `String`：
    /// 变量形式的 `String` 会走**非本地化**重载，字面量看着一样但静默失效。
    private enum Tab: CaseIterable, Identifiable, Hashable {
        case mine
        case builtin

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .mine: "My Rules"
            case .builtin: "Built-in Rules"
            }
        }

        var searchPrompt: LocalizedStringKey {
            switch self {
            case .mine: "Search my rules"
            case .builtin: "Search built-in rules"
            }
        }
    }

    /// 导入 / 导出的结果提示。
    ///
    /// 必须用 `.alert`，**不能**塞成 List 末尾的一个 Section：内置规则库那一屏
    /// 有 1061 行，放最后等于永远看不见（实际踩到过——导入成功却像什么都没发生）。
    private struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }

    @State private var tab: Tab = .mine
    @State private var search = ""
    @State private var testURL = ""
    @State private var testResult: MatchResult?
    @State private var testNotAUrl = false
    @State private var editingTarget: EditorTarget?
    @State private var deletedRule: DeletedRule?
    @State private var undoTimer: Task<Void, Never>?
    @State private var notice: Notice?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var exportDoc = JSONDocument(text: "[]")

    /// 刚删掉的规则 + 它**原来在列表里的位置**（撤销时要插回原位）。
    private struct DeletedRule: Equatable {
        let rule: LocalRule
        let index: Int
    }

    var body: some View {
        NavigationStack {
            List {
                Section { testRow }
                Section { sectionPicker }

                if tab == .mine {
                    mineSection
                } else {
                    builtinSection
                }
            }
            .navigationTitle("LinkPure")
            // `.automatic`（默认）就是跟着滚动收起 / 下拉露出，跟系统 App 一致。
            // 刻意不写 `.navigationBarDrawer(displayMode: .always)`：那会永久占掉
            // 一行高度，而这一屏的主要内容是列表本身。
            .searchable(text: $search, prompt: tab.searchPrompt)
            .toolbar { toolbarContent }
            // 撤销条。**不弹确认**是有意为之：iOS 上滑动删除本来就不二次确认
            // （邮件 / 提醒事项 / 信息 / 文件 都不问），而 iOS 对误删的答案是**撤销**，
            // 不是确认——确认多一次点击、且只对"手滑"有用，对"点错了"没用。
            //
            // 另外确认在这里还有个副作用：`.swipeActions` 里的
            // `Button(role: .destructive)` 会让 SwiftUI **乐观地**把整行划走
            // （它假设这行马上会消失），而确认期间数据没变，List 重画时行又回来——
            // 就是那个"先消失再加回来"。
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let deletedRule {
                    undoBar(deletedRule)
                }
            }
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
            // `.alert` 而不是 `.confirmationDialog`：后者在这里被当成 popover，
            // 锚点落在"正在滑出的 swipe action"上，弹窗会飘到屏幕顶部并被切掉。
            .alert(
                notice?.title ?? "",
                isPresented: Binding(
                    get: { notice != nil },
                    set: { if !$0 { notice = nil } }
                ),
                presenting: notice
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { notice in
                Text(notice.body)
            }
            .fileExporter(
                isPresented: $isExporting, document: exportDoc,
                contentType: .json, defaultFilename: "LinkPure-Rules"
            ) { result in
                if case .failure(let e) = result {
                    notice = Notice(title: String(localized: "Export failed"), body: e.localizedDescription)
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
        }
    }

    // MARK: - 顶部：测试 + 分区

    private var testRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Paste URL here…", text: $testURL)
                    .font(.system(.subheadline, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !testURL.isEmpty {
                    Button {
                        testURL = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Clear")
                }
            }
            // 这里曾经有个「从剪贴板填入」按钮（读 UIPasteboard.general.string）。
            // 已删：测试框本身长按就能粘贴，而程序化读剪贴板在 iOS 16+ 反而会多弹
            // 一次「允许粘贴」——比原生粘贴更差。
            if testNotAUrl {
                RuleTestResultView.invalid()
            } else if let testResult {
                RuleTestResultView(result: testResult)
            }
        }
        .padding(.vertical, 4)
        // 输入即测；规则集变动（启用/禁用、增删、导入）时也重算
        .task(id: "\(testURL)|\(model.rulesetRevision)") { await runTest() }
    }

    private var sectionPicker: some View {
        // `Picker("")` 会往 String Catalog 里塞一个空 key；给个真标签 + `labelsHidden`
        // 就只剩无障碍用的名字，界面上看不到。
        Picker("Rules section", selection: $tab) {
            ForEach(Tab.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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

    // MARK: - 我的规则

    private var filteredUserRules: [LocalRule] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.userRules }
        return model.userRules.filter {
            $0.rule.id.lowercased().contains(q) || $0.rule.regexFilter.lowercased().contains(q)
        }
    }

    @ViewBuilder
    private var mineSection: some View {
        if model.userRules.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("No custom rules yet", systemImage: "square.and.pencil")
                } description: {
                    Text("Paste a URL above to try the built-in rules, or add one of your own.")
                } actions: {
                    Button("Add Rule") { openEditor(newRule(), testUrl: nil) }
                        .buttonStyle(.borderedProminent)
                }
                // 空状态是"这一屏没内容"，不是"这里有一行内容"——
                // 别把它画进一张卡片里
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }
        } else {
            Section("\(model.enabledUserRuleCount) / \(model.userRules.count) enabled") {
                ForEach(filteredUserRules) { local in
                    userRuleRow(local)
                }
            }
        }
    }

    private func userRuleRow(_ local: LocalRule) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                openEditor(local.rule, testUrl: local.testUrl)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(local.rule.regexFilter)
                        .font(.system(.subheadline, design: .monospaced))
                        // 给两行：正则在一行里不管中间截还是尾部截，都截到看不出是哪条规则
                        .lineLimit(2)
                        .foregroundStyle(local.enabled ? Color.primary : Color.secondary)
                    if let to = local.rule.regexSubstitution {
                        // 替换目标只给一行，而且**从中间**截：
                        // `https://addons.mozilla.org/en-US/…addon/$1/` 两头都在，
                        // 比尾部截断丢掉整个路径有用得多。
                        Text("→ \(to)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // 让整行（含文字右侧的空白）都可点，而不是只有文字那几个字宽
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 开关放**尾部**（跟「设置」一致）。放前面会跟正文抢左边缘，
            // 一列文字参差不齐，扫读时很难受。
            // 标签给 VoiceOver 用（`labelsHidden` 只是不画出来）；
            // 也不要写成空串 `Toggle("")`——那会往 String Catalog 里塞一个空 key。
            Toggle("Rule enabled", isOn: Binding(
                get: { local.enabled },
                set: { model.setEnabled(local, $0) }
            ))
            .labelsHidden()
        }
        // 编辑已经由「点整行」承担了，swipe 只留删除——跟邮件一致。
        // `role: .destructive` 现在是对的：删是**立即发生**的，行就该被划走。
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(local) } label: {
                Label("Delete Rule", systemImage: "trash")
            }
        }
        // 次要信息走长按，而不是 `.help()`（那个在 iPhone 上没有任何效果）
        .contextMenu {
            Button { openEditor(local.rule, testUrl: local.testUrl) } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(local.enabled ? "Disable" : "Enable") { model.setEnabled(local, !local.enabled) }
            Divider()
            Button { copy(local.rule.regexFilter) } label: {
                Label("Copy Regular Expression", systemImage: "doc.on.doc")
            }
            Button { copy(local.rule.id) } label: {
                Label("Copy Rule ID", systemImage: "number")
            }
            Divider()
            Button("Delete Rule", role: .destructive) { delete(local) }
        }
    }

    // MARK: - 删除 / 撤销

    /// 底部撤销条（邮件 / 文件那种）。`safeAreaInset` 而不是 `overlay`：
    /// 要的就是"把列表顶上去"，浮在上面会撞到 iOS 26 那个悬浮 TabView。
    private func undoBar(_ deleted: DeletedRule) -> some View {
        HStack(spacing: 12) {
            // 这里只可能删掉一条，所以用固定的 “Rule deleted”（Flutter 的原词），
            // 不需要复数形式。
            Text("Rule deleted")
                .font(.footnote)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Undo") { undoDelete() }
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// 立即删，但记住原位置并给出 6 秒的撤销窗口。
    private func delete(_ local: LocalRule) {
        guard let index = model.userRules.firstIndex(where: { $0.id == local.id }) else { return }
        model.deleteUserRule(local)
        withAnimation(.snappy) { deletedRule = DeletedRule(rule: local, index: index) }

        // 上一条的计时器要先取消，否则连续删两条时会被前一个计时器提前收起
        undoTimer?.cancel()
        undoTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { deletedRule = nil }
        }
    }

    private func undoDelete() {
        guard let deletedRule else { return }
        var rules = model.userRules
        // 插回**原来的下标**（不是接在末尾）：规则集是**有序**的，
        // 用户规则排在共享规则前面、新规则优先级最高，顺序会改变命中结果。
        rules.insert(deletedRule.rule, at: min(deletedRule.index, rules.count))
        model.replaceUserRules(rules)

        undoTimer?.cancel()
        withAnimation(.snappy) { self.deletedRule = nil }
    }

    // MARK: - 内置规则库（只读）

    private var filteredBuiltinRules: [Rule] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.sharedRules }
        return model.sharedRules.filter {
            $0.id.lowercased().contains(q) || $0.regexFilter.lowercased().contains(q)
        }
    }

    private var builtinSection: some View {
        Section {
            if model.sharedRules.isEmpty {
                Text(model.loadError ?? String(localized: "The rule library is empty"))
                    .foregroundStyle(.secondary)
            }
            // 不再 `prefix(300)`：`List` 是懒加载的，1061 行没有性能问题，
            // 截断只会让"搜不到但其实有"这种情况出现
            ForEach(filteredBuiltinRules) { rule in
                builtinRow(rule)
            }
        } header: {
            Text("\(filteredBuiltinRules.count) rules · Read-only")
        } footer: {
            Text("Built-in rules can't be edited and always apply. Long-press any rule to copy its regular expression.")
        }
    }

    private func builtinRow(_ rule: Rule) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(rule.id)
                .font(.subheadline)
                .lineLimit(1)
            Text(rule.regexFilter)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .contextMenu {
            Button { copy(rule.regexFilter) } label: {
                Label("Copy Regular Expression", systemImage: "doc.on.doc")
            }
            Button { copy(rule.id) } label: {
                Label("Copy Rule ID", systemImage: "number")
            }
        }
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // 内置规则库只读，工具栏上不该出现写操作
        if tab == .mine {
            // 新增是最常用的动作，直接给按钮；导入/导出不常用，收进菜单
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openEditor(newRule(), testUrl: nil)
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { isImporting = true } label: {
                        Label("Import Rules", systemImage: "square.and.arrow.down")
                    }
                    Button { doExport() } label: {
                        Label("Export Rules", systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.userRules.isEmpty)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - 动作

    /// 打开编辑器（预览在弹窗出现前算好，见 `EditorTarget`）。
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

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
    }

    private func doExport() {
        do {
            exportDoc = JSONDocument(text: try model.exportRules())
            isExporting = true
        } catch {
            notice = Notice(title: String(localized: "Export failed"), body: error.localizedDescription)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let e):
            notice = Notice(title: String(localized: "Import failed"), body: e.localizedDescription)
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                try model.importRules(try String(contentsOf: url, encoding: .utf8), merge: true)
                // 与 macOS 版同一个 key（同一份翻译，不要两边各写一句）
                notice = Notice(title: String(localized: "Rules imported successfully"), body: "")
            } catch {
                notice = Notice(title: String(localized: "Import failed"), body: error.localizedDescription)
            }
        }
    }
}
