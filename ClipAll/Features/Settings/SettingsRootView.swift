import AppKit
import Combine
import SwiftUI

private enum SettingsSection: String, CaseIterable, Hashable, Identifiable {
    case selection
    case general
    case capabilities
    case plugins
    case developer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selection: "取词"
        case .general: "通用"
        case .capabilities: "操作栏"
        case .plugins: "插件"
        case .developer: "开发者"
        }
    }

    var symbolName: String {
        switch self {
        case .selection: "selection.pin.in.out"
        case .general: "gearshape"
        case .capabilities: "rectangle.stack"
        case .plugins: "puzzlepiece.extension"
        case .developer: "chevron.left.forwardslash.chevron.right"
        }
    }
}

@MainActor
private final class SettingsNavigationModel: ObservableObject {
    @Published var selection: SettingsSection = .selection
}

struct SettingsRootView: View {
    let environment: AppEnvironment
    @StateObject private var navigation = SettingsNavigationModel()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(ClipAllTheme.separator)
                .frame(width: 1)
            VStack(spacing: 0) {
                content
            }
            .background(ClipAllTheme.canvas)
        }
        .background(ClipAllTheme.sidebar)
        .frame(minWidth: 1_020, idealWidth: 1_140, minHeight: 650, idealHeight: 720)
        .tint(ClipAllTheme.accent)
        .task { await environment.start() }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: ClipAllTheme.Spacing.sm) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ClipAll")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ClipAllTheme.textPrimary)
                    Text("本地文字能力工具")
                        .font(.caption)
                        .foregroundStyle(ClipAllTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: ClipAllTheme.Spacing.xxs) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        navigation.selection = section
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.symbolName)
                                .font(.system(size: 15, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                                .frame(width: 22)
                            Text(section.title)
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(
                            navigation.selection == section
                                ? ClipAllTheme.accent
                                : ClipAllTheme.textPrimary
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(
                        ClipAllSelectableRowStyle(
                            isSelected: navigation.selection == section
                        )
                    )
                    .accessibilityAddTraits(
                        navigation.selection == section ? .isSelected : []
                    )
                }
            }
            .padding(.top, ClipAllTheme.Spacing.xl)

            Spacer()

            VStack(alignment: .leading, spacing: 3) {
                Text("版本 \(appVersion)")
                    .font(.caption.monospacedDigit().weight(.medium))
                Text("菜单栏与 Dock 均可打开")
                    .font(.caption2)
                    .foregroundStyle(ClipAllTheme.textSecondary)
            }
        }
        .padding(.horizontal, ClipAllTheme.Spacing.md)
        .padding(.top, 46)
        .padding(.bottom, ClipAllTheme.Spacing.md)
        .frame(width: ClipAllTheme.Size.settingsSidebar)
        .frame(maxHeight: .infinity)
        .background(ClipAllTheme.sidebar)
    }

    @ViewBuilder
    private var content: some View {
        switch navigation.selection {
        case .selection:
            SelectionSettingsView(settings: environment.settings)
        case .general:
            GeneralSettingsView(
                settings: environment.settings,
                permissions: environment.permissions
            )
        case .capabilities:
            CapabilitiesSettingsView(
                settings: environment.settings,
                registry: environment.registry
            )
        case .plugins:
            PluginsSettingsView(environment: environment)
        case .developer:
            DeveloperSettingsView(environment: environment)
        }
    }
}
