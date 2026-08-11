import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permissions: AccessibilityPermissionService

    var body: some View {
        ScrollView {
            VStack(spacing: ClipAllTheme.Spacing.sm) {
                ClipAllSectionCard(
                    "取词",
                    subtitle: "控制是否在选择文字后自动显示操作栏。"
                ) {
                    HStack(alignment: .center, spacing: ClipAllTheme.Spacing.md) {
                        Label("自动监听文字选择", systemImage: "selection.pin.in.out")
                            .fontWeight(.medium)
                        Spacer()
                        Toggle("", isOn: monitoringBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .fixedSize()
                    }
                }

                ClipAllSectionCard(
                    "全局快捷键",
                    subtitle: "在任意 App 中主动读取当前选中文字。"
                ) {
                    HStack(spacing: ClipAllTheme.Spacing.sm) {
                        Text("显示取词浮窗")
                            .fontWeight(.medium)
                        Spacer()
                        Text(shortcutLabel)
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .clipAllInset(cornerRadius: ClipAllTheme.Radius.control)
                        Button("恢复默认") { settings.globalShortcut = .standard }
                    }
                }

                ClipAllSectionCard(
                    "应用入口",
                    subtitle: "控制 Dock 与菜单栏图标，至少保留一个入口。"
                ) {
                    VStack(spacing: ClipAllTheme.Spacing.sm) {
                        HStack(alignment: .center, spacing: ClipAllTheme.Spacing.md) {
                            Label("显示菜单栏图标", systemImage: "menubar.rectangle")
                                .fontWeight(.medium)
                            Spacer()
                            Toggle("", isOn: menuBarIconBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .fixedSize()
                                .disabled(
                                    settings.isMenuBarIconVisible
                                        && !settings.isDockIconVisible
                                )
                        }

                        Divider()

                        HStack(alignment: .center, spacing: ClipAllTheme.Spacing.md) {
                            Label("显示 Dock 图标", systemImage: "dock.rectangle")
                                .fontWeight(.medium)
                            Spacer()
                            Toggle("", isOn: dockIconBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .fixedSize()
                                .disabled(
                                    settings.isDockIconVisible
                                        && !settings.isMenuBarIconVisible
                                )
                        }
                    }
                }

                ClipAllSectionCard(
                    "兼容取词",
                    subtitle: "辅助功能无法读取时，临时模拟复制并恢复原剪贴板。"
                ) {
                    VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.sm) {
                        HStack(alignment: .center, spacing: ClipAllTheme.Spacing.md) {
                            Label("启用复制回退", systemImage: "doc.on.clipboard")
                                .fontWeight(.medium)
                            Spacer()
                            Toggle("", isOn: $settings.isSelectionFallbackEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .fixedSize()
                        }

                        if !settings.selectionFallbackExcludedBundleIdentifiers.isEmpty {
                            Divider()
                            ForEach(settings.selectionFallbackExcludedBundleIdentifiers, id: \.self) {
                                bundleIdentifier in
                                HStack(spacing: ClipAllTheme.Spacing.sm) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(applicationName(for: bundleIdentifier))
                                        Text(bundleIdentifier)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("移除") {
                                        settings.setSelectionFallbackExcluded(
                                            bundleIdentifier,
                                            isExcluded: false
                                        )
                                    }
                                }
                            }
                        }

                        Button("添加排除应用…") { chooseExcludedApplication() }
                            .disabled(!settings.isSelectionFallbackEnabled)
                    }
                }

                ClipAllSectionCard(
                    "辅助功能权限",
                    subtitle: "只用于读取当前选中文字和选区位置。"
                ) {
                    HStack(alignment: .center, spacing: ClipAllTheme.Spacing.sm) {
                        Label(
                            permissionStatusText,
                            systemImage: permissions.isTrusted
                                ? "checkmark.circle.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .fontWeight(.medium)
                        .foregroundStyle(permissions.isTrusted ? Color.green : ClipAllTheme.accent)

                        if permissions.isAwaitingAuthorization, !permissions.isTrusted {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Spacer()

                        Button(permissions.isTrusted ? "重新检查" : "请求权限…") {
                            if permissions.isTrusted {
                                permissions.refresh()
                            } else {
                                permissions.requestPermission()
                            }
                        }
                        .disabled(permissions.isAwaitingAuthorization && !permissions.isTrusted)

                        Button("打开系统设置") { permissions.openSystemSettings() }
                    }
                }
            }
            .frame(maxWidth: 760)
            .padding(ClipAllTheme.Spacing.lg)
            .frame(maxWidth: .infinity)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    private var monitoringBinding: Binding<Bool> {
        Binding(
            get: { settings.isMonitoringEnabled },
            set: { settings.isMonitoringEnabled = $0 }
        )
    }

    private var menuBarIconBinding: Binding<Bool> {
        Binding(
            get: { settings.isMenuBarIconVisible },
            set: { settings.setMenuBarIconVisible($0) }
        )
    }

    private var dockIconBinding: Binding<Bool> {
        Binding(
            get: { settings.isDockIconVisible },
            set: { settings.setDockIconVisible($0) }
        )
    }

    private var shortcutLabel: String {
        settings.globalShortcut == .standard ? "⌃⌥Space" : "自定义快捷键"
    }

    private func chooseExcludedApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleIdentifier = Bundle(url: url)?.bundleIdentifier,
              bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        settings.setSelectionFallbackExcluded(bundleIdentifier, isExcluded: true)
    }

    private func applicationName(for bundleIdentifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else { return bundleIdentifier }
        return FileManager.default.displayName(atPath: url.path)
    }

    private var permissionStatusText: String {
        if permissions.isTrusted { return "已授权" }
        if permissions.isAwaitingAuthorization { return "等待系统授权" }
        return "未授权"
    }
}
