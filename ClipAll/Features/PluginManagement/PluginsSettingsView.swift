import AppKit
import Combine
import SwiftUI

private enum PluginDetailSection: String, CaseIterable, Identifiable {
    case configuration = "配置"
    case capabilities = "能力"

    var id: String { rawValue }
}

@MainActor
private final class PluginsSettingsViewModel: ObservableObject {
    @Published var selectedPluginID: PluginID?
    @Published var preparedImport: PreparedPluginImport?
    @Published var uninstallTarget: ManagedPlugin?
    @Published var errorMessage: String?
    @Published var isInstalling = false
    @Published var selectedDetailSection: PluginDetailSection = .configuration
}

struct PluginsSettingsView: View {
    let environment: AppEnvironment

    @ObservedObject private var registry: CapabilityRegistry
    @ObservedObject private var lifecycle: PluginLifecycleController
    @StateObject private var model: PluginsSettingsViewModel

    init(environment: AppEnvironment) {
        self.environment = environment
        _registry = ObservedObject(wrappedValue: environment.registry)
        _lifecycle = ObservedObject(wrappedValue: environment.pluginLifecycle)
        _model = StateObject(wrappedValue: PluginsSettingsViewModel())
    }

    var body: some View {
        HStack(alignment: .top, spacing: ClipAllTheme.Spacing.md) {
            pluginListPanel
            if let descriptor = selectedDescriptor {
                PluginSettingsDetail(
                    descriptor: descriptor,
                    environment: environment,
                    section: $model.selectedDetailSection,
                    onError: { model.errorMessage = $0 },
                    onUninstall: {
                        model.uninstallTarget = lifecycle.plugin(id: descriptor.id)
                    }
                )
                .id(descriptor.id)
                .clipAllSurface()
            } else {
                ContentUnavailableView(
                    "选择一个插件",
                    systemImage: "puzzlepiece.extension",
                    description: Text("查看能力、配置和安装状态。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipAllSurface()
            }
        }
        .padding(.horizontal, ClipAllTheme.Spacing.xl)
        .padding(.top, ClipAllTheme.Spacing.lg)
        .padding(.bottom, ClipAllTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await environment.start()
            if model.selectedPluginID == nil { model.selectedPluginID = pluginDescriptors.first?.id }
        }
        .onChange(of: pluginDescriptors.map(\.id)) { _, identifiers in
            if let selectedPluginID = model.selectedPluginID,
               !identifiers.contains(selectedPluginID) {
                model.selectedPluginID = identifiers.first
            } else if model.selectedPluginID == nil {
                model.selectedPluginID = identifiers.first
            }
        }
        .sheet(item: $model.preparedImport) { prepared in
            PluginInstallationConfirmationView(
                prepared: prepared,
                isInstalling: model.isInstalling,
                onCancel: {
                    guard !model.isInstalling else { return }
                    Task { await environment.pluginLifecycle.discardImport(prepared) }
                    model.preparedImport = nil
                },
                onConfirm: {
                    guard !model.isInstalling else { return }
                    model.isInstalling = true
                    Task {
                        defer { model.isInstalling = false }
                        do {
                            try await environment.pluginLifecycle.install(
                                prepared,
                                replacingExisting: prepared.replacesExistingPlugin
                            )
                            model.selectedPluginID = prepared.package.definition.descriptor.id
                            model.preparedImport = nil
                        } catch {
                            await environment.pluginLifecycle.discardImport(prepared)
                            model.errorMessage = error.localizedDescription
                            model.preparedImport = nil
                        }
                    }
                }
            )
            .onDisappear {
                Task { await environment.pluginLifecycle.discardImport(prepared) }
            }
        }
        .sheet(item: $model.uninstallTarget) { plugin in
            PluginUninstallConfirmationView(
                plugin: plugin,
                onCancel: { model.uninstallTarget = nil },
                onConfirm: {
                    Task {
                        do {
                            try await environment.pluginLifecycle.uninstall(pluginID: plugin.id)
                            model.uninstallTarget = nil
                        } catch {
                            model.errorMessage = error.localizedDescription
                        }
                    }
                }
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

    private var pluginListPanel: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("能力来源")
                        .font(.headline)
                    Spacer()
                    Text("\(pluginDescriptors.count) 个")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text("选择一项查看和编辑配置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(ClipAllTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(pluginDescriptors) { descriptor in
                        Button {
                            model.selectedPluginID = descriptor.id
                        } label: {
                            PluginListRow(
                                descriptor: descriptor,
                                managed: lifecycle.plugin(id: descriptor.id),
                                isSelected: model.selectedPluginID == descriptor.id
                            )
                        }
                        .buttonStyle(
                            ClipAllSelectableRowStyle(
                                isSelected: model.selectedPluginID == descriptor.id
                            )
                        )
                        .accessibilityAddTraits(
                            model.selectedPluginID == descriptor.id ? .isSelected : []
                        )
                    }
                }
                .padding(ClipAllTheme.Spacing.sm)
            }

            if !lifecycle.invalidPlugins.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        "\(lifecycle.invalidPlugins.count) 个载入问题",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    if let invalid = lifecycle.invalidPlugins.first {
                        Text(invalid.issue.errorDescription ?? invalid.issue.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .help(invalid.issue.errorDescription ?? invalid.issue.message)
                    }
                }
                .padding(.horizontal, ClipAllTheme.Spacing.md)
                .padding(.vertical, ClipAllTheme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.055))
            }

            Divider()

            VStack(spacing: 8) {
                if lifecycle.plugin(id: .timestampTools) == nil {
                    Button {
                        importBundledTimestampTools()
                    } label: {
                        Label("安装时间工具示例", systemImage: "clock.arrow.2.circlepath")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ClipAllTheme.accent)
                    .disabled(model.isInstalling || environment.bundledTimestampToolsURL == nil)
                    .help(
                        environment.bundledTimestampToolsURL == nil
                            ? "当前构建未包含时间工具示例包"
                            : "通过普通插件安装流程检查并导入"
                    )
                }

                Button {
                    choosePlugin()
                } label: {
                    Label("导入插件", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(model.isInstalling)
            }
            .padding(ClipAllTheme.Spacing.sm)
        }
        .frame(width: ClipAllTheme.Size.pluginList)
        .frame(maxHeight: .infinity)
        .clipAllSurface()
    }

    private var pluginDescriptors: [PluginDescriptor] {
        var byID = Dictionary(uniqueKeysWithValues: registry.plugins.map { ($0.id, $0) })
        for plugin in lifecycle.plugins {
            byID[plugin.id] = plugin.package.definition.descriptor
        }
        return byID.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var selectedDescriptor: PluginDescriptor? {
        guard let selectedPluginID = model.selectedPluginID else { return nil }
        return pluginDescriptors.first(where: { $0.id == selectedPluginID })
    }

    private func choosePlugin() {
        let panel = NSOpenPanel()
        panel.title = "导入 ClipAll 插件"
        panel.prompt = "检查并导入"
        panel.allowedContentTypes = [.clipAllPlugin, .folder]
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await prepareImport(from: url)
            }
        }
    }

