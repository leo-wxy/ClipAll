import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var permissions: AccessibilityPermissionService

    var body: some View {
        ClipAllSettingsPage(
            "通用",
            subtitle: "管理外观、全局快捷键、应用入口和辅助功能权限。"
        ) {
                ClipAllSettingsSection(
                    "外观",
                    subtitle: "设置窗口与取词浮窗会同步使用所选外观。"
                ) {
                    ClipAllSettingsRow(
                        "显示模式",
                        subtitle: "跟随系统，或固定使用浅色、深色效果。",
                        symbolName: "circle.lefthalf.filled"
                    ) {
                        Picker("显示模式", selection: $settings.appearancePreference) {
                            ForEach(AppearancePreference.allCases, id: \.self) { appearance in
                                Text(appearanceTitle(appearance)).tag(appearance)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 250)
                        .accessibilityLabel("显示模式")
                    }
                }

                ClipAllSettingsSection(
                    "全局快捷键",
                    subtitle: "在任意 App 中主动读取当前选中文字。"
                ) {
                    ClipAllSettingsRow(
                        "显示取词浮窗",
                        subtitle: "按下快捷键后读取当前选区并显示操作栏。",
                        symbolName: "keyboard"
                    ) {
                        HStack(spacing: ClipAllTheme.Spacing.sm) {
                            ClipAllTag(
                                shortcutLabel,
                                tone: .accent,
                                systemImage: "command"
                            )
                            Button("恢复默认") { settings.globalShortcut = .standard }
                                .buttonStyle(ClipAllButtonStyle(variant: .secondary))
                                .accessibilityLabel("恢复默认快捷键")
                        }
                    }
                }

                ClipAllSettingsSection(
                    "应用入口",
                    subtitle: "控制 Dock 与菜单栏图标，至少保留一个入口。"
                ) {
                    VStack(spacing: ClipAllTheme.Spacing.xs) {
                        ClipAllSettingsRow(
                            "显示菜单栏图标",
                            subtitle: "在屏幕顶部随时打开 ClipAll。",
                            symbolName: "menubar.rectangle"
                        ) {
                            Toggle("", isOn: menuBarIconBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .fixedSize()
                                .accessibilityLabel("显示菜单栏图标")
                                .disabled(
                                    settings.isMenuBarIconVisible
                                        && !settings.isDockIconVisible
                                )
                        }

                        ClipAllSettingsRow(
                            "显示 Dock 图标",
                            subtitle: "从 Dock 打开设置并保留标准 App 入口。",
                            symbolName: "dock.rectangle"
                        ) {
                            Toggle("", isOn: dockIconBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .fixedSize()
                                .accessibilityLabel("显示 Dock 图标")
                                .disabled(
                                    settings.isDockIconVisible
                                        && !settings.isMenuBarIconVisible
                                )
                        }
                    }
                }

                ClipAllSettingsSection(
                    "辅助功能权限",
                    subtitle: "只用于读取当前选中文字和选区位置。"
                ) {
                    ClipAllSettingsRow(minimumHeight: 72) {
                        HStack(spacing: ClipAllTheme.Spacing.sm) {
                            ClipAllIconBadge(
                                symbolName: permissions.isTrusted
                                    ? "checkmark.shield.fill"
                                    : "exclamationmark.shield.fill",
                                size: ClipAllTheme.Size.iconMedium,
                                tone: permissions.isTrusted ? .success : .warning
                            )
                            VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.xxs) {
                                HStack(spacing: ClipAllTheme.Spacing.xs) {
                                    Text("辅助功能")
                                        .font(ClipAllTheme.Typography.body.weight(.medium))
                                        .foregroundStyle(ClipAllTheme.textPrimary)
                                    ClipAllTag(
                                        permissionStatusText,
                                        tone: permissions.isTrusted ? .success : .warning
                                    )
                                }
                                Text(permissionDetailText)
                                    .font(ClipAllTheme.Typography.supporting)
                                    .foregroundStyle(ClipAllTheme.textSecondary)
                            }
                        }
                    } trailing: {
                        HStack(spacing: ClipAllTheme.Spacing.sm) {
                            if permissions.isAwaitingAuthorization, !permissions.isTrusted {
                                ProgressView()
                                    .controlSize(.small)
                                    .accessibilityLabel("等待系统授权")
                            }

                            Button(permissionActionTitle) {
                                if permissions.isTrusted || permissions.isAwaitingAuthorization {
                                    permissions.refresh()
                                } else {
                                    permissions.requestPermission()
                                }
                            }
                            .buttonStyle(
                                ClipAllButtonStyle(
                                    variant: permissions.isTrusted || permissions.isAwaitingAuthorization
                                        ? .secondary
                                        : .primary
                                )
                            )
                            .accessibilityLabel(
                                permissions.isTrusted
                                    ? "重新检查辅助功能权限"
                                    : permissions.isAwaitingAuthorization
                                        ? "检查辅助功能授权结果"
                                        : "请求辅助功能权限"
                            )

                            Button("系统设置") { permissions.openSystemSettings() }
                                .buttonStyle(ClipAllButtonStyle(variant: .secondary))
                                .accessibilityLabel("打开辅助功能系统设置")
                        }
                    }
                }
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

    private func appearanceTitle(_ appearance: AppearancePreference) -> String {
        switch appearance {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    private var permissionStatusText: String {
        if permissions.isTrusted { return "已授权" }
        if permissions.isAwaitingAuthorization { return "等待系统授权" }
        return "未授权"
    }

    private var permissionActionTitle: String {
        if permissions.isTrusted { return "重新检查" }
        if permissions.isAwaitingAuthorization { return "检查授权" }
        return "请求权限"
    }

    private var permissionDetailText: String {
        permissions.isTrusted
            ? "ClipAll 可以读取文字选区；不会记录其他输入内容。"
            : "授权后才能自动读取文字与选区位置。"
    }
}
