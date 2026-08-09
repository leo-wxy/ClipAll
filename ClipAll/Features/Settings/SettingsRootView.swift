import Combine
import SwiftUI

private enum SettingsSection: String, CaseIterable, Hashable, Identifiable {
    case general
    case capabilities
    case plugins
    case developer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用"
        case .capabilities: "操作栏"
        case .plugins: "插件"
        case .developer: "开发者"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "取词行为、快捷键与系统权限"
        case .capabilities: "安排取词浮窗中的常用操作"
        case .plugins: "管理内置能力与本地插件"
        case .developer: "载入、重新载入并调试本地插件"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .capabilities: "rectangle.stack"
        case .plugins: "puzzlepiece.extension"
        case .developer: "chevron.left.forwardslash.chevron.right"
        }
    }
}

@MainActor
private final class SettingsNavigationModel: ObservableObject {
    @Published var selection: SettingsSection = .plugins
}

struct SettingsRootView: View {
    let environment: AppEnvironment
    @StateObject private var navigation = SettingsNavigationModel()

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $navigation.selection) { section in
                Label(section.title, systemImage: section.symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(
                min: 164,
                ideal: ClipAllTheme.Size.settingsSidebar,
                max: 194
            )
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ClipAll")
                        .font(.caption.weight(.semibold))
                    Text("本地文字能力工具")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("版本 \(appVersion)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ClipAllTheme.Spacing.sm)
                .padding(.vertical, ClipAllTheme.Spacing.xs)
                .background(.bar)
            }
        } detail: {
            VStack(spacing: 0) {
                pageHeader
                Divider()
                content
            }
            .background(ClipAllTheme.canvas)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 880, idealWidth: 920, minHeight: 580, idealHeight: 620)
        .tint(ClipAllTheme.accent)
        .task { await environment.start() }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: ClipAllTheme.Spacing.sm) {
            ClipAllIconBadge(
                symbolName: navigation.selection.symbolName,
                size: ClipAllTheme.Size.iconMedium
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(navigation.selection.title)
                    .font(.system(size: 20, weight: .semibold))
                Text(navigation.selection.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, ClipAllTheme.Spacing.lg)
        .padding(.vertical, ClipAllTheme.Spacing.sm)
    }

    @ViewBuilder
    private var content: some View {
        switch navigation.selection {
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
