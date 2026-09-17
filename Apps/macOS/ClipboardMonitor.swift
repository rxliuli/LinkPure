import AppKit
import Foundation
import LinkPureCore

/// 监听系统剪贴板：轮询 `changeCount`（AppKit 没有变更通知）。
///
/// 注意：这与 iOS 的处境完全不同——macOS 上后台轮询剪贴板是**允许**的，
/// 所以桌面端能做到真正的「零操作自动改写」。
@MainActor
final class ClipboardMonitor {
    /// 返回改写后的 URL；返回 nil 表示不改写。
    var handler: ((String) async -> String?)?
    /// 成功改写后的回调（用于通知/日志）。
    var onRewritten: ((String, String) -> Void)?

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    /// 自己写回的内容不要再被当成"用户复制的新内容"
    private var lastWritten: String?

    private(set) var isRunning = false

    func start(interval: TimeInterval = 0.4) {
        guard !isRunning else { return }
        isRunning = true
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    private func tick() async {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let raw = pasteboard.string(forType: .string) else { return }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != lastWritten else { return }
        guard let rewritten = await handler?(text), rewritten != text else { return }

        lastWritten = rewritten
        pasteboard.clearContents()
        pasteboard.setString(rewritten, forType: .string)
        // 写回会再次改变 changeCount，同步掉，避免自触发
        lastChangeCount = pasteboard.changeCount

        onRewritten?(text, rewritten)
    }
}
