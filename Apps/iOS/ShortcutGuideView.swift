import SwiftUI

/// 使用方式说明。
///
/// iOS 上不存在"自动改写"——这是系统限制，不是实现偷懒。
/// 这一屏的任务就是把"为什么"和"怎么做"讲清楚，并把配置成本压到最低。
///
/// 文案注意事项：这里提到的动作名（Get Clipboard / Copy to Clipboard /
/// Show Notification / If）和系统路径（Control Center / Back Tap）都是
/// **Apple 自己会本地化的系统术语**。翻译时必须用各语言里 Apple 的官方叫法，
/// 否则用户按图索骥找不到——这一类文本最容易被意译搞坏。
struct ShortcutGuideView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                whySection
                stepsSection
                entrySection
                verifySection
            }
            .navigationTitle("How to Use")
        }
    }

    // MARK: - 为什么不能自动

    private var whySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("iOS can't rewrite automatically", systemImage: "exclamationmark.shield")
                    .font(.headline)

                Text("On iOS, an app that reads the clipboard is either blocked (background reads) or triggers an “Allow Paste” prompt first (foreground reads). So “copy it and it's already clean” can't be done on this platform — that's a system limitation, not a shortcut this app is taking.")
                    .font(.footnote)

                Text("The macOS version isn't affected: copy a link and it's rewritten automatically, with nothing to press.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 三步设置

    private var stepsSection: some View {
        Section {
            step(
                n: 1, icon: "square.and.arrow.down",
                title: "Open the Shortcuts app and create a new shortcut",
                detail: "Search for and add the “Get Clipboard” action"
            )
            step(
                n: 2, icon: "wand.and.stars",
                title: "Add LinkPure's “Clean URL Text” action",
                detail: "Set its URL parameter to the output of step 1 (tap the parameter → choose “Clipboard”)"
            )
            step(
                n: 3, icon: "arrow.triangle.branch",
                title: "Add an “If” and put the write-back actions inside it",
                detail: "Condition: Clean URL Text “is not” Clipboard — drag both variables into the condition"
            )
            nestedAction("Inside “If”: “Copy to Clipboard”, with the input set to Clean URL Text")
            nestedAction("Inside “If”: “Show Notification”, with the content set to Clean URL Text (optional, just for feedback)")
            nestedAction("Leave the “Otherwise” branch empty: if the result didn't change, do nothing")
        } header: {
            Text("Set up (once)")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("The flow:")
                Text("Get Clipboard (read by the system) → Clean URL Text (this app) → copy back + notify, only if the URL changed")
                    .font(.system(.caption2, design: .monospaced))
                Text("The important part: the clipboard is read by the **system**, not by this app — so iOS never shows an “Allow Paste” prompt.")
                    .padding(.top, 2)
                Text("There's exactly one thing to get right: “Copy to Clipboard” must be **inside** the “If”. Put it outside and every run writes the clipboard again even when nothing changed — iOS doesn't de-duplicate clipboard writes, so you'd trigger a Universal Clipboard sync for nothing, and any rich text you copied gets flattened to plain text (non-text content may be dropped entirely). Clean URL Text itself has no side effects; all the risk lives in where that write-back sits.")
                    .padding(.top, 2)
            }
        }
    }

    /// 「如果」分支里的动作。缩进 + 拐弯箭头，让从属关系在视觉上成立。
    private func nestedAction(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.turn.down.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 28)
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func step(
        n: Int, icon: String,
        title: LocalizedStringKey, detail: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 28, height: 28)
                // 纯数字不需要过本地化（`Text("\(n)")` 会生成一个 `%lld` 的 key）
                Text(n, format: .number).font(.footnote.bold()).foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - 挂到顺手的位置

    private var entrySection: some View {
        Section {
            entryItem(icon: "switch.2", title: "Control Center",
                      detail: "Swipe down → “+” in the top left → Add a Control → search for “Shortcuts”, then pick this one")
            entryItem(icon: "hand.tap", title: "Back Tap",
                      detail: "Settings → Accessibility → Touch → Back Tap → pick this shortcut")
            entryItem(icon: "mic", title: "Siri",
                      detail: "Say the shortcut's name, e.g. “Hey Siri, Clean URL”")
        } header: {
            Text("Put it somewhere within reach")
        } footer: {
            Text("Control Center is the best pick: one swipe from any app, no switching required.")
        }
    }

    private func entryItem(
        icon: String,
        title: LocalizedStringKey, detail: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 26)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 验证

    private var verifySection: some View {
        Section {
            // 用 enabledUserRuleCount 而不是 enabledRules.count：后者已经含了
            // 全部共享规则，会和下面那行重复计数（1061 条 + 1061 条）。
            LabeledContent("Enabled custom rules") { Text("\(model.enabledUserRuleCount) rules") }
            LabeledContent("Built-in shared rules") { Text("\(model.sharedRules.count) rules") }
        } header: {
            Text("Current status")
        } footer: {
            Text("Want to try it in the app first? Switch to the Rules tab — there's a test field there.")
        }
    }
}
