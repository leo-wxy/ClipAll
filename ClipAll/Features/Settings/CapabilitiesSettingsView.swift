import SwiftUI

struct CapabilitiesSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var registry: CapabilityRegistry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("固定能力")
                        .font(.headline)
                    Spacer()
                    Text("\(settings.pinnedCapabilityIDs.count)/\(SettingsStore.maximumPinnedCapabilities)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text("复制始终位于首位；这里的顺序就是取词面板中的显示顺序。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(Array(settings.pinnedCapabilityIDs.enumerated()), id: \.element) { index, id in
                            pinnedRow(id: id, index: index)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipAllSurface()

            VStack(alignment: .leading, spacing: 12) {
                Text("可固定")
                    .font(.headline)
                Text("从已启用插件中选择常用能力，最多固定 4 个。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(unpinnedDescriptors) { descriptor in
                            HStack(spacing: 10) {
                                capabilityIcon(descriptor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(descriptor.name)
                                        .fontWeight(.medium)
                                    Text(pluginName(for: descriptor))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("固定") {
                                    _ = settings.setPinned(descriptor.id, isPinned: true)
                                }
                                .disabled(
                                    settings.pinnedCapabilityIDs.count
                                        >= SettingsStore.maximumPinnedCapabilities
                                )
                            }
                            .padding(11)
                            .background(
                                ClipAllTheme.quietFill,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipAllSurface()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var unpinnedDescriptors: [CapabilityDescriptor] {
        registry.descriptors.filter { !settings.pinnedCapabilityIDs.contains($0.id) }
    }

    private func pinnedRow(id: CapabilityID, index: Int) -> some View {
        let descriptor = registry.descriptor(for: id)
        return HStack(spacing: 10) {
            if let descriptor { capabilityIcon(descriptor) }
            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor?.name ?? id.rawValue)
                    .fontWeight(.medium)
                if let descriptor {
                    Text(pluginName(for: descriptor))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { settings.movePinned(id, by: -1) } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .help("上移")

            Button { settings.movePinned(id, by: 1) } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index == settings.pinnedCapabilityIDs.count - 1)
            .help("下移")

            Button("取消固定") { _ = settings.setPinned(id, isPinned: false) }
        }
        .padding(11)
        .background(
            ClipAllTheme.quietFill,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private func capabilityIcon(_ descriptor: CapabilityDescriptor) -> some View {
        Image(systemName: descriptor.symbolName)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(ClipAllTheme.accent)
            .frame(width: 32, height: 32)
            .background(ClipAllTheme.accent.opacity(0.07), in: Circle())
    }

    private func pluginName(for descriptor: CapabilityDescriptor) -> String {
        registry.plugin(for: descriptor.pluginID)?.name ?? descriptor.pluginID.rawValue
    }
}
