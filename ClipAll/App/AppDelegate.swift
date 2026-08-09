import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            NotificationCenter.default.post(name: .clipAllOpenSettings, object: nil)
        }
        return true
    }
}

extension Notification.Name {
    static let clipAllOpenSettings = Notification.Name("com.wxy.ClipAll.openSettings")
}
