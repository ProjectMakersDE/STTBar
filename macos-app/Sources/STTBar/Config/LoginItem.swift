import Foundation
import ServiceManagement

/// "Launch at login" via the modern Service Management API. Replaces the old
/// LaunchAgent plist (forbidden under the App Sandbox).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ on: Bool) -> Bool {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            AppLogger.log("login_item_toggle_failed on=\(on) error=\(error.localizedDescription)")
            return false
        }
    }
}
