import AppKit
import SwiftUI

@main
struct ClipAllApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(environment: environment)
        } label: {
            MenuBarStatusIcon(settings: environment.settings)
                .task { await environment.start() }
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
    @ObservedObject private var settings: SettingsStore
    @Environment(\.openWindow) private var openWindow

    init(environment: AppEnvironment) {
        self.environment = environment
        _settings = ObservedObject(wrappedValue: environment.settings)
    }

    var body: some View {
        Toggle("启用 ClipAll", isOn: monitoringBinding)

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

    private var monitoringBinding: Binding<Bool> {
        Binding(
            get: { settings.isMonitoringEnabled },
            set: { settings.isMonitoringEnabled = $0 }
        )
    }

    private func bringSettingsToFront() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
