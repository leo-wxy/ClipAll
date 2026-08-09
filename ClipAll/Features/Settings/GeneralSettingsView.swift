import AppKit
import SwiftUI

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
            .frame(maxWidth: 680)
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

    private var shortcutLabel: String {
        settings.globalShortcut == .standard ? "⌃⌥Space" : "自定义快捷键"
    }

    private var permissionStatusText: String {
        if permissions.isTrusted { return "已授权" }
        if permissions.isAwaitingAuthorization { return "等待系统授权" }
        return "未授权"
    }
}
