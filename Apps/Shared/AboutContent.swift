import SwiftUI

/// app 版本号（「0.6.0 (600)」）。
///
/// 放 Shared 里是因为**两端格式必须一致**：macOS 填设置窗口、iOS 填「How to Use」页尾。
enum AppVersion {
    static var display: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

/// 对外链接。**与 Android 侧 `AboutScreen.kt` 里的那批是同一组 URL。**
enum LinkPureLinks {
    static let github = URL(string: "https://github.com/rxliuli/LinkPure")!
    static let discord = URL(string: "https://discord.gg/gFhKUthc88")!
    static let website = URL(string: "https://rxliuli.com/project/linkpure")!
    static let clearURLs = URL(string: "https://github.com/ClearURLs/Addon")!
    static let linkumori = URL(string: "https://github.com/Linkumori/Linkumori-Extension")!
}

/// 规则库署名。
///
/// **这是许可要求，不是装饰。** `shared-rules.json` 是 LGPL-3.0 的（规则来自
/// ClearURLs 与 Linkumori）。只写在仓库 README 里的话，**装到设备上的用户看不到**。
struct RulesAttribution: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Built-in rules")
                .font(.footnote.weight(.semibold))
            Text(
                "The rule library is assembled from ClearURLs and Linkumori, and is distributed under the LGPL-3.0. LinkPure itself is GPL-3.0."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Link("ClearURLs", destination: LinkPureLinks.clearURLs)
                Link("Linkumori", destination: LinkPureLinks.linkumori)
            }
            .font(.caption)
        }
    }
}
