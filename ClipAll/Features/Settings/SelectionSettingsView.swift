import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SelectionSettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: ClipAllTheme.Spacing.sm) {
                automaticDisplayCard
                applicationRulesCard
                fixedFiltersCard
                compatibilityCard
            }
            .frame(maxWidth: 760)
            .padding(ClipAllTheme.Spacing.lg)
            .frame(maxWidth: .infinity)
        }
    }

    private var automaticDisplayCard: some View {
        ClipAllSectionCard(
            "自动显示",
            subtitle: "控制哪些文字选择操作会自动显示浮窗。"
        ) {
            VStack(spacing: ClipAllTheme.Spacing.sm) {
                settingRow("自动监听文字选择", symbol: "selection.pin.in.out") {
                    Toggle("", isOn: $settings.isMonitoringEnabled)
                }
                Divider()
                settingRow("拖选或 Shift 扩选后显示", symbol: "text.cursor") {
                    Toggle("", isOn: $settings.isDragSelectionEnabled)
                }
                Divider()
                settingRow("双击或多击文字后显示", symbol: "cursorarrow.click.2") {
                    Toggle("", isOn: $settings.isMultiClickSelectionEnabled)
                }
            }
        }
    }

    private var applicationRulesCard: some View {
        ClipAllSectionCard(
            "应用规则",
            subtitle: "为常用 App 覆盖自动显示规则；快捷键和菜单主动取词不受影响。"
        ) {
            VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.sm) {
                if settings.selectionApplicationBundleIdentifiers.isEmpty {
                    ContentUnavailableView(
                        "没有应用规则",
                        systemImage: "app.badge",
                        description: Text("新增 App 后默认跟随全局设置。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    ForEach(settings.selectionApplicationBundleIdentifiers, id: \.self) {
                        bundleIdentifier in
                        applicationRow(bundleIdentifier)
                        if bundleIdentifier != settings.selectionApplicationBundleIdentifiers.last {
                            Divider()
                        }
                    }
                }

                Button("添加应用…", action: chooseApplication)
            }
        }
    }

    private var fixedFiltersCard: some View {
        ClipAllSectionCard(
            "始终不显示",
            subtitle: "以下安全过滤固定生效，避免旧选区或非文字对象误触。"
        ) {
            VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.xs) {
                fixedFilter("普通单击或未形成有效选择意图")
                fixedFilter("空白、重复、失效选区或来源 App 已切换")
                fixedFilter("密码框和其他安全输入区域")
                fixedFilter("按钮、标签页、菜单、文件、文件夹和图片")
                fixedFilter("剪贴板超时、取消、竞争写入或无法安全恢复")
            }
        }
    }

    private var compatibilityCard: some View {
        ClipAllSectionCard(
            "高级：兼容取词",
            subtitle: "辅助功能无法读取时，临时模拟复制并在内存中恢复原剪贴板。"
        ) {
            settingRow("启用复制回退", symbol: "doc.on.clipboard") {
                Toggle("", isOn: $settings.isSelectionFallbackEnabled)
            }
        }
    }

    private func settingRow<Control: View>(
        _ title: String,
        symbol: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: ClipAllTheme.Spacing.md) {
            Label(title, systemImage: symbol)
                .fontWeight(.medium)
            Spacer()
            control()
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

        return HStack(spacing: ClipAllTheme.Spacing.sm) {
            Group {
                if let applicationURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: applicationURL.path))
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "app")
                        .font(.system(size: 20))
                }
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(applicationName)
                    .fontWeight(.medium)
                Text(bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: ClipAllTheme.Spacing.sm)

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
            .frame(width: 126)

            Toggle(
                "兼容取词",
                isOn: selectionFallbackBinding(for: bundleIdentifier)
            )
            .toggleStyle(.switch)
            .fixedSize()

            Button("移除", role: .destructive) {
                settings.removeSelectionApplication(bundleIdentifier)
            }
        }
    }

    private func fixedFilter(_ title: String) -> some View {
        Label(title, systemImage: "checkmark.shield")
            .foregroundStyle(.secondary)
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
