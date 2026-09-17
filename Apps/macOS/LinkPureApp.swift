import AppKit
import SwiftUI

/// 是不是【安装后第一次运行】。
///
/// 为什么要做成进程内"读一次就写掉"：这个判断被 SwiftUI 侧（`Window` 的启动
/// 展示策略）和 AppKit 侧（要不要把窗口带到最前）同时用到，而两边必须得到**同
/// 一个**答案。`static let` 只求值一次，正好。
private enum FirstRun {
    private static let key = "linkpure.hasLaunched"

    static let isCurrent: Bool = {
        let first = !UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        return first
    }()
}

/// 把 SwiftUI 的 `openWindow` 桥给 AppKit 侧调用。
///
/// 为什么需要这座桥：`openWindow` 只在 SwiftUI 环境里拿得到，但"要不要打开窗口"
/// 这个决定有发生在 AppKit 回调里的场合（`applicationShouldHandleReopen`）。
///
/// 注册点选菜单栏图标的 label view：它是最早被实例化的 SwiftUI 视图（实测它的
/// `onAppear` 跑在 `applicationDidFinishLaunching` **之前**），所以任何时点调用都安全。
@MainActor
final class MainWindowOpener {
    static let shared = MainWindowOpener()
    private var action: (() -> Void)?

    func register(_ action: @escaping () -> Void) { self.action = action }

    /// 打开主窗口，并把它真正带到最前。
    ///
    /// **为什么不能只 `activate` 一下**：`openWindow` 是异步的，调用它那一瞬间窗口
    /// 对象还**不存在**（`.suppressed` 的启动策略不是"把窗口藏起来"，而是根本不创建）。
    /// 对一个没有窗口的 app 请求激活，系统会批准，但随后很容易把前台交还回去；等
    /// 窗口真正建出来时 app 已经不是前台了——表现为「窗口开了但没激活」。
    /// 实测复现率 **15%（20 次里 3 次）**，且失败时 `NSApp.windows` 里确实有一个可见的
    /// 主窗口，只是 app 不 active。
    ///
    /// 所以关键在**时机**：等窗口确实存在之后再抢一次前台并置为 key window。
    /// 用重试而不是单次 `async`——SwiftUI 建窗要几轮 runloop，一次 hop 不保证够。
    /// （早先试过直接 `NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)`
    /// 而不带重试，失败正是因为那一刻窗口尚未被创建。）
    func openAndActivate() {
        action?()
        bringToFront()
    }

    /// 等"能成为 main 的窗口"出现，然后激活 app 并把它置为 key。
    ///
    /// 只认 `canBecomeMain`：菜单栏那个 `NSStatusBarWindow` 不满足（否则会把 app
    /// 激活成"没有窗口"的状态，正是要避免的情形），各种 `NSPanel`（面板、sheet）
    /// 也不满足，所以不会误抓。
    ///
    /// 已知的小瑕疵：它取的是"第一个能成为 main 的窗口"，**不专门认主窗口**。
    /// 所以"设置窗口开着、而主窗口已关"时点「Open LinkPure…」，被置为 key 的可能是
    /// 设置窗口（app 一样会到前台，只是焦点具体落在哪个窗口上不精确）。这个组合很少见，
    /// 为它引入窗口标识匹配的复杂度不划算。
    func bringToFront(attempts: Int = 20) {
        guard attempts > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else {
                // 窗口还没建出来，再等一轮
                self.bringToFront(attempts: attempts - 1)
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
}

/// `LSUIElement` 应用没有 Dock 图标、没有主菜单，用户很难找到它的窗口。
///
/// 启动策略：**只有安装后第一次运行**才展示主窗口——否则装完双击一下什么都不
/// 弹，只会让人以为没装上。之后一律安静地待在菜单栏里：
///
///   - 这个 app 绝大多数时候就是个状态栏工具，窗口仅用于偶尔改规则；
///   - 更关键的是开机自启：`SMAppService.mainApp` 每次登录都会拉起它，等于每次
///     开机往桌面上糊一个 900×600 的窗口，那是错的默认。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `.defaultLaunchBehavior(.presented)` 只负责"展示"，不保证 app 被激活
        // （最前那个 app 可能还是别人）。首次运行要主动抢一次焦点。
        //
        // 必须走 `bringToFront()` 而不能直接 `activate`：启动瞬间窗口同样还没建出来，
        // 直接激活会撞上和菜单栏「Open LinkPure」一模一样的时机问题。
        guard FirstRun.isCurrent else { return }
        MainWindowOpener.shared.bringToFront()
    }

