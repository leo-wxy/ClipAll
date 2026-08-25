import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SelectionSettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        ClipAllSettingsPage(
            "取词",
            subtitle: "控制浮窗何时出现，并为不同 App 保留合适的取词方式。"
        ) {
            automaticDisplaySection
            applicationRulesSection
            compatibilitySection
        }
    }

    private var automaticDisplaySection: some View {
        ClipAllSettingsSection(
            "自动显示",
            subtitle: "控制哪些文字选择操作会自动显示浮窗。"
        ) {
            VStack(spacing: ClipAllTheme.Spacing.xs) {
                settingToggleRow(
                    "自动监听文字选择",
                    subtitle: "监听前台 App 中形成的有效文字选区。",
                    symbol: "selection.pin.in.out",
                    isOn: $settings.isMonitoringEnabled
                )
                settingToggleRow(
                    "拖选或 Shift 扩选后显示",
                    subtitle: "鼠标拖选，或按住 Shift 扩展选区后显示。",
                    symbol: "text.cursor",
                    isOn: $settings.isDragSelectionEnabled
                )
                settingToggleRow(
                    "双击或多击文字后显示",
                    subtitle: "双击单词或多击段落后显示。",
                    symbol: "cursorarrow.click.2",
                    isOn: $settings.isMultiClickSelectionEnabled
                )
            }
        }
    }

    private var applicationRulesSection: some View {
        ClipAllSettingsSection(
            "应用规则",
            subtitle: "为常用 App 覆盖自动显示规则；快捷键和菜单主动取词不受影响。",
            helpText: "普通单击、空白、重复、失效或来源已切换的选区，密码框等安全区域，按钮、文件等非文字对象，以及无法安全恢复的剪贴板操作，始终不会显示浮窗。"
        ) {
            VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.sm) {
                if settings.selectionApplicationBundleIdentifiers.isEmpty {
                    ClipAllEmptyState(
                        title: "没有应用规则",
                        systemImage: "app.badge",
                        message: "新增 App 后，可单独决定自动显示与兼容取词策略。",
                        minimumHeight: 88
                    )
                } else {
                    VStack(spacing: ClipAllTheme.Spacing.xs) {
                        ForEach(settings.selectionApplicationBundleIdentifiers, id: \.self) {
                            bundleIdentifier in
                            applicationRow(bundleIdentifier)
                        }
                    }
                }

                Button(action: chooseApplication) {
                    Label("添加应用", systemImage: "plus")
                }
                .buttonStyle(ClipAllButtonStyle(variant: .secondary))
            }
        }
    }

    private var compatibilitySection: some View {
        ClipAllSettingsSection(
            "高级：兼容取词",
            subtitle: "文字目标无法读取时临时模拟复制，并安全收尾剪贴板。"
        ) {
            settingToggleRow(
                "启用复制回退",
                subtitle: "只接受非空文字；图片、文件等非文字结果会清理，不显示浮窗。",
                symbol: "doc.on.clipboard",
                isOn: $settings.isSelectionFallbackEnabled
            )
        }
    }

    private func settingToggleRow(
        _ title: String,
        subtitle: String,
        symbol: String,
        isOn: Binding<Bool>
    ) -> some View {
        ClipAllSettingsRow(
            title,
            subtitle: subtitle,
            symbolName: symbol
        ) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .fixedSize()
                .accessibilityLabel(title)
        }
    }

    private func applicationRow(_ bundleIdentifier: String) -> some View {
        let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        )
        let applicationName = applicationURL.map {
            FileManager.default.displayName(atPath: $0.path)
        } ?? bundleIdentifier

        return ClipAllSettingsRow(minimumHeight: 72) {
            HStack(spacing: ClipAllTheme.Spacing.sm) {
                Group {
                    if let applicationURL {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: applicationURL.path))
                            .resizable()
                            .scaledToFit()
                    } else {
                        ClipAllIconBadge(
                            symbolName: "app.fill",
                            size: ClipAllTheme.Size.iconSmall,
                            tone: .neutral
                        )
                    }
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.xxs) {
                    HStack(spacing: ClipAllTheme.Spacing.xs) {
                        Text(applicationName)
                            .font(ClipAllTheme.Typography.body.weight(.medium))
                            .foregroundStyle(ClipAllTheme.textPrimary)
                            .lineLimit(1)
                        ClipAllTag("应用规则", tone: .muted)
                    }
                    Text(bundleIdentifier)
                        .font(ClipAllTheme.Typography.supporting)
                        .foregroundStyle(ClipAllTheme.textSecondary)
                        .lineLimit(1)
                }
            }
        } trailing: {
            HStack(alignment: .center, spacing: ClipAllTheme.Spacing.sm) {
                VStack(alignment: .trailing, spacing: ClipAllTheme.Spacing.xxs) {
                    Text("自动显示")
                        .font(.caption)
                        .foregroundStyle(ClipAllTheme.textSecondary)
                    Picker(
                        "自动显示",
                        selection: automaticDisplayPolicyBinding(for: bundleIdentifier)
                    ) {
                        ForEach(SelectionAutomaticDisplayPolicy.allCases, id: \.self) { policy in
                            Text(policyTitle(policy)).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 142)
                    .accessibilityLabel("\(applicationName)自动显示策略")
                }

                VStack(alignment: .center, spacing: ClipAllTheme.Spacing.xxs) {
                    Text("兼容取词")
                        .font(.caption)
                        .foregroundStyle(ClipAllTheme.textSecondary)
                    Toggle(
                        "兼容取词",
                        isOn: selectionFallbackBinding(for: bundleIdentifier)
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .fixedSize()
                    .accessibilityLabel("\(applicationName)兼容取词")
                }

                Button(role: .destructive) {
                    settings.removeSelectionApplication(bundleIdentifier)
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("移除 \(applicationName) 的规则")
                .accessibilityLabel("移除 \(applicationName) 的规则")
            }
        }
    }

    private func automaticDisplayPolicyBinding(
        for bundleIdentifier: String
    ) -> Binding<SelectionAutomaticDisplayPolicy> {
        Binding(
            get: { settings.automaticDisplayPolicy(for: bundleIdentifier) },
            set: { settings.setAutomaticDisplayPolicy($0, for: bundleIdentifier) }
        )
    }

    private func selectionFallbackBinding(for bundleIdentifier: String) -> Binding<Bool> {
        Binding(
            get: {
                !settings.selectionFallbackExcludedBundleIdentifiers.contains(bundleIdentifier)
            },
            set: {
                settings.setSelectionFallbackExcluded(bundleIdentifier, isExcluded: !$0)
            }
        )
    }

    private func policyTitle(_ policy: SelectionAutomaticDisplayPolicy) -> String {
        switch policy {
        case .followGlobal: "跟随全局"
        case .dragOnly: "仅拖选"
        case .disabled: "永不自动显示"
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleIdentifier = Bundle(url: url)?.bundleIdentifier,
              bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        settings.addSelectionApplication(bundleIdentifier)
    }
}
