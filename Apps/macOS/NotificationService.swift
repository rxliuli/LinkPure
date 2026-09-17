import Foundation
import os
import UserNotifications

/// 通知封装。
///
/// 三个容易踩的坑，都在这里处理掉了：
///   1. 必须设 `delegate`，否则 app 在前台时通知会被系统静默丢弃。
///   2. 授权失败必须**记日志**，不能吞掉——否则表现就是"什么都没发生"。
///   3. macOS 的横幅默认会留在通知中心，需要**主动移除**才会几秒后消失
///      （Flutter 版也是这么做的：3 秒后 cancel）。
enum NotificationService {
    private static let log = Logger(subsystem: "com.rxliuli.linkpure.mac", category: "notify")

    final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        static let shared = Delegate()

        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification,
            withCompletionHandler completionHandler:
                @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            // 即便 app 在前台也照常弹出（对菜单栏应用尤其重要）
            completionHandler([.banner, .sound])
        }
    }

    static func bootstrap() {
        UNUserNotificationCenter.current().delegate = Delegate.shared
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound])
                log.error("authorization granted = \(granted, privacy: .public)")
            } catch {
                log.error("authorization threw: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 弹一条通知，并在 `autoDismissAfter` 秒后自动收起。
    static func post(title: String, body: String, autoDismissAfter seconds: TimeInterval = 3) {
        let id = UUID().uuidString
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.interruptionLevel = .active

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                log.error("add() failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // 主动移除已投递的通知，否则横幅会一直挂在通知中心里
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            UNUserNotificationCenter.current()
                .removeDeliveredNotifications(withIdentifiers: [id])
        }
    }
}
