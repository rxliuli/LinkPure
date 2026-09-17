import Foundation
import ServiceManagement
import os

/// 开机自启（`SMAppService.mainApp`）。
///
/// 注意：`register()` 需要 app 处于系统认可的位置（通常在 `/Applications`），
/// 从 DerivedData 直接跑时**可能失败**——所以要报错，不能吞掉，
/// 否则用户只会看到开关自己弹回去而不知道为什么。
enum LaunchAtLogin {
    private static let log = Logger(subsystem: "com.rxliuli.linkpure", category: "login")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 返回错误描述；`nil` 表示成功。
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            let status = SMAppService.mainApp.status
            log.error("loginItem=\(enabled, privacy: .public) ok, status=\(status.rawValue, privacy: .public)")
            return nil
        } catch {
            log.error("loginItem=\(enabled, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }
}
