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
        .defaultSize(width: 900, height: 620)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsRootView(environment: environment)
        }
    }
}

private struct MenuBarStatusIcon: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Group {
            if let icon = menuBarImage {
                Image(nsImage: icon)
                    .renderingMode(.template)
            } else {
                Image(systemName: "text.cursor")
                    .font(.system(size: 17, weight: .bold))
            }
        }
        .opacity(settings.isMonitoringEnabled ? 1 : 0.45)
        .frame(width: 29, height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(settings.isMonitoringEnabled ? "ClipAll 已启用" : "ClipAll 已停用")
    }

    private var menuBarImage: NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "svg"),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        image.isTemplate = true
        image.size = NSSize(width: 27, height: 16)
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
            openWindow(id: "capability-center")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("k", modifiers: [.command, .shift])

        SettingsLink {
            Text("设置…")
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
}
