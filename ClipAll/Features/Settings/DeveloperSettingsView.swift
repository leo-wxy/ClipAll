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
            VStack(spacing: 12) {
                developerModePanel

                if settings.isDeveloperModeEnabled {
                    developmentPluginsPanel
                    if !lifecycle.invalidPlugins.isEmpty { diagnosticsPanel }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
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
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(ClipAllTheme.accent)
                .frame(width: 42, height: 42)
                .background(ClipAllTheme.accent.opacity(0.07), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("开发者模式")
                    .font(.headline)
                Text("直接引用源码目录进行重新载入和调试。关闭后引用会保留，但不会继续载入。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(
                "启用",
                isOn: Binding(
                    get: { settings.isDeveloperModeEnabled },
                    set: { lifecycle.setDeveloperModeEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .fixedSize()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipAllSurface()
    }

    private var developmentPluginsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("开发引用")
                        .font(.headline)
                    Text("移除引用不会删除插件源码。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                        developmentPluginRow(plugin)
                        if index < developmentPlugins.count - 1 { Divider() }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipAllSurface()
    }

    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("载入诊断", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(ClipAllTheme.accent)
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
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 5)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipAllSurface()
    }

    private var developmentPlugins: [ManagedPlugin] {
        lifecycle.plugins.filter {
            $0.package.definition.descriptor.source == .development
        }
    }

    private func developmentPluginRow(_ plugin: ManagedPlugin) -> some View {
        let descriptor = plugin.package.definition.descriptor
        return HStack(spacing: 12) {
            Image(systemName: descriptor.symbolName)
                .foregroundStyle(ClipAllTheme.accent)
                .frame(width: 34, height: 34)
                .background(ClipAllTheme.quietFill, in: Circle())
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
        .padding(.vertical, 10)
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
