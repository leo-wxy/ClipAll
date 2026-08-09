import Combine
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
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
        case .general: "设置取词行为、快捷键与系统权限"
        case .capabilities: "安排固定操作、智能推荐与更多入口"
        case .plugins: "管理内置与外置能力"
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
        HStack(spacing: 0) {
            settingsSidebar
            Rectangle()
                .fill(ClipAllTheme.border)
                .frame(width: 1)
            content
        }
        .frame(minWidth: 980, idealWidth: 1080, minHeight: 620, idealHeight: 680)
        .background(ClipAllTheme.canvas)
        .tint(ClipAllTheme.accent)
        .ignoresSafeArea(.container, edges: .top)
        .task { await environment.start() }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(SettingsSection.allCases) { section in
                Button {
                    navigation.selection = section
                } label: {
                    Label(section.title, systemImage: section.symbolName)
                        .font(.system(size: 14, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            navigation.selection == section ? ClipAllTheme.accent : .primary
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background {
                            if navigation.selection == section {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(ClipAllTheme.accent.opacity(0.09))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(navigation.selection == section ? .isSelected : [])
            }

            Spacer()

            VStack(alignment: .leading, spacing: 3) {
                Text("ClipAll")
                    .font(.caption.weight(.semibold))
                Text("本地文字能力工具")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .padding(.top, 54)
        .frame(width: 220)
        .background(.ultraThinMaterial)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(navigation.selection.title)
                    .font(.system(size: 24, weight: .bold))
                Text(navigation.selection.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 34)

            Group {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ClipAllTheme.canvas)
    }
}
