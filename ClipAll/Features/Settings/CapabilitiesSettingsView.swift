import SwiftUI

struct CapabilitiesSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var registry: CapabilityRegistry

    var body: some View {
        ClipAllSettingsPage(
            "操作栏",
            subtitle: "调整已固定能力的顺序；新的能力从所属插件详情中固定。"
        ) {
            ClipAllSettingsSection(
                "浮窗预览",
                subtitle: "复制始终在首位；能力顺序会实时同步到取词浮窗。"
            ) {
                toolbarPreview
            }

            ClipAllSettingsSection(
                "已固定",
                subtitle: "在这里调整顺序或取消固定；新增能力请前往所属插件。"
            ) {
                HStack(spacing: ClipAllTheme.Spacing.xs) {
                    ClipAllTag(
                        "\(settings.pinnedCapabilityIDs.count)/\(SettingsStore.maximumPinnedCapabilities)",
                        tone: .accent,
                        systemImage: "pin.fill"
                    )
                    Spacer()
                    Text("最多固定 \(SettingsStore.maximumPinnedCapabilities) 个能力")
                        .font(ClipAllTheme.Typography.supporting)
                        .foregroundStyle(ClipAllTheme.textSecondary)
                }
                .padding(.bottom, ClipAllTheme.Spacing.xxs)

                if settings.pinnedCapabilityIDs.isEmpty {
                    ClipAllEmptyState(
                        title: "还没有固定能力",
                        systemImage: "pin",
                        message: "请在“插件”页面选择插件，并固定它提供的能力。",
                        minimumHeight: 96
                    )
                } else {
                    LazyVStack(spacing: ClipAllTheme.Spacing.xs) {
                        ForEach(Array(settings.pinnedCapabilityIDs.enumerated()), id: \.element) { index, id in
                            pinnedRow(id: id, index: index)
                        }
                    }
                }
            }
        }
    }

    private var toolbarPreview: some View {
        HStack(spacing: 0) {
            previewItem(title: "复制", symbolName: "doc.on.doc", isAccent: false)
            previewItem(title: "粘贴", symbolName: "doc.on.clipboard", isAccent: false)

            ForEach(settings.pinnedCapabilityIDs, id: \.self) { id in
                let descriptor = registry.descriptor(for: id)
                previewItem(
                    title: descriptor?.name ?? id.rawValue,
                    symbolName: descriptor?.symbolName ?? "puzzlepiece.extension",
                    isAccent: true
                )
            }

            Rectangle()
                .fill(ClipAllTheme.separator)
                .frame(width: 1, height: 18)
            Image(systemName: "plus")
                .foregroundStyle(ClipAllTheme.textSecondary)
                .frame(width: 38, height: 34)
        }
        .padding(ClipAllTheme.Spacing.xxs)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            ClipAllTheme.overlaySurface,
            in: RoundedRectangle(
                cornerRadius: ClipAllTheme.Radius.overlayChrome,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: ClipAllTheme.Radius.overlayChrome,
                style: .continuous
            )
            .stroke(ClipAllTheme.overlayBorder, lineWidth: 0.75)
        }
        .shadow(
            color: ClipAllTheme.shadowFloating,
            radius: ClipAllTheme.Shadow.floatingRadius,
            y: ClipAllTheme.Shadow.floatingY
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("取词浮窗操作栏预览")
    }

    private func previewItem(
        title: String,
        symbolName: String,
        isAccent: Bool
    ) -> some View {
        HStack(spacing: ClipAllTheme.Spacing.xxs) {
            ClipAllToolbarGlyph(symbolName: symbolName, isAccented: isAccent)
            Text(title)
                .lineLimit(1)
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(ClipAllTheme.textPrimary)
        .padding(.horizontal, ClipAllTheme.Spacing.sm)
        .frame(height: 34)
    }

    private func pinnedRow(id: CapabilityID, index: Int) -> some View {
        let descriptor = registry.descriptor(for: id)
        return ClipAllSettingsRow(minimumHeight: 68) {
            HStack(spacing: ClipAllTheme.Spacing.sm) {
                if let descriptor {
                    capabilityIcon(descriptor)
                } else {
                    ClipAllIconBadge(
                        symbolName: "puzzlepiece.extension",
                        size: ClipAllTheme.Size.iconSmall,
                        tone: .neutral
                    )
                }
                VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.xxs) {
                    Text(descriptor?.name ?? id.rawValue)
                        .font(ClipAllTheme.Typography.body.weight(.semibold))
                        .foregroundStyle(ClipAllTheme.textPrimary)
                    if let descriptor {
                        Text(descriptor.purpose)
                            .font(ClipAllTheme.Typography.supporting)
                            .foregroundStyle(ClipAllTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
        } trailing: {
            HStack(spacing: ClipAllTheme.Spacing.xs) {
                if let descriptor {
                    ClipAllTag(pluginName(for: descriptor), tone: .muted)
                }
                ClipAllTag("\(index + 1)", tone: .accent)

                Button { settings.movePinned(id, by: -1) } label: {
                    Image(systemName: "chevron.up")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)
                .help("上移 \(descriptor?.name ?? id.rawValue)")
                .accessibilityLabel("上移 \(descriptor?.name ?? id.rawValue)")

                Button { settings.movePinned(id, by: 1) } label: {
                    Image(systemName: "chevron.down")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(index == settings.pinnedCapabilityIDs.count - 1)
                .help("下移 \(descriptor?.name ?? id.rawValue)")
                .accessibilityLabel("下移 \(descriptor?.name ?? id.rawValue)")

                Button("取消固定") { _ = settings.setPinned(id, isPinned: false) }
                    .buttonStyle(ClipAllButtonStyle(variant: .secondary))
                    .accessibilityLabel("取消固定 \(descriptor?.name ?? id.rawValue)")
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
