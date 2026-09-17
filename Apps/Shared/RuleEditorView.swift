import SwiftUI
import LinkPureCore

/// 打开编辑器的目标：规则 + 上次的测试 URL + **打开前就同步算好的预览**。
///
/// 为什么要预计算：`.sheet` 内容在出现的那一帧就完成布局，若让编辑器自己在
/// `.task` 里算，弹窗会先以“没有结果”的高度出现、拿到结果后再长高一次——
/// 肉眼就是一次闪烁。
///
/// 规则匹配/替换本身是同步的，只有 `followRedirect` 要联网；所以本地能算的
/// 在这里算完，算不了（需要联网、或测试 URL 还不是合法 URL）就留空，
/// 交给编辑器里的异步路径补上（那条路径也会画“不是有效 URL”的提示）。
struct EditorTarget: Identifiable {
    let rule: Rule
    let testUrl: String?
    let preview: MatchResult?
    var id: String { rule.id }

    @MainActor
    init(rule: Rule, testUrl: String?, rulesetForTesting: (Rule) -> [Rule]) {
        self.rule = rule
        self.testUrl = testUrl
        self.preview = RuleEditingPreview.compute(
            draft: rule,
            testUrl: testUrl,
            ruleset: rulesetForTesting(rule)
        )
    }
}

/// 规则编辑（macOS 用 sheet，iOS 用 NavigationStack 包裹的 Form）。
///
/// 带**测试 URL 字段与实时预览**，语义与 Redirector 的 RuleDialog 一致：
/// 把草稿规则放进**完整规则集**里跑出整条改写链——
/// 而不是只测这条规则本身（那样会与真实行为不符：
/// 别的规则可能先把 URL 改成草稿能匹配的样子）。
struct RuleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Rule
    @State private var testUrl: String
    @State private var testResult: MatchResult?
    private let rulesetProvider: (Rule) -> [Rule]
    private let onSave: (Rule, String?) -> Void

    init(
        rule: Rule,
        testUrl: String?,
        initialResult: MatchResult? = nil,
        rulesetProvider: @escaping (Rule) -> [Rule],
        onSave: @escaping (Rule, String?) -> Void
    ) {
        _draft = State(initialValue: rule)
        _testUrl = State(initialValue: testUrl ?? "")
        // 打开前就算好的预览：弹窗**第一帧**就带着它画出来。
        // 留空也没关系，下面的 `.task` 会用异步路径（能跟随重定向）补上。
        _testResult = State(initialValue: initialResult)
        self.rulesetProvider = rulesetProvider
        self.onSave = onSave
    }

    private var canSave: Bool {
        !draft.regexFilter.isEmpty && !(draft.regexSubstitution?.isEmpty ?? true)
    }

    private var trimmedTestUrl: String {
        testUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 任一输入变化就重跑测试
    private var testKey: String {
        "\(draft.regexFilter)|\(draft.regexSubstitution ?? "")|\(trimmedTestUrl)"
    }

    private func runTest() async {
        guard !trimmedTestUrl.isEmpty,
              !draft.regexFilter.isEmpty,
              UrlCleaner.isValidUrl(trimmedTestUrl) else {
            testResult = nil
            return
        }
        // 把草稿放进完整规则集里跑（与 Redirector 一致），
        // 这样看到的就是“保存后实际会怎样”。
        let rules = rulesetProvider(draft)
        testResult = await UrlCleaner(rules: rules).check(trimmedTestUrl)
    }

    private func save() {
        let empty = draft.regexSubstitution?.isEmpty ?? true
        onSave(
            Rule(
                id: draft.id,
                regexFilter: draft.regexFilter,
                regexSubstitution: empty ? nil : draft.regexSubstitution,
                removeParams: draft.removeParams
            ),
            trimmedTestUrl.isEmpty ? nil : trimmedTestUrl
        )
        dismiss()
    }

    private var filterBinding: Binding<String> {
        Binding(
            get: { draft.regexFilter },
            set: {
                draft = Rule(id: draft.id, regexFilter: $0,
                             regexSubstitution: draft.regexSubstitution,
                             removeParams: draft.removeParams)
            }
        )
    }

    private var substitutionBinding: Binding<String> {
        Binding(
            get: { draft.regexSubstitution ?? "" },
            set: {
                draft = Rule(id: draft.id, regexFilter: draft.regexFilter,
                             regexSubstitution: $0.isEmpty ? nil : $0,
                             removeParams: draft.removeParams)
            }
        )
    }

    /// 用 `LocalizedStringKey` 而不是拼出来的 `String`：
    /// 字符串拼接会把句子拆成几段，换语言时语序没法重排，也不会进 String Catalog。
    private var hint: LocalizedStringKey {
        "The engine matches on regexFilter, then replaces the whole URL using regexSubstitution ($1..$9 are supported). A rule with an empty replacement is invalid, and Save stays disabled."
    }

    private var previewHint: LocalizedStringKey {
        "The test runs your draft through the whole rule set, so what you see is what a saved rule would actually do."
    }

    var body: some View {
        #if os(macOS)
            macBody
        #else
            iosBody
        #endif
    }

    @ViewBuilder
    private var preview: some View {
        if !trimmedTestUrl.isEmpty {
            if !UrlCleaner.isValidUrl(trimmedTestUrl) {
                RuleTestResultView.invalid()
            } else if let testResult {
                RuleTestResultView(result: testResult)
            }
        }
    }

    // MARK: - macOS

    #if os(macOS)
        /// mac 侧用 `Form` + `.grouped`，而不是自己 `VStack` 一堆 `TextField`。
        ///
        /// 系统会给出跟「系统设置」一致的成组卡片、标签与控件对齐、行高，
        /// 以及跟着主题/强调色走的配色。手摆 `HStack` 只能复刻**某一版** macOS
        /// 的样子，复刻不了它的行为（窗口变窄时怎么收缩、标签怎么换行）。
        private var macBody: some View {
            VStack(spacing: 0) {
                Form {
                    Section("Regular Expression Match") {
                        TextField("^https://example\\.com/(.*)$", text: filterBinding)
                            .font(.system(.body, design: .monospaced))
                            .labelsHidden()
                    }

                    Section("Replace With") {
                        TextField("https://example.com/$1", text: substitutionBinding)
                            .font(.system(.body, design: .monospaced))
                            .labelsHidden()
                    }

                    Section("Test URL (optional)") {
                        TextField("Paste a URL to test it right away", text: $testUrl)
                            .font(.system(.body, design: .monospaced))
                            .labelsHidden()
                    }

                    Section("Preview") {
                        preview.frame(maxWidth: .infinity, alignment: .leading)
                        Text(previewHint).font(.caption).foregroundStyle(.secondary)
                    }

                    Section {
                        Text(hint).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)

                Divider()

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave)
                }
                .padding(12)
            }
            .frame(width: 560, height: 580)
            .task(id: testKey) { await runTest() }
        }
    #endif

    // MARK: - iOS

    #if os(iOS)
        private var iosBody: some View {
            NavigationStack {
                Form {
                    Section("Regular Expression Match") {
                        TextField("^https://example\\.com/...", text: filterBinding)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Section("Replace With") {
                        TextField("https://example.com/$1", text: substitutionBinding)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Section("Test URL (optional)") {
                        TextField("Paste a URL to test it right away", text: $testUrl)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                    Section("Preview") {
                        preview
                        Text(previewHint).font(.caption2).foregroundStyle(.secondary)
                    }
                    Section {
                        Text(hint).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Rule")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }.disabled(!canSave)
                    }
                }
                .task(id: testKey) { await runTest() }
            }
        }
    #endif
}
