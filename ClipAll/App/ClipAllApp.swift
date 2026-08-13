import AppKit
import SwiftUI

@main
struct ClipAllApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarIconBinding) {
            MenuBarContent(environment: environment)
        } label: {
            MenuBarStatusIcon(settings: environment.settings)
        }

        Window("能力中心", id: "capability-center") {
            CapabilityCenterView(environment: environment)
        }
        .defaultSize(width: 860, height: 580)
        .windowResizability(.contentMinSize)

        Window("ClipAll 设置", id: "settings") {
            SettingsRootView(environment: environment)
        }
        .defaultSize(width: 1_140, height: 720)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
    }

    private var menuBarIconBinding: Binding<Bool> {
        Binding(
            get: { environment.settings.isMenuBarIconVisible },
            set: { environment.settings.setMenuBarIconVisible($0) }
        )
    }
}

private struct MenuBarStatusIcon: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let icon = menuBarImage {
                Image(nsImage: icon)
                    .renderingMode(.template)
            } else {
                Image(systemName: "text.cursor")
                    .font(.system(size: 15.3, weight: .bold))
            }
        }
        .opacity(settings.isMonitoringEnabled ? 1 : 0.45)
        .frame(width: 29, height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(settings.isMonitoringEnabled ? "ClipAll 已启用" : "ClipAll 已停用")
        .onReceive(NotificationCenter.default.publisher(for: .clipAllOpenSettings)) { _ in
            openWindow(id: "settings")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private var menuBarImage: NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "svg"),
              let data = try? Data(contentsOf: url, options: .uncached),
              let image = NSImage(data: data)
        else {
            return nil
        }
        image.isTemplate = true
        image.cacheMode = .never
        image.size = NSSize(width: 24.3, height: 14.4)
        return image
    }
}

private struct MenuBarContent: View {
    let environment: AppEnvironment
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("显示当前选区") {
            environment.captureSelectionNow()
        }

        Divider()

        Button("能力中心…") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "capability-center")
        }
        .keyboardShortcut("k", modifiers: [.command, .shift])

        Button("设置…") {
            bringSettingsToFront()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("退出 ClipAll") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func bringSettingsToFront() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
