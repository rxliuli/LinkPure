import SwiftUI

/// 应用设置（⌘,）。
///
/// 「开机时自动启动」原本挤在主窗口底栏里。那是**应用级**设置、不是窗口级操作，
/// 放进这里有两个实际好处：
///
///   1. 免费的 ⌘, 和标准的设置窗口，跟系统里其他 app 一致；
///   2. 每次打开都重新读一遍系统状态——之前那个 `@State` 只初始化一次，
///      用户在「系统设置 > 通用 > 登录项」里改过之后，主窗口的开关会显示成旧的。
struct SettingsView: View {
    @ObservedObject var model: AppModel

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { applyLaunchAtLogin($0) }
                ))
                Text("Stays quietly in the menu bar after login. No window is shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Status") {
                // 计数用 `Text` 而不是 `value: "\(n) 条"`：拼出来的 `String`
                // 不过本地化系统，复数（1 rule / 5 rules）也就丢了。
                LabeledContent("Custom rules") { Text("\(model.userRules.count) rules") }
                LabeledContent("Built-in rules") { Text("\(model.sharedRules.count) rules") }
                LabeledContent("URLs rewritten") { Text(model.rewriteCount, format: .number) }
            }

            Section {
                LabeledContent("Version", value: AppVersion.display)
            }

            // 链接放设置窗口，而不是 Help 菜单：这是个 `LSUIElement` 菜单栏 app，
            // **它几乎不前台**（菜单栏 app 级菜单只在 app 前台时存在），
            // 所以 Help 菜单用户基本看不到。设置窗口才是两个入口
            // （状态栏菜单 / 主窗口侧边栏）都够得到的那个。
            //
            // 版本号由系统自带的 About 面板（`.appInfo` 没被动过）负责，这里不重复。
            Section("Links") {
                Link("GitHub", destination: LinkPureLinks.github)
                Link("Discord", destination: LinkPureLinks.discord)
                Link("Website", destination: LinkPureLinks.website)
            }

            Section {
                RulesAttribution()
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 400)
    }

    private func applyLaunchAtLogin(_ on: Bool) {
        if let failure = LaunchAtLogin.set(on) {
            error = String(localized: "Could not change the launch at login setting: \(failure)")
            // 回到系统里的真实状态（注册失败时其实没生效）
            launchAtLogin = LaunchAtLogin.isEnabled
        } else {
            launchAtLogin = on
            error = nil
        }
    }
}
