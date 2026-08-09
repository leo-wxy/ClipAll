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

    init(environment: AppEnvironment) {
        self.environment = environment
        _registry = ObservedObject(wrappedValue: environment.registry)
        _settings = ObservedObject(wrappedValue: environment.settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("能力中心")
                        .font(.system(size: 24, weight: .bold))
                    Text("浏览所有可用操作，并决定哪些显示在取词面板。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                SettingsLink {
                    Label("打开设置", systemImage: "gearshape")
                }
            }

            HStack(spacing: 12) {
                capabilityList
                    .frame(width: 300)
                    .clipAllSurface()

                if let descriptor = selectedDescriptor {
                    capabilityDetail(descriptor)
                        .clipAllSurface()
                } else {
                    ContentUnavailableView(
                        "选择一个能力",
                        systemImage: "sparkles",
                        description: Text("查看用途、示例和来源插件。")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipAllSurface()
                }
            }
        }
        .padding(24)
        .frame(minWidth: 820, minHeight: 560)
        .background(ClipAllTheme.canvas)
        .tint(ClipAllTheme.accent)
        .task {
            await environment.start()
            reconcileSelection()
        }
        .onChange(of: filteredDescriptors.map(\.id)) { _, _ in
            reconcileSelection()
        }
    }

    private var capabilityList: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("搜索能力或插件", text: $model.query)
                .textFieldStyle(.roundedBorder)

            Text("\(filteredDescriptors.count) 个能力")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filteredDescriptors) { descriptor in
                        Button {
                            model.selectedCapabilityID = descriptor.id
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: descriptor.symbolName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(
                                        model.selectedCapabilityID == descriptor.id
                                            ? ClipAllTheme.accent
                                            : .secondary
                                    )
                                    .frame(width: 32, height: 32)
                                    .background(ClipAllTheme.quietFill, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(descriptor.name)
                                        .fontWeight(.medium)
                                    Text(pluginName(for: descriptor))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                if model.selectedCapabilityID == descriptor.id {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(ClipAllTheme.accent.opacity(0.08))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func capabilityDetail(_ descriptor: CapabilityDescriptor) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: descriptor.symbolName)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(ClipAllTheme.accent)
                        .frame(width: 48, height: 48)
                        .background(ClipAllTheme.accent.opacity(0.07), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(descriptor.name)
                            .font(.title2.weight(.semibold))
                        Text(descriptor.purpose)
                            .foregroundStyle(.secondary)
                        Text(pluginName(for: descriptor))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
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

                VStack(alignment: .leading, spacing: 10) {
                    Text("适用内容")
                        .font(.headline)
                    Text(descriptor.supportedContentKinds.map(contentKindName).sorted().joined(separator: "、"))
                        .foregroundStyle(.secondary)
                }

                if !descriptor.examples.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("示例")
                            .font(.headline)
                        ForEach(descriptor.examples, id: \.self) { example in
                            Text(example)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    ClipAllTheme.quietFill,
                                    in: RoundedRectangle(cornerRadius: 9)
                                )
                        }
                    }
                }

                if let plugin = registry.plugin(for: descriptor.pluginID),
                   !plugin.configurationFields.isEmpty {
                    Divider()
                    SettingsLink {
                        Label("在设置中配置“\(plugin.name)”", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
