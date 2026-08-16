import AppKit
import Combine
import SwiftUI

private struct PluginDebuggerPresentation: Identifiable {
    let id = UUID()
    let session: PluginDebugSession
}

@MainActor
private final class DeveloperSettingsViewModel: ObservableObject {
    @Published var debugger: PluginDebuggerPresentation?
    @Published var errorMessage: String?
}

struct DeveloperSettingsView: View {
    let environment: AppEnvironment

    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var lifecycle: PluginLifecycleController
    @StateObject private var model = DeveloperSettingsViewModel()

    init(environment: AppEnvironment) {
        self.environment = environment
        _settings = ObservedObject(wrappedValue: environment.settings)
        _lifecycle = ObservedObject(wrappedValue: environment.pluginLifecycle)
    }

    var body: some View {
        ClipAllSettingsPage(
            "开发者",
            subtitle: "加载本地插件源码，验证能力并查看载入诊断。"
        ) {
            developerModeSection
            developerWorkflowSection

            if settings.isDeveloperModeEnabled {
                developmentPluginsSection
                if !lifecycle.invalidPlugins.isEmpty { diagnosticsSection }
            }
        }
        .sheet(item: $model.debugger) { presentation in
            PluginDebuggerView(
                session: presentation.session,
                configurationStore: environment.configuration,
                secretStore: environment.secrets
            )
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
    }

    private var developerModeSection: some View {
        ClipAllSettingsSection(
            "开发者模式",
            subtitle: "直接引用源码目录；关闭后保留引用，但不继续载入。"
        ) {
            ClipAllSettingsRow(minimumHeight: 76) {
                HStack(spacing: ClipAllTheme.Spacing.sm) {
                    ClipAllIconBadge(
                        symbolName: "chevron.left.forwardslash.chevron.right",
                        size: ClipAllTheme.Size.iconMedium,
                        tone: settings.isDeveloperModeEnabled ? .accent : .neutral
                    )
                    VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.xxs) {
                        HStack(spacing: ClipAllTheme.Spacing.xs) {
                            Text("开发者模式")
                                .font(ClipAllTheme.Typography.body.weight(.medium))
                                .foregroundStyle(ClipAllTheme.textPrimary)
                            ClipAllTag(
                                settings.isDeveloperModeEnabled ? "已启用" : "未启用",
                                tone: settings.isDeveloperModeEnabled ? .accent : .muted,
                                systemImage: settings.isDeveloperModeEnabled
                                    ? "checkmark"
                                    : "minus"
                            )
                        }
                        Text(
                            settings.isDeveloperModeEnabled
                                ? "可直接引用本地源码，并在这里重新载入或调试。"
                                : "开启后才能载入和调试本地未打包插件。"
                        )
                        .font(ClipAllTheme.Typography.supporting)
                        .foregroundStyle(ClipAllTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } trailing: {
                Toggle(
                    "启用开发者模式",
                    isOn: Binding(
                        get: { settings.isDeveloperModeEnabled },
                        set: { lifecycle.setDeveloperModeEnabled($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .fixedSize()
                .accessibilityValue(settings.isDeveloperModeEnabled ? "已启用" : "未启用")
            }
        }
    }

    private var developerWorkflowSection: some View {
        ClipAllSettingsSection(
            "开发流程",
            subtitle: "启用后，按同一条本地链路载入、校验并调试插件。"
        ) {
            HStack(alignment: .top, spacing: ClipAllTheme.Spacing.xs) {
                workflowStep(
                    number: "1",
                    title: "载入源码",
                    detail: "选择本地 .clipallplugin 目录。",
                    symbolName: "folder.badge.plus"
                )
                workflowStep(
                    number: "2",
                    title: "验证能力",
                    detail: "校验插件清单与能力声明。",
                    symbolName: "checkmark.shield"
                )
                workflowStep(
                    number: "3",
                    title: "运行调试",
                    detail: "用真实输入检查输出与日志。",
                    symbolName: "hammer"
                )
            }
        }
    }

    private func workflowStep(
        number: String,
        title: String,
        detail: String,
        symbolName: String
    ) -> some View {
        VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.xs) {
            HStack {
                ClipAllIconBadge(
                    symbolName: symbolName,
                    size: ClipAllTheme.Size.iconSmall,
                    tone: .accent
                )
                Spacer()
                ClipAllTag(number, tone: .accent)
            }
            Text(title)
                .font(ClipAllTheme.Typography.body.weight(.semibold))
                .foregroundStyle(ClipAllTheme.textPrimary)
            Text(detail)
                .font(ClipAllTheme.Typography.supporting)
                .foregroundStyle(ClipAllTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ClipAllTheme.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(
            ClipAllTheme.quietFill,
            in: RoundedRectangle(cornerRadius: ClipAllTheme.Radius.row, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ClipAllTheme.Radius.row, style: .continuous)
                .stroke(ClipAllTheme.border.opacity(0.62), lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(number) 步，\(title)，\(detail)")
    }

    private var developmentPluginsSection: some View {
        ClipAllSettingsSection(
            "开发引用",
            subtitle: "移除引用不会删除插件源码。"
        ) {
            Button {
                chooseDevelopmentPlugin()
            } label: {
                Label("载入未打包插件…", systemImage: "folder.badge.plus")
            }
            .buttonStyle(ClipAllButtonStyle(variant: .primary))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityHint("选择一个 .clipallplugin 目录或文件夹")

            if developmentPlugins.isEmpty {
                ClipAllEmptyState(
                    title: "还没有开发引用",
                    systemImage: "hammer",
                    message: "载入一个 .clipallplugin 目录开始调试。",
                    minimumHeight: 88
                )
            } else {
                VStack(spacing: ClipAllTheme.Spacing.xs) {
                    ForEach(developmentPlugins) { plugin in
                        ClipAllHoverRow { developmentPluginRow(plugin) }
                    }
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        ClipAllSettingsSection(
            "载入诊断",
            subtitle: "以下插件未能通过校验或载入。"
        ) {
            VStack(spacing: ClipAllTheme.Spacing.xs) {
                ForEach(lifecycle.invalidPlugins) { invalid in
                    ClipAllSettingsRow(minimumHeight: 72) {
                        HStack(alignment: .top, spacing: ClipAllTheme.Spacing.sm) {
                            ClipAllIconBadge(
                                symbolName: "exclamationmark.triangle.fill",
                                size: ClipAllTheme.Size.iconSmall,
                                tone: .warning
                            )
                            VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.xxs) {
                                Text(invalid.packageURL.lastPathComponent)
                                    .font(ClipAllTheme.Typography.body.weight(.medium))
                                    .foregroundStyle(ClipAllTheme.textPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(invalid.packageURL.path)
                                Text("\(invalid.issue.code)：\(invalid.issue.message)")
                                    .font(ClipAllTheme.Typography.supporting)
                                    .foregroundStyle(ClipAllTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                                if let location = invalid.issue.location, !location.isEmpty {
                                    Text(location)
                                        .font(ClipAllTheme.Typography.monospacedSupporting)
                                        .foregroundStyle(ClipAllTheme.textSecondary)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    } trailing: {
                        ClipAllTag("载入失败", tone: .warning, systemImage: "exclamationmark.triangle")
                    }
                }
            }
        }
    }

    private var developmentPlugins: [ManagedPlugin] {
        lifecycle.plugins.filter {
            $0.package.definition.descriptor.source == .development
        }
    }

    private func developmentPluginRow(_ plugin: ManagedPlugin) -> some View {
        let descriptor = plugin.package.definition.descriptor
        return HStack(alignment: .top, spacing: ClipAllTheme.Spacing.md) {
            HStack(alignment: .top, spacing: ClipAllTheme.Spacing.sm) {
                ClipAllIconBadge(
                    symbolName: descriptor.symbolName,
                    size: ClipAllTheme.Size.iconSmall,
                    tone: .accent
                )
                VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.xxs) {
                    Text(descriptor.name)
                        .font(ClipAllTheme.Typography.body.weight(.medium))
                        .foregroundStyle(ClipAllTheme.textPrimary)
                    Text(plugin.package.packageURL.path)
                        .font(ClipAllTheme.Typography.monospacedSupporting)
                        .foregroundStyle(ClipAllTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(plugin.package.packageURL.path)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: ClipAllTheme.Spacing.xs) {
                Button("重新载入") { reload(plugin.id) }
                    .buttonStyle(ClipAllButtonStyle(variant: .secondary))
                    .accessibilityHint("重新校验并载入此开发插件")
                Button("调试") { openDebugger(plugin.id) }
                    .buttonStyle(ClipAllButtonStyle(variant: .primary))
                    .accessibilityHint("打开此插件的调试器")
                Button(role: .destructive) {
                    removeReference(plugin.id)
                } label: {
                    Text("移除引用")
                        .foregroundStyle(ClipAllTheme.error)
                }
                .buttonStyle(ClipAllButtonStyle(variant: .secondary))
                .accessibilityHint("只移除引用，不删除插件源码")
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func chooseDevelopmentPlugin() {
        let panel = NSOpenPanel()
        panel.title = "载入未打包插件"
        panel.prompt = "载入"
        panel.allowedContentTypes = [.clipAllPlugin, .folder]
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    try lifecycle.loadDevelopment(from: url)
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func reload(_ pluginID: PluginID) {
        do {
            try lifecycle.reloadDevelopment(pluginID: pluginID)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func openDebugger(_ pluginID: PluginID) {
        do {
            model.debugger = PluginDebuggerPresentation(
                session: try lifecycle.makeDebugSession(pluginID: pluginID)
            )
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func removeReference(_ pluginID: PluginID) {
        do {
            try lifecycle.removeDevelopmentReference(pluginID: pluginID)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}
