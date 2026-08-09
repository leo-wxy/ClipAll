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
        ScrollView {
            VStack(spacing: ClipAllTheme.Spacing.sm) {
                developerModePanel

                if settings.isDeveloperModeEnabled {
                    developmentPluginsPanel
                    if !lifecycle.invalidPlugins.isEmpty { diagnosticsPanel }
                }
            }
            .frame(maxWidth: 720)
            .padding(ClipAllTheme.Spacing.lg)
            .frame(maxWidth: .infinity)
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

    private var developerModePanel: some View {
        ClipAllSectionCard(
            "开发者模式",
            subtitle: "直接引用源码目录；关闭后保留引用，但不继续载入。"
        ) {
            HStack(spacing: ClipAllTheme.Spacing.sm) {
                ClipAllIconBadge(
                    symbolName: "chevron.left.forwardslash.chevron.right",
                    size: ClipAllTheme.Size.iconMedium
                )
                Text(settings.isDeveloperModeEnabled ? "已启用" : "未启用")
                    .fontWeight(.medium)
                Spacer()
                Toggle(
                    "启用",
                    isOn: Binding(
                        get: { settings.isDeveloperModeEnabled },
                        set: { lifecycle.setDeveloperModeEnabled($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .fixedSize()
            }
        }
    }

    private var developmentPluginsPanel: some View {
        ClipAllSectionCard(
            "开发引用",
            subtitle: "移除引用不会删除插件源码。"
        ) {
            HStack {
                Spacer()
                Button("载入未打包插件…") { chooseDevelopmentPlugin() }
            }

            if developmentPlugins.isEmpty {
                ContentUnavailableView(
                    "还没有开发引用",
                    systemImage: "hammer",
                    description: Text("载入一个 .clipallplugin 目录开始调试。")
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(developmentPlugins.enumerated()), id: \.element.id) { index, plugin in
                        ClipAllHoverRow { developmentPluginRow(plugin) }
                        if index < developmentPlugins.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    private var diagnosticsPanel: some View {
        ClipAllSectionCard(
            "载入诊断",
            subtitle: "以下插件未能通过校验或载入。"
        ) {
            ForEach(lifecycle.invalidPlugins) { invalid in
                VStack(alignment: .leading, spacing: 3) {
                    Text(invalid.packageURL.lastPathComponent)
                        .fontWeight(.medium)
                    Text("\(invalid.issue.code)：\(invalid.issue.message)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let location = invalid.issue.location, !location.isEmpty {
                        Text(location)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 5)
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
        return HStack(spacing: 12) {
            ClipAllIconBadge(
                symbolName: descriptor.symbolName,
                size: ClipAllTheme.Size.iconSmall
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.name)
                    .fontWeight(.medium)
                Text(plugin.package.packageURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(plugin.package.packageURL.path)
            }
            Spacer()
            Button("重新载入") { reload(plugin.id) }
            Button("调试") { openDebugger(plugin.id) }
                .buttonStyle(.borderedProminent)
            Button("移除引用", role: .destructive) { removeReference(plugin.id) }
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
