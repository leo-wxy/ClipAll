import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permissions: AccessibilityPermissionService

    var body: some View {
        ScrollView {
            VStack(spacing: ClipAllTheme.Spacing.sm) {
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

    private var permissionStatusText: String {
        if permissions.isTrusted { return "已授权" }
        if permissions.isAwaitingAuthorization { return "等待系统授权" }
        return "未授权"
    }
}
