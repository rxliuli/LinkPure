import SwiftUI
import LinkPureCore

/// 改写链展示。
///
/// 参照 Redirector 扩展的 RuleCheckResult：不只给一个结果，而是把
/// 每一步都列出来——调试规则时这才是有用的信息。
struct UrlChainView: View {
    let urls: [String]
    /// 最后一步高亮成红色（用于循环重定向，指出卡在哪一环）
    var highlightLast = false
    /// 最多显示几条，其余折叠
    var limit: Int?

    private var shown: [String] { limit.map { Array(urls.prefix($0)) } ?? urls }
    private var hidden: Int { max(0, urls.count - shown.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, url in
                Text(url)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isBad(index) ? Color.red.opacity(0.15) : Color.secondary.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(isBad(index) ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
            }
            if hidden > 0 {
                Text("… \(hidden) more steps")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func isBad(_ index: Int) -> Bool {
        highlightLast && index == shown.count - 1
    }
}

/// 测试结果展示（macOS / iOS 共用）。
///
/// 注意：**不要用固定高度的 ScrollView 包裹**——ScrollView 会撑满可用高度，
/// 内容很短时会留出一大块纵向空白。这里靠 `chainLimit` 限制长度，
/// 让高度自然贴合内容。
struct RuleTestResultView: View {
    let result: MatchResult
    var chainLimit = 6
    /// 结果为空（输入不是合法 URL）
    static func invalid() -> some View {
        MessageRow(icon: "questionmark.circle", tint: .secondary,
                   title: "Not a valid http(s) URL")
    }

    var body: some View {
        switch result.status {
        case .matched:
            VStack(alignment: .leading, spacing: 6) {
                MessageRow(
                    icon: "checkmark.circle.fill", tint: .green,
                    title: "Rewrite chain (\(result.chain.count) steps)"
                )
                UrlChainView(urls: result.chain, limit: chainLimit)
            }

        case .notMatched:
            MessageRow(icon: "exclamationmark.triangle.fill", tint: .yellow,
                       title: "No matching rules found for this URL")

        case .circularRedirect:
            VStack(alignment: .leading, spacing: 6) {
                MessageRow(icon: "arrow.triangle.2.circlepath", tint: .red,
                           title: "Circular Redirect")
                UrlChainView(urls: result.chain, highlightLast: true, limit: chainLimit)
            }

        case .infiniteRedirect:
            VStack(alignment: .leading, spacing: 6) {
                MessageRow(icon: "infinity.circle.fill", tint: .red,
                           title: "Maximum redirect limit exceeded")
                UrlChainView(urls: result.chain, limit: 3)
            }
        }
    }
}

private struct MessageRow: View {
    let icon: String
    let tint: Color
    /// `LocalizedStringKey` 而不是 `String`：`String` 不会过本地化，
    /// 也不会进 String Catalog。
    let title: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(title).font(.callout)
        }
    }
}
