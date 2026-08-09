import SwiftUI

struct CapabilitiesSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var registry: CapabilityRegistry

    var body: some View {
        HStack(spacing: ClipAllTheme.Spacing.sm) {
            ClipAllSectionCard(
                "固定操作",
                subtitle: "复制始终位于首位；下列顺序与取词浮窗一致。"
            ) {
                HStack {
                    Text("已固定")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(settings.pinnedCapabilityIDs.count)/\(SettingsStore.maximumPinnedCapabilities)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    if settings.pinnedCapabilityIDs.isEmpty {
                        ContentUnavailableView(
                            "还没有固定操作",
                            systemImage: "pin",
                            description: Text("从右侧选择常用能力。")
                        )
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(settings.pinnedCapabilityIDs.enumerated()), id: \.element) { index, id in
                                pinnedRow(id: id, index: index)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            ClipAllSectionCard(
                "可固定能力",
                subtitle: "最多固定 4 个，其他能力仍可从“更多”中找到。"
            ) {
                ScrollView {
                    if unpinnedDescriptors.isEmpty {
                        ContentUnavailableView(
                            "没有更多能力",
                            systemImage: "checkmark.circle",
                            description: Text("已启用能力都在操作栏中。")
                        )
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        LazyVStack(spacing: 6) {
                            ForEach(unpinnedDescriptors) { descriptor in
                                ClipAllHoverRow {
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
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(ClipAllTheme.Spacing.lg)
    }

    private var unpinnedDescriptors: [CapabilityDescriptor] {
        registry.descriptors.filter { !settings.pinnedCapabilityIDs.contains($0.id) }
    }

    private func pinnedRow(id: CapabilityID, index: Int) -> some View {
        let descriptor = registry.descriptor(for: id)
        return ClipAllHoverRow {
            HStack(spacing: 10) {
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
        }
    }

    private func capabilityIcon(_ descriptor: CapabilityDescriptor) -> some View {
        ClipAllIconBadge(
            symbolName: descriptor.symbolName,
            size: ClipAllTheme.Size.iconSmall
        )
    }

    private func pluginName(for descriptor: CapabilityDescriptor) -> String {
        registry.plugin(for: descriptor.pluginID)?.name ?? descriptor.pluginID.rawValue
    }
}
