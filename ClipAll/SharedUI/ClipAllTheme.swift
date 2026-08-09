import AppKit
import SwiftUI

enum ClipAllTheme {
    static let accent = Color(nsColor: accentColor)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color(nsColor: .underPageBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let elevatedSurface = Color(nsColor: .textBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
    static let border = Color.primary.opacity(0.095)
    static let quietFill = Color.primary.opacity(0.038)
    static let hoverFill = Color.primary.opacity(0.055)
    static let pressedFill = Color.primary.opacity(0.09)
    static let accentSoft = accent.opacity(0.07)
    static let selectionFill = accent.opacity(0.075)

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let control: CGFloat = 8
        static let row: CGFloat = 10
        static let surface: CGFloat = 16
        static let overlayChrome: CGFloat = 8
    }

    enum Size {
        static let settingsSidebar: CGFloat = 188
        static let pluginList: CGFloat = 260
        static let capabilityList: CGFloat = 246
        static let iconSmall: CGFloat = 30
        static let iconMedium: CGFloat = 40
        static let iconLarge: CGFloat = 48
    }

    private static let accentColor = NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        if match == .darkAqua {
            return NSColor(srgbRed: 0.88, green: 0.48, blue: 0.39, alpha: 1)
        }
        return NSColor(srgbRed: 0.72, green: 0.29, blue: 0.23, alpha: 1)
    }
}

private struct ClipAllSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                ClipAllTheme.surface,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(ClipAllTheme.border, lineWidth: 1)
            }
            .shadow(
                color: colorScheme == .dark ? .clear : .black.opacity(0.045),
                radius: 12,
                y: 4
            )
    }
}

private struct ClipAllInsetModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                ClipAllTheme.quietFill,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(ClipAllTheme.border.opacity(0.7), lineWidth: 0.75)
            }
    }
}

extension View {
    func clipAllSurface(cornerRadius: CGFloat = ClipAllTheme.Radius.surface) -> some View {
        modifier(ClipAllSurfaceModifier(cornerRadius: cornerRadius))
    }

    func clipAllInset(cornerRadius: CGFloat = ClipAllTheme.Radius.row) -> some View {
        modifier(ClipAllInsetModifier(cornerRadius: cornerRadius))
    }
}

struct ClipAllIconBadge: View {
    enum Tone {
        case accent
        case neutral
    }

    let symbolName: String
    var size: CGFloat = ClipAllTheme.Size.iconMedium
    var tone: Tone = .accent

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(tone == .accent ? ClipAllTheme.accent : Color.secondary)
            .frame(width: size, height: size)
            .background(
                tone == .accent ? ClipAllTheme.accentSoft : ClipAllTheme.quietFill,
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            )
    }
}

struct ClipAllSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(ClipAllTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipAllSurface()
    }
}

struct ClipAllHoverRow<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: ClipAllTheme.Radius.row, style: .continuous)
                        .fill(ClipAllTheme.quietFill)
                    ClipAllHoverHighlight(
                        cornerRadius: ClipAllTheme.Radius.row,
                        opacity: 0.065
                    )
                }
            }
    }
}

struct ClipAllSelectableRowStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> Body {
        Body(configuration: configuration, isSelected: isSelected)
    }

    struct Body: View {
        let configuration: Configuration
        let isSelected: Bool

        var body: some View {
            configuration.label
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: ClipAllTheme.Radius.row, style: .continuous)
                            .fill(isSelected ? ClipAllTheme.selectionFill : .clear)
                        ClipAllHoverHighlight(
                            cornerRadius: ClipAllTheme.Radius.row,
                            opacity: isSelected ? 0.035 : 0.065
                        )
                        if configuration.isPressed {
                            RoundedRectangle(cornerRadius: ClipAllTheme.Radius.row, style: .continuous)
                                .fill(ClipAllTheme.pressedFill)
                        }
                    }
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(
                            cornerRadius: ClipAllTheme.Radius.row,
                            style: .continuous
                        )
                        .stroke(ClipAllTheme.accent.opacity(0.24), lineWidth: 1)
                    }
                }
                .overlay(alignment: .leading) {
                    if isSelected {
                        Capsule()
                            .fill(ClipAllTheme.accent)
                            .frame(width: 2.5, height: 24)
                            .padding(.leading, 1)
                    }
                }
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}

private struct ClipAllHoverHighlight: NSViewRepresentable {
    let cornerRadius: CGFloat
    let opacity: CGFloat

    func makeNSView(context: Context) -> ClipAllHoverTrackingView {
        ClipAllHoverTrackingView(cornerRadius: cornerRadius, highlightOpacity: opacity)
    }

    func updateNSView(_ nsView: ClipAllHoverTrackingView, context: Context) {
        nsView.cornerRadius = cornerRadius
        nsView.highlightOpacity = opacity
    }
}

private final class ClipAllHoverTrackingView: NSView {
    var cornerRadius: CGFloat {
        didSet { layer?.cornerRadius = cornerRadius }
    }
    var highlightOpacity: CGFloat {
        didSet { updateHighlight() }
    }

    private var trackingAreaReference: NSTrackingArea?
    private var isHighlighted = false

    init(cornerRadius: CGFloat, highlightOpacity: CGFloat) {
        self.cornerRadius = cornerRadius
        self.highlightOpacity = highlightOpacity
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        updateHighlight()
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        updateHighlight()
    }

    private func updateHighlight() {
        layer?.backgroundColor = isHighlighted
            ? NSColor.labelColor.withAlphaComponent(highlightOpacity).cgColor
            : NSColor.clear.cgColor
    }
}
