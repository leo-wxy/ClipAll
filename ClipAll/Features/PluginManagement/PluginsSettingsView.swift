import AppKit
import Combine
import SwiftUI

private enum PluginDetailSection: String, CaseIterable, Identifiable {
    case configuration = "配置"
    case capabilities = "能力"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .configuration: "slider.horizontal.3"
        case .capabilities: "sparkles"
        }
    }
}

@MainActor
private final class PluginsSettingsViewModel: ObservableObject {
    @Published var query = ""
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
        VStack(spacing: 0) {
            ClipAllPageHeader(
                title: "插件",
                subtitle: "能力属于插件；在这里查看、配置并固定到取词操作栏。"
            )
            .padding(.horizontal, ClipAllTheme.Spacing.xl)
            .padding(.top, ClipAllTheme.Spacing.xl)
            .padding(.bottom, ClipAllTheme.Spacing.lg)

            Rectangle()
                .fill(ClipAllTheme.separator)
                .frame(height: 1)

            HStack(alignment: .top, spacing: 0) {
                pluginListPanel
                Rectangle()
                    .fill(ClipAllTheme.separator)
                    .frame(width: 1)
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
                    .background(ClipAllTheme.contentSurface)
                } else {
                    VStack {
                        Spacer()
                        ClipAllEmptyState(
                            title: model.query.isEmpty ? "选择一个插件" : "没有匹配的插件",
                            systemImage: model.query.isEmpty
                                ? "puzzlepiece.extension"
                                : "magnifyingglass",
                            message: model.query.isEmpty
                                ? "查看能力、配置和安装状态。"
                                : "尝试搜索插件名称、摘要或能力。",
                            minimumHeight: 116
                        )
                        .frame(maxWidth: 520)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ClipAllTheme.contentSurface)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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

            HStack(spacing: ClipAllTheme.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ClipAllTheme.textSecondary)
                TextField("搜索插件或能力", text: $model.query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .clipAllInset(cornerRadius: ClipAllTheme.Radius.control)
            .padding(.horizontal, ClipAllTheme.Spacing.sm)
            .padding(.bottom, ClipAllTheme.Spacing.sm)

            Divider()

            ScrollView {
                Group {
                    if pluginDescriptors.isEmpty {
                        ClipAllEmptyState(
                            title: "没有匹配的插件",
                            systemImage: "magnifyingglass",
                            message: "能力仍会在所属插件中展示。",
                            minimumHeight: 132
                        )
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        LazyVStack(spacing: ClipAllTheme.Spacing.xxs) {
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
                    .foregroundStyle(ClipAllTheme.warning)
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
                .background(ClipAllTheme.warning.opacity(0.055))
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
                    .buttonStyle(ClipAllButtonStyle(variant: .secondary))
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
                .buttonStyle(ClipAllButtonStyle(variant: .primary))
                .disabled(model.isInstalling)
            }
            .padding(ClipAllTheme.Spacing.sm)
        }
        .frame(width: ClipAllTheme.Size.pluginList)
        .frame(maxHeight: .infinity)
        .background(ClipAllTheme.elevatedSurface)
    }

    private var allPluginDescriptors: [PluginDescriptor] {
        var byID = Dictionary(uniqueKeysWithValues: registry.plugins.map { ($0.id, $0) })
        for plugin in lifecycle.plugins {
            byID[plugin.id] = plugin.package.definition.descriptor
        }
        return byID.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var pluginDescriptors: [PluginDescriptor] {
        let query = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allPluginDescriptors }
        return allPluginDescriptors.filter { descriptor in
            descriptor.name.localizedCaseInsensitiveContains(query)
                || descriptor.summary.localizedCaseInsensitiveContains(query)
                || capabilityDescriptors(
                    for: descriptor,
                    registry: registry,
                    lifecycle: lifecycle
                ).contains { capability in
                    capability.name.localizedCaseInsensitiveContains(query)
                        || capability.purpose.localizedCaseInsensitiveContains(query)
                        || capability.supportedContentKinds.contains {
                            contentKindName($0).localizedCaseInsensitiveContains(query)
                        }
                        || capability.examples.contains {
                            $0.localizedCaseInsensitiveContains(query)
                        }
                }
        }
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
        HStack(alignment: .center, spacing: ClipAllTheme.Spacing.sm) {
            ClipAllIconBadge(
                symbolName: descriptor.symbolName,
                size: ClipAllTheme.Size.iconSmall,
                tone: isSelected ? .accent : .neutral
            )
            VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.xxs) {
                Text(descriptor.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isSelected ? ClipAllTheme.accent : .primary)
                Text("v\(descriptor.version) · \(sourceLabel)")
                    .font(ClipAllTheme.Typography.supporting)
                    .foregroundStyle(ClipAllTheme.textSecondary)
            }
            Spacer()
            ClipAllTag(
                stateLabel,
                tone: stateTone,
                systemImage: stateSymbolName
            )
        }
        .padding(.horizontal, ClipAllTheme.Spacing.sm)
        .padding(.vertical, ClipAllTheme.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(descriptor.name)，\(sourceLabel)，\(status)，版本 \(descriptor.version)")
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

    private var sourceLabel: String {
        switch descriptor.source {
        case .builtIn: "内置"
        case .development: "开发"
        case .installed: "本地"
        }
    }

    private var stateLabel: String {
        guard descriptor.source == .installed else { return "可用" }
        return managed?.state == .disabled ? "已停用" : "已启用"
    }

    private var stateTone: ClipAllTag.Tone {
        managed?.state == .disabled ? .warning : .success
    }

    private var stateSymbolName: String {
        managed?.state == .disabled ? "pause.fill" : "checkmark"
    }
}

private struct PluginSettingsDetail: View {
    let descriptor: PluginDescriptor
    let environment: AppEnvironment
    @ObservedObject private var lifecycle: PluginLifecycleController
    @ObservedObject private var registry: CapabilityRegistry
    @ObservedObject private var settings: SettingsStore
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
        _settings = ObservedObject(wrappedValue: environment.settings)
        _section = section
        self.onError = onError
        self.onUninstall = onUninstall
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            detailTabs

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
        HStack(alignment: .top, spacing: ClipAllTheme.Spacing.md) {
            ClipAllIconBadge(
                symbolName: descriptor.symbolName,
                size: ClipAllTheme.Size.iconLarge
            )
            VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.xs) {
                HStack(spacing: ClipAllTheme.Spacing.xxs) {
                    ClipAllTag(sourceLabel, tone: .accent, systemImage: sourceSymbolName)
                    ClipAllTag("v\(descriptor.version)", tone: .muted)
                    if descriptor.source == .installed, let managed {
                        ClipAllTag(
                            managed.state == .disabled ? "已停用" : "已启用",
                            tone: managed.state == .disabled ? .warning : .success,
                            systemImage: managed.state == .disabled ? "pause.fill" : "checkmark"
                        )
                    }
                }
                Text(descriptor.name)
                    .font(ClipAllTheme.Typography.pageTitle)
                    .foregroundStyle(ClipAllTheme.textPrimary)
                Text(descriptor.summary)
                    .font(.callout)
                    .foregroundStyle(ClipAllTheme.textSecondary)
                    .lineLimit(2)
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

    private var detailTabs: some View {
        HStack(spacing: ClipAllTheme.Spacing.xxs) {
            ForEach(PluginDetailSection.allCases) { item in
                Button {
                    section = item
                } label: {
                    Label(item.rawValue, systemImage: item.symbolName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(
                            section == item
                                ? ClipAllTheme.accent
                                : ClipAllTheme.textSecondary
                        )
                        .padding(.horizontal, ClipAllTheme.Spacing.sm)
                        .padding(.vertical, ClipAllTheme.Spacing.xs)
                        .background(
                            section == item ? ClipAllTheme.selectionFill : .clear,
                            in: RoundedRectangle(
                                cornerRadius: ClipAllTheme.Radius.control,
                                style: .continuous
                            )
                        )
                        .overlay(alignment: .bottom) {
                            if section == item {
                                Capsule()
                                    .fill(ClipAllTheme.accent)
                                    .frame(height: 2)
                                    .padding(.horizontal, ClipAllTheme.Spacing.xs)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(section == item ? .isSelected : [])
                .accessibilityLabel("插件详情：\(item.rawValue)")
            }
            Spacer()
        }
        .padding(.horizontal, ClipAllTheme.Spacing.lg)
        .padding(.vertical, ClipAllTheme.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var configurationPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.lg) {
                if descriptor.configurationFields.isEmpty {
                    ClipAllEmptyState(
                        title: "无需配置",
                        systemImage: "checkmark.circle",
                        message: "这个插件安装后即可使用。",
                        minimumHeight: 104
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    ClipAllSettingsSection(
                        "运行配置",
                        subtitle: "修改后立即用于下一次能力执行。"
                    ) {
                        PluginConfigurationForm(
                            descriptor: descriptor,
                            configurationStore: environment.configuration,
                            secretStore: environment.secrets
                        )
                    }
                }

                if descriptor.source == .installed {
                    ClipAllSettingsSection(
                        "插件管理",
                        subtitle: "安装副本、配置和密钥会一并删除。"
                    ) {
                        HStack {
                            Button("卸载插件…", role: .destructive, action: onUninstall)
                                .buttonStyle(.bordered)
                            Spacer()
                        }
                    }
                }
            }
            .padding(.horizontal, ClipAllTheme.Spacing.lg)
            .padding(.bottom, ClipAllTheme.Spacing.lg)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var capabilitiesPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ClipAllSettingsSection(
                    "提供的能力",
                    subtitle: "每个能力会独立参与匹配和执行；固定后会出现在取词操作栏。"
                ) {
                    HStack {
                        ClipAllTag(
                            "\(capabilities.count) 个能力",
                            tone: .muted,
                            systemImage: "sparkles"
                        )
                        Spacer()
                    }

                    if capabilities.isEmpty {
                        ClipAllEmptyState(
                            title: "暂无可用能力",
                            systemImage: "sparkles",
                            message: "这个插件目前没有声明可执行能力。",
                            minimumHeight: 104
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(capabilities.enumerated()), id: \.element.id) { index, capability in
                                capabilityRow(capability)
                                if index < capabilities.count - 1 { Divider() }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, ClipAllTheme.Spacing.lg)
            .padding(.bottom, ClipAllTheme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var capabilities: [CapabilityDescriptor] {
        capabilityDescriptors(for: descriptor, registry: registry, lifecycle: lifecycle)
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

    private var sourceSymbolName: String {
        switch descriptor.source {
        case .builtIn: "shippingbox.fill"
        case .installed: "arrow.down.app.fill"
        case .development: "hammer.fill"
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

    private func capabilityRow(_ capability: CapabilityDescriptor) -> some View {
        HStack(alignment: .top, spacing: ClipAllTheme.Spacing.sm) {
            ClipAllIconBadge(
                symbolName: capability.symbolName,
                size: ClipAllTheme.Size.iconSmall,
                tone: isPinned(capability.id) ? .accent : .neutral
            )

            VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.xs) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(capability.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ClipAllTheme.textPrimary)
                    Text(capability.purpose)
                        .font(.caption)
                        .foregroundStyle(ClipAllTheme.textSecondary)
                }

                if !capability.supportedContentKinds.isEmpty {
                    HStack(spacing: ClipAllTheme.Spacing.xxs) {
                        ForEach(
                            capability.supportedContentKinds.sorted {
                                contentKindName($0) < contentKindName($1)
                            },
                            id: \.self
                        ) { kind in
                            ClipAllTag(
                                contentKindName(kind),
                                tone: .muted,
                                systemImage: "text.badge.checkmark"
                            )
                        }
                    }
                }

                ForEach(capability.examples, id: \.self) { example in
                    ClipAllExampleBlock(text: example)
                }
            }

            Spacer(minLength: ClipAllTheme.Spacing.md)

            Button {
                _ = settings.setPinned(capability.id, isPinned: !isPinned(capability.id))
            } label: {
                Label(
                    isPinned(capability.id) ? "已固定" : "固定到操作栏",
                    systemImage: isPinned(capability.id) ? "pin.fill" : "pin"
                )
            }
            .buttonStyle(
                ClipAllButtonStyle(
                    variant: isPinned(capability.id) ? .secondary : .primary
                )
            )
            .disabled(isPinDisabled(capability.id))
            .help(pinHelp(capability.id))
            .accessibilityLabel(
                isPinned(capability.id)
                    ? "取消固定“\(capability.name)”"
                    : "固定“\(capability.name)”到操作栏"
            )
        }
        .padding(.horizontal, ClipAllTheme.Spacing.md)
        .padding(.vertical, ClipAllTheme.Spacing.sm)
    }

    private func isPinned(_ capabilityID: CapabilityID) -> Bool {
        settings.pinnedCapabilityIDs.contains(capabilityID)
    }

    private func isPinDisabled(_ capabilityID: CapabilityID) -> Bool {
        guard !isPinned(capabilityID) else { return false }
        if managed?.state == .disabled { return true }
        return settings.pinnedCapabilityIDs.count >= SettingsStore.maximumPinnedCapabilities
    }

    private func pinHelp(_ capabilityID: CapabilityID) -> String {
        if isPinned(capabilityID) { return "从操作栏取消固定" }
        if managed?.state == .disabled { return "启用插件后才能固定能力" }
        if settings.pinnedCapabilityIDs.count >= SettingsStore.maximumPinnedCapabilities {
            return "操作栏最多固定 \(SettingsStore.maximumPinnedCapabilities) 个能力"
        }
        return "固定到取词操作栏"
    }
}

@MainActor
private func capabilityDescriptors(
    for descriptor: PluginDescriptor,
    registry: CapabilityRegistry,
    lifecycle: PluginLifecycleController
) -> [CapabilityDescriptor] {
    if let managed = lifecycle.plugin(id: descriptor.id) {
        return managed.package.definition.capabilities.map(\.descriptor)
    }
    return registry.descriptors.filter { $0.pluginID == descriptor.id }
}

private func contentKindName(_ kind: ContentKind) -> String {
    switch kind {
    case .text: "文本"
    case .foreignLanguage: "外语文本"
    case .url: "网址"
    case .email: "邮箱"
    case .code: "代码"
    case .address: "地址"
    case .unixTimestampSeconds: "秒级时间戳"
    case .unixTimestampMilliseconds: "毫秒级时间戳"
    case .dateTime: "日期时间"
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
            .foregroundStyle(ClipAllTheme.warning)

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
