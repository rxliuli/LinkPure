import AppKit
import SwiftUI

/// 菜单栏下拉菜单：只放状态与快捷操作。
///
/// 刻意**不提供**"暂停监听"——不想用就退出 app，少一个能弄坏它的状态。
struct MenuBarMenu: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text("\(model.rewriteCount) URLs rewritten")

        if let last = model.lastRewritten, !last.to.isEmpty {
            Text(shorten(last.to))
        }

        Divider()

        Button("Open LinkPure…") { showMainWindow() }
            .keyboardShortcut("o")

        // 这是个 `LSUIElement` app：没有 Dock 图标，设置窗口只能从菜单栏进
        // （⌘, 也能用，但没人会对着一个菜单栏图标按 ⌘,）。
        Button("Settings…") { showSettings() }
            .keyboardShortcut(",")

        Divider()

        Button("Quit LinkPure") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }

    /// 设置窗口归系统管，但**把 app 拉到最前**得自己做——
    /// 否则从菜单栏点完，窗口开在别人后面，看起来像没反应。
    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    private func shorten(_ url: String) -> String {
        url.count > 48 ? String(url.prefix(48)) + "…" : url
    }
}