    /// 关掉最后一个窗口**不等于**不用它了。
    ///
    /// 不写这一条的话，菜单栏图标会在用户关窗的瞬间静默消失、剪贴板监听也跟着
    /// 停掉——而用户以为自己只是关了个窗口。AppKit 的默认值就是 false，但这里
    /// 显式写出来，因为它对状态栏应用是**语义性**的，不该依赖默认值。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// 用户从 Finder 再次双击一个已经在运行的 app（也可能来自 `open -a`）——
    /// 这是**显式**意图，该把窗口叫出来。
    ///
    /// 注意这里**不能**用 `NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)`：
    /// `.defaultLaunchBehavior(.suppressed)` 不是"把窗口藏起来"，而是**根本不创建**
    /// （实测：被 suppressed 的启动之后，`NSApp.windows` 里只剩 `NSStatusBarWindow`，
    /// 连一个可用的窗口对象都没有）。所以必须走 SwiftUI 的 openWindow 把场景真正开出来。
    ///
    /// 顺序也重要：激活必须发生在**窗口建出来之后**，所以交给 `openAndActivate()`
    /// 去做（先 openWindow，再等窗口出现才抢前台）。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        MainWindowOpener.shared.openAndActivate()
        return true
    }
}

/// 菜单栏图标本身。除了画图，它唯一的职责是把 `openWindow` 注册到桥上
/// （见 `MainWindowOpener`）——它是最早、也最稳定的注册点。
private struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image("MenuBarIcon")
            .onAppear { MainWindowOpener.shared.register { openWindow(id: "main") } }
    }
}

@main
struct LinkPureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        // 规则管理放在**真正的窗口**里（而不是菜单栏弹窗）：
        // MenuBarExtra 的 .window 形态是个"假窗口"，sheet/焦点行为特殊，
        // 编辑规则这种重 UI 任务不适合塞在里面。
        Window("LinkPure", id: "main") {
            MainWindowView(model: model)
        }
        .defaultSize(width: 900, height: 600)
        // 只有当次是"安装后第一次运行"才展示。
        // 用 `.suppressed` 而不是 `.automatic`：后者会按系统状态恢复窗口显隐，
        // 于是"上次退出时开着窗口 → 这次登录又弹出来"，等于没解决问题。
        // 需要 macOS 15——这是最低版本从 13 抬到 15 的唯一原因。
        .defaultLaunchBehavior(FirstRun.isCurrent ? .presented : .suppressed)
        // `.commands` 是 Scene 修饰符，只能挂在这里；而窗口状态（要建哪条规则、
        // 要不要弹导入面板）活在 `MainWindowView` 里。两边靠 `FocusedValues` 接：
        // 窗口在的时候菜单项可用，窗口关了自动置灰。
        //
        // **必须挂在 `Window` 这个场景上**，不能挂到下面的 `Settings`：
        // 挂在 `Settings` 上，菜单项就只在设置窗口活动时才存在——
        // 按 ⌘N 会什么都不发生（实际踩到过）。
        .commands { RuleCommands() }

        // 菜单栏只做"快速状态 + 开关"，也是窗口被关掉之后**唯一**的入口。
        // 图标用菜单栏专用的裁剪版 artwork（18pt 铺满），
        // **不要**用 NSApp.applicationIconImage —— 那是 Finder 渲染版，
        // 外面带了系统加的圆角底板，实际图形会小 ~30%。
        MenuBarExtra {
            MenuBarMenu(model: model)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.menu)

        // 「开机时自动启动」住在这里。那是**应用级**设置、不是窗口级操作，
        // 塞在主窗口底栏既占地方，作用域也对不上。
        Settings {
            SettingsView(model: model)
        }
    }
}

/// 「文件」菜单里的窗口级命令。
///
/// 键盘可达性不是锦上添花：这是个菜单栏工具，用户一天要开好几次窗口改规则，
/// 每次都拿鼠标去够工具栏上那三个按钮是很差的体验。
private struct RuleCommands: Commands {
    @FocusedValue(\.ruleActions) private var actions

    var body: some Commands {
        // `Settings` 场景**不会**自动给 `LSUIElement` app 装上"设置…"菜单项
        // （实测：菜单栏里没这一项，⌘, 按下去没任何反应；但环境里的 `openSettings()`
        // 是好的，窗口能正常开）。所以自己接一下。
        CommandGroup(replacing: .appSettings) {
            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .newItem) {
            Button("Add Rule") { actions?.createRule() }
                .keyboardShortcut("n")
                .disabled(actions == nil)
        }
        CommandGroup(after: .newItem) {
            Button("Import Rules…") { actions?.importRules() }
                .keyboardShortcut("i")
                .disabled(actions == nil)
            Button("Export Rules…") { actions?.exportRules() }
                .keyboardShortcut("e")
                .disabled(actions?.canExport != true)
        }
        // 删除选中。**必须自己接**：`.onDelete` 在 macOS 上不接管 Delete 键
        // （实测：绑了 selection 之后按 Delete / 前向删除仍然毫无反应）。
        //
        // 快捷键用 ⌘⌫ —— Finder「移到废纸篓」、提醒事项删除都用的它。
        // 已知代价：文本框里 ⌘⌫ 本来有别的含义（删到行首），所以「文本字段获得焦点
        // 的同时恰好有规则处于选中态」时，会删掉规则而不是删到行首。这种情形很少，
        // 且删除有 8 秒撤销条兜底。
        CommandGroup(after: .pasteboard) {
            Button {
                actions?.deleteSelection()
            } label: {
                Text("Delete \(actions?.selectedRuleCount ?? 0) Rules")
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled((actions?.selectedRuleCount ?? 0) == 0)
        }
    }
}
