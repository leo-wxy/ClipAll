import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permissions: AccessibilityPermissionService

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                settingsBlock(title: "取词") {
                    Toggle("自动监听文字选择", isOn: monitoringBinding)
                    Text("关闭后不会自动弹出取词面板，能力中心和设置仍然可用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                settingsBlock(title: "全局快捷键") {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("显示取词面板")
                                .fontWeight(.medium)
                            Text("在任意 App 中主动唤起当前选中文字。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(shortcutLabel)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(ClipAllTheme.quietFill, in: RoundedRectangle(cornerRadius: 7))
                        Button("恢复默认") { settings.globalShortcut = .standard }
                    }
                }

                settingsBlock(title: "辅助功能权限") {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(
                                permissionStatusText,
                                systemImage: permissions.isTrusted
                                    ? "checkmark.circle.fill"
                                    : "exclamationmark.triangle.fill"
                            )
                            .fontWeight(.medium)
                            .foregroundStyle(
                                permissions.isTrusted ? Color.green : ClipAllTheme.accent
                            )
                            Text("ClipAll 只用该权限读取当前选中文字和选区位置。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if permissions.isAwaitingAuthorization, !permissions.isTrusted {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button(permissions.isTrusted ? "重新检查" : "请求权限…") {
                            if permissions.isTrusted {
                                permissions.refresh()
                            } else {
                                permissions.requestPermission()
                            }
                        }
                        Button("打开系统设置") { permissions.openSystemSettings() }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    private func settingsBlock<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipAllSurface()
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
