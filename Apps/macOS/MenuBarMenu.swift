import AppKit
import SwiftUI

/// 菜单栏下拉菜单：只放状态与快捷操作。
///
/// 刻意**不提供**"暂停监听"——不想用就退出 app，少一个能弄坏它的状态。
struct MenuBarMenu: View {
    @ObservedObject var model: AppModel
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
        // 先把 app 拉起来（菜单也跟着收起），但**真正决定成败的是后面那一步**：
        // 走桥里的 openAndActivate，它会先 openWindow，等窗口确实建出来再抢前台。
        // 顺序反了就是「窗口开了但没激活」——实测复现率 15%。
        NSApp.activate(ignoringOtherApps: true)
        MainWindowOpener.shared.openAndActivate()
    }

    /// 设置窗口归系统管，但**把 app 拉到最前**得自己做——
    /// 否则从菜单栏点完，窗口开在别人后面，看起来像没反应。
    /// 同样要等窗口建出来再抢，理由见 `MainWindowOpener.bringToFront`。
    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        MainWindowOpener.shared.bringToFront()
    }

    private func shorten(_ url: String) -> String {
        url.count > 48 ? String(url.prefix(48)) + "…" : url
    }
}
