import AppKit
import Combine
import SwiftUI

@MainActor
private final class CapabilityCenterViewModel: ObservableObject {
    @Published var query = ""
    @Published var selectedCapabilityID: CapabilityID?
}

struct CapabilityCenterView: View {
    let environment: AppEnvironment

    @ObservedObject private var registry: CapabilityRegistry
    @ObservedObject private var settings: SettingsStore
    @StateObject private var model = CapabilityCenterViewModel()
    @Environment(\.openWindow) private var openWindow

    init(environment: AppEnvironment) {
        self.environment = environment
        _registry = ObservedObject(wrappedValue: environment.registry)
        _settings = ObservedObject(wrappedValue: environment.settings)
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索能力或插件", text: $model.query)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 9)
                .frame(height: 30)
                .clipAllInset(cornerRadius: ClipAllTheme.Radius.control)
                .padding(ClipAllTheme.Spacing.sm)

                Divider()

                List(selection: $model.selectedCapabilityID) {
                    Section("\(filteredDescriptors.count) 个能力") {
                        ForEach(filteredDescriptors) { descriptor in
                            capabilityRow(descriptor)
                                .tag(descriptor.id)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationTitle("能力")
            .navigationSplitViewColumnWidth(
                min: 220,
                ideal: ClipAllTheme.Size.capabilityList,
                max: 280
            )
        } detail: {
            Group {
                if let descriptor = selectedDescriptor {
                    capabilityDetail(descriptor)
                } else if model.query.isEmpty {
                    ContentUnavailableView(
                        "选择一个能力",
                        systemImage: "sparkles",
                        description: Text("查看用途、示例和来源插件。")
                    )
                } else {
                    ContentUnavailableView(
                        "没有匹配的能力",
                        systemImage: "magnifyingglass",
                        description: Text("尝试搜索能力名称、用途或插件名称。")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ClipAllTheme.canvas)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 500)
        .tint(ClipAllTheme.accent)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    bringSettingsToFront()
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
            }
        }
        .task {
            await environment.start()
            reconcileSelection()
        }
        .onChange(of: filteredDescriptors.map(\.id)) { _, _ in
            reconcileSelection()
        }
    }

    private func capabilityRow(_ descriptor: CapabilityDescriptor) -> some View {
        HStack(spacing: 9) {
            ClipAllIconBadge(
                symbolName: descriptor.symbolName,
                size: ClipAllTheme.Size.iconSmall,
                tone: model.selectedCapabilityID == descriptor.id ? .accent : .neutral
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(descriptor.name)
                    .fontWeight(.medium)
                Text(pluginName(for: descriptor))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if settings.pinnedCapabilityIDs.contains(descriptor.id) {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(ClipAllTheme.accent)
                    .accessibilityLabel("已固定")
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private func capabilityDetail(_ descriptor: CapabilityDescriptor) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.lg) {
                HStack(alignment: .top, spacing: ClipAllTheme.Spacing.sm) {
                    ClipAllIconBadge(
                        symbolName: descriptor.symbolName,
                        size: ClipAllTheme.Size.iconLarge
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(descriptor.name)
                            .font(.title2.weight(.semibold))
                        Text(descriptor.purpose)
                            .foregroundStyle(.secondary)
                        Text(pluginName(for: descriptor))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("固定到操作栏", isOn: pinBinding(descriptor.id))
                        .toggleStyle(.switch)
                        .fixedSize()
                        .disabled(
                            !settings.pinnedCapabilityIDs.contains(descriptor.id)
                                && settings.pinnedCapabilityIDs.count
                                    >= SettingsStore.maximumPinnedCapabilities
                        )
                }

                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    Text("适用内容")
                        .font(.headline)
                    Text(descriptor.supportedContentKinds.map(contentKindName).sorted().joined(separator: "、"))
                        .foregroundStyle(.secondary)
                }

                if !descriptor.examples.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("示例")
                            .font(.headline)
                        ForEach(descriptor.examples, id: \.self) { example in
                            Text(example)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .clipAllInset()
                        }
                    }
                }

                if let plugin = registry.plugin(for: descriptor.pluginID),
                   !plugin.configurationFields.isEmpty {
                    Divider()
                    Button {
                        bringSettingsToFront()
                    } label: {
                        Label("在设置中配置“\(plugin.name)”", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .padding(ClipAllTheme.Spacing.xl)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("能力中心")
    }

    private var filteredDescriptors: [CapabilityDescriptor] {
        let query = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return registry.descriptors }
        return registry.descriptors.filter { descriptor in
            descriptor.name.localizedCaseInsensitiveContains(query)
                || descriptor.purpose.localizedCaseInsensitiveContains(query)
                || pluginName(for: descriptor).localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedDescriptor: CapabilityDescriptor? {
        guard let id = model.selectedCapabilityID else { return nil }
        return registry.descriptor(for: id)
    }

    private func reconcileSelection() {
        if let selected = model.selectedCapabilityID,
           filteredDescriptors.contains(where: { $0.id == selected }) {
            return
        }
        model.selectedCapabilityID = filteredDescriptors.first?.id
    }

    private func pinBinding(_ id: CapabilityID) -> Binding<Bool> {
        Binding(
            get: { settings.pinnedCapabilityIDs.contains(id) },
            set: { _ = settings.setPinned(id, isPinned: $0) }
        )
    }

    private func bringSettingsToFront() {
        openWindow(id: "settings")
        NSApplication.shared.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func pluginName(for descriptor: CapabilityDescriptor) -> String {
        registry.plugin(for: descriptor.pluginID)?.name ?? descriptor.pluginID.rawValue
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
}