    private func importBundledTimestampTools() {
        guard let url = environment.bundledTimestampToolsURL else {
            model.errorMessage = "当前 App 构建未包含时间工具示例包"
            return
        }
        Task { @MainActor in
            await prepareImport(from: url)
        }
    }

    private func prepareImport(from url: URL) async {
        do {
            model.preparedImport = try await environment.pluginLifecycle.prepareImport(from: url)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

private struct PluginListRow: View {
    let descriptor: PluginDescriptor
    let managed: ManagedPlugin?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ClipAllIconBadge(
                symbolName: descriptor.symbolName,
                size: ClipAllTheme.Size.iconSmall,
                tone: isSelected ? .accent : .neutral
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.name)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? ClipAllTheme.accent : .primary)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(stateLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(stateColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(stateColor.opacity(0.09), in: Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var status: String {
        switch descriptor.source {
        case .builtIn, .development:
            "v\(descriptor.version)"
        case .installed:
            managed?.state == .disabled
                ? "v\(descriptor.version) · 已停用"
                : "v\(descriptor.version) · 已启用"
        }
    }

    private var stateLabel: String {
        switch descriptor.source {
        case .builtIn: "内置"
        case .development: "开发"
        case .installed: "本地"
        }
    }

    private var stateColor: Color {
        if managed?.state == .disabled { return .secondary }
        return isSelected ? ClipAllTheme.accent : .secondary
    }
}

private struct PluginSettingsDetail: View {
    let descriptor: PluginDescriptor
    let environment: AppEnvironment
    @ObservedObject private var lifecycle: PluginLifecycleController
    @ObservedObject private var registry: CapabilityRegistry
    @Binding private var section: PluginDetailSection
    let onError: (String) -> Void
    let onUninstall: () -> Void

    init(
        descriptor: PluginDescriptor,
        environment: AppEnvironment,
        section: Binding<PluginDetailSection>,
        onError: @escaping (String) -> Void,
        onUninstall: @escaping () -> Void
    ) {
        self.descriptor = descriptor
        self.environment = environment
        _lifecycle = ObservedObject(wrappedValue: environment.pluginLifecycle)
        _registry = ObservedObject(wrappedValue: environment.registry)
        _section = section
        self.onError = onError
        self.onUninstall = onUninstall
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HStack {
                Picker("插件详情", selection: $section) {
                    ForEach(PluginDetailSection.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 180)
                Spacer()
            }
            .padding(.horizontal, ClipAllTheme.Spacing.lg)
            .padding(.vertical, ClipAllTheme.Spacing.sm)

            Divider()

            switch section {
            case .configuration:
                configurationPane
            case .capabilities:
                capabilitiesPane
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ClipAllIconBadge(
                symbolName: descriptor.symbolName,
                size: ClipAllTheme.Size.iconLarge
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: ClipAllTheme.Spacing.xs) {
                    Text(sourceLabel)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(ClipAllTheme.quietFill, in: Capsule())
                    Text("v\(descriptor.version)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(descriptor.name)
                    .font(.title3.weight(.semibold))
                Text(descriptor.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(descriptor.id.rawValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: ClipAllTheme.Spacing.md)

            if descriptor.source == .installed, managed != nil {
                HStack(spacing: 9) {
                    Text("启用插件")
                        .font(.callout.weight(.medium))
                    Toggle(
                        "启用插件",
                        isOn: Binding(
                            get: { managed?.state == .enabled },
                            set: { value in setEnabled(value) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .clipAllInset(cornerRadius: ClipAllTheme.Radius.control)
                .fixedSize()
            }
        }
        .padding(ClipAllTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var configurationPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.lg) {
                if descriptor.configurationFields.isEmpty {
                    ContentUnavailableView(
                        "无需配置",
                        systemImage: "checkmark.circle",
                        description: Text("这个插件安装后即可使用。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("配置")
                            .font(.headline)
                        Text("修改后立即用于下一次能力执行。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    PluginConfigurationForm(
                        descriptor: descriptor,
                        configurationStore: environment.configuration,
                        secretStore: environment.secrets
                    )
                    .clipAllInset(cornerRadius: ClipAllTheme.Radius.surface)
                }

                if descriptor.source == .installed {
                    HStack {
                        Button("卸载插件…", role: .destructive, action: onUninstall)
                        Spacer()
                        Text("安装副本、配置和密钥会一并删除")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, ClipAllTheme.Spacing.xs)
                }
            }
            .padding(ClipAllTheme.Spacing.lg)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var capabilitiesPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("提供的能力")
                            .font(.headline)
                        Text("每个能力会独立参与固定、匹配和执行。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(capabilities.count) 个")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(ClipAllTheme.Spacing.md)

                Divider()

                ForEach(Array(capabilities.enumerated()), id: \.element.id) { index, capability in
                    HStack(alignment: .top, spacing: 12) {
                        ClipAllIconBadge(
                            symbolName: capability.symbolName,
                            size: ClipAllTheme.Size.iconSmall,
                            tone: .neutral
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(capability.name)
                                .fontWeight(.medium)
                            Text(capability.purpose)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, ClipAllTheme.Spacing.md)
                    .padding(.vertical, ClipAllTheme.Spacing.sm)
                    if index < capabilities.count - 1 { Divider() }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .clipAllInset(cornerRadius: ClipAllTheme.Radius.surface)
            .padding(ClipAllTheme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var capabilities: [CapabilityDescriptor] {
        if let managed {
            return managed.package.definition.capabilities.map(\.descriptor)
        }
        return registry.descriptors.filter { $0.pluginID == descriptor.id }
    }

    private var managed: ManagedPlugin? {
        lifecycle.plugin(id: descriptor.id)
    }

    private var sourceLabel: String {
        switch descriptor.source {
        case .builtIn: "内置"
        case .installed: "本地安装"
        case .development: "开发引用"
        }
    }

    private func setEnabled(_ value: Bool) {
        Task {
            do {
                try await environment.pluginLifecycle.setEnabled(value, pluginID: descriptor.id)
            } catch {
                onError(error.localizedDescription)
            }
        }
    }
}

private struct PluginInstallationConfirmationView: View {
    let prepared: PreparedPluginImport
    let isInstalling: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(
                prepared.replacesExistingPlugin ? "替换本地插件" : "导入本地插件",
                systemImage: "puzzlepiece.extension"
            )
            .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 7) {
                Text(prepared.package.definition.descriptor.name)
                    .font(.headline)
                Text(prepared.package.definition.descriptor.summary)
                    .foregroundStyle(.secondary)
                LabeledContent("版本", value: prepared.package.definition.descriptor.version)
                LabeledContent("来源", value: prepared.sourceDisplayName)
                LabeledContent("能力", value: "\(prepared.package.definition.capabilities.count) 个")
                if !prepared.package.definition.capabilities.isEmpty {
                    Text(prepared.package.definition.capabilities
                        .map { $0.descriptor.name }
                        .joined(separator: "、"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent(
                    "配置项",
                    value: prepared.package.definition.descriptor.configurationFields.isEmpty
                        ? "无"
                        : prepared.package.definition.descriptor.configurationFields
                            .map(\.title)
                            .joined(separator: "、")
                )
                LabeledContent("权限", value: "无文件、网络或系统权限")
            }

            Label(
                "这是未签名的本地插件。格式校验只确认包结构有效，不验证作者身份。",
                systemImage: "exclamationmark.shield"
            )
            .font(.callout)
            .foregroundStyle(.orange)

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isInstalling)
                Button(action: onConfirm) {
                    if isInstalling {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(prepared.replacesExistingPlugin ? "替换" : "导入")
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isInstalling)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

private struct PluginUninstallConfirmationView: View {
    let plugin: ManagedPlugin
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("卸载“\(plugin.package.definition.descriptor.name)”？")
                .font(.title2.weight(.semibold))
            Text("插件能力、配置和密钥会一并删除。最初导入的源包不会被修改。")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("卸载", role: .destructive, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 430)
    }
}
