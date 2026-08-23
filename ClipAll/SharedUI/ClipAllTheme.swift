import AppKit
import SwiftUI

enum ClipAllTheme {
    static let accent = adaptive(
        light: NSColor(srgbRed: 0.16, green: 0.40, blue: 0.93, alpha: 1),
        dark: NSColor(srgbRed: 0.28, green: 0.55, blue: 1.00, alpha: 1)
    )
    static let canvas = adaptive(
        light: NSColor(srgbRed: 0.965, green: 0.953, blue: 0.925, alpha: 1),
        dark: NSColor(srgbRed: 0.075, green: 0.090, blue: 0.122, alpha: 1)
    )
    static let sidebar = adaptive(
        light: NSColor(srgbRed: 0.935, green: 0.918, blue: 0.882, alpha: 1),
        dark: NSColor(srgbRed: 0.050, green: 0.064, blue: 0.090, alpha: 1)
    )
    static let contentSurface = adaptive(
        light: NSColor(srgbRed: 0.985, green: 0.978, blue: 0.958, alpha: 1),
        dark: NSColor(srgbRed: 0.096, green: 0.118, blue: 0.158, alpha: 1)
    )
    static let elevatedSurface = adaptive(
        light: NSColor(srgbRed: 1.000, green: 0.996, blue: 0.984, alpha: 1),
        dark: NSColor(srgbRed: 0.126, green: 0.153, blue: 0.202, alpha: 1)
    )
    static let overlaySurface = adaptive(
        light: NSColor(srgbRed: 0.985, green: 0.978, blue: 0.960, alpha: 1),
        dark: NSColor(srgbRed: 0.085, green: 0.103, blue: 0.139, alpha: 1)
    )
    static let overlayBorder = adaptive(
        light: NSColor(srgbRed: 0.08, green: 0.12, blue: 0.20, alpha: 0.18),
        dark: NSColor(srgbRed: 0.83, green: 0.88, blue: 0.98, alpha: 0.18)
    )
    static let overlayPressedFill = adaptive(
        light: NSColor(srgbRed: 0.08, green: 0.12, blue: 0.20, alpha: 0.085),
        dark: NSColor(srgbRed: 0.83, green: 0.88, blue: 0.98, alpha: 0.13)
    )
    static let surface = contentSurface
    static let textPrimary = adaptive(
        light: NSColor(srgbRed: 0.075, green: 0.112, blue: 0.190, alpha: 1),
        dark: NSColor(srgbRed: 0.935, green: 0.957, blue: 1.000, alpha: 1)
    )
    static let textSecondary = adaptive(
        light: NSColor(srgbRed: 0.345, green: 0.400, blue: 0.505, alpha: 1),
        dark: NSColor(srgbRed: 0.635, green: 0.690, blue: 0.790, alpha: 1)
    )
    static let separator = adaptive(
        light: NSColor(srgbRed: 0.08, green: 0.12, blue: 0.20, alpha: 0.105),
        dark: NSColor(srgbRed: 0.83, green: 0.88, blue: 0.98, alpha: 0.115)
    )
    static let border = adaptive(
        light: NSColor(srgbRed: 0.08, green: 0.12, blue: 0.20, alpha: 0.13),
        dark: NSColor(srgbRed: 0.83, green: 0.88, blue: 0.98, alpha: 0.15)
    )
    static let quietFill = adaptive(
        light: NSColor(srgbRed: 0.08, green: 0.12, blue: 0.20, alpha: 0.042),
        dark: NSColor(srgbRed: 0.83, green: 0.88, blue: 0.98, alpha: 0.065)
    )
    static let pressedFill = adaptive(
        light: NSColor(srgbRed: 0.08, green: 0.12, blue: 0.20, alpha: 0.105),
        dark: NSColor(srgbRed: 0.83, green: 0.88, blue: 0.98, alpha: 0.135)
    )
    static let accentSoft = adaptive(
        light: NSColor(srgbRed: 0.16, green: 0.40, blue: 0.93, alpha: 0.105),
        dark: NSColor(srgbRed: 0.28, green: 0.55, blue: 1.00, alpha: 0.16)
    )
    static let selectionFill = adaptive(
        light: NSColor(srgbRed: 0.16, green: 0.40, blue: 0.93, alpha: 0.12),
        dark: NSColor(srgbRed: 0.28, green: 0.55, blue: 1.00, alpha: 0.19)
    )
    static let focusRing = accent.opacity(0.58)
    static let onAccent = Color.white
    static let accentPressedFill = Color.white.opacity(0.18)
    static let spark = Color(nsColor: .systemOrange)
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let error = Color(nsColor: .systemRed)
    static let shadowFloating = adaptive(
        light: NSColor.black.withAlphaComponent(0.18),
        dark: NSColor.black.withAlphaComponent(0.54)
    )

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
        static let overlayChrome: CGFloat = 8
    }

    enum Shadow {
        static let floatingRadius: CGFloat = 14
        static let floatingY: CGFloat = 6
    }

    enum Interaction {
        static let hoverOpacity: CGFloat = 0.065
        static let selectedHoverOpacity: CGFloat = 0.035
        static let chromeHoverOpacity: CGFloat = 0.045
        static let activeChromeHoverOpacity: CGFloat = 0.07
        static let disabledOpacity: CGFloat = 0.46
    }

    enum Size {
        static let settingsSidebar: CGFloat = 208
        static let settingsContent: CGFloat = 780
        static let pluginList: CGFloat = 272
        static let capabilityList: CGFloat = 246
        static let formLabel: CGFloat = 220
        static let formControl: CGFloat = 340
        static let iconSmall: CGFloat = 30
        static let iconMedium: CGFloat = 40
        static let iconLarge: CGFloat = 48
        static let controlHeight: CGFloat = 32
        static let settingsRowMinimumHeight: CGFloat = 54
    }

    enum Typography {
        static let pageTitle = Font.system(size: 23, weight: .semibold)
        static let sectionTitle = Font.system(size: 15, weight: .semibold)
        static let body = Font.system(size: 13)
        static let supporting = Font.system(size: 12)
        static let monospacedSupporting = Font.system(size: 12, design: .monospaced)
    }

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        })
    }
}

struct ClipAllPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.xs) {
            Text(title)
                .font(ClipAllTheme.Typography.pageTitle)
                .foregroundStyle(ClipAllTheme.textPrimary)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(ClipAllTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ClipAllSettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(
        _ title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ClipAllPageHeader(title: title, subtitle: subtitle)
                    .padding(.bottom, ClipAllTheme.Spacing.lg)
                content
            }
            .frame(maxWidth: ClipAllTheme.Size.settingsContent, alignment: .leading)
            .padding(ClipAllTheme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .top)
        }
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
    func clipAllInset(cornerRadius: CGFloat = ClipAllTheme.Radius.row) -> some View {
        modifier(ClipAllInsetModifier(cornerRadius: cornerRadius))
    }
}

struct ClipAllIconBadge: View {
    enum Tone {
        case accent
        case neutral
        case success
        case warning
        case error
    }

    let symbolName: String
    var size: CGFloat = ClipAllTheme.Size.iconMedium
    var tone: Tone = .accent

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(foregroundColor)
            .frame(width: size, height: size)
            .background(
                backgroundColor,
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            )
    }

    private var foregroundColor: Color {
        switch tone {
        case .accent: ClipAllTheme.accent
        case .neutral: ClipAllTheme.textSecondary
        case .success: ClipAllTheme.success
        case .warning: ClipAllTheme.warning
        case .error: ClipAllTheme.error
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .accent: ClipAllTheme.accentSoft
        case .neutral: ClipAllTheme.quietFill
        case .success: ClipAllTheme.success.opacity(0.11)
        case .warning: ClipAllTheme.warning.opacity(0.12)
        case .error: ClipAllTheme.error.opacity(0.11)
        }
    }
}

struct ClipAllToolbarGlyph: View {
    let symbolName: String
    var isAccented = false

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: isAccented ? 9.5 : 13, weight: .semibold))
            .foregroundStyle(isAccented ? ClipAllTheme.onAccent : ClipAllTheme.textPrimary)
            .frame(width: isAccented ? 17 : 14, height: isAccented ? 17 : 14)
            .background {
                if isAccented {
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .fill(ClipAllTheme.accent)
                }
            }
    }
}

struct ClipAllSettingsRowLabel: View {
    let title: String
    let subtitle: String?
    let symbolName: String

    var body: some View {
        HStack(alignment: .center, spacing: ClipAllTheme.Spacing.sm) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ClipAllTheme.accent)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.xxs) {
                Text(title)
                    .font(ClipAllTheme.Typography.body.weight(.medium))
                    .foregroundStyle(ClipAllTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(ClipAllTheme.Typography.supporting)
                        .foregroundStyle(ClipAllTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct ClipAllSettingsRow<Leading: View, Trailing: View>: View {
    let alignment: VerticalAlignment
    let minimumHeight: CGFloat
    let leading: Leading
    let trailing: Trailing

    init(
        alignment: VerticalAlignment = .center,
        minimumHeight: CGFloat = ClipAllTheme.Size.settingsRowMinimumHeight,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.alignment = alignment
        self.minimumHeight = minimumHeight
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: ClipAllTheme.Spacing.md) {
            leading
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, ClipAllTheme.Spacing.md)
        .padding(.vertical, ClipAllTheme.Spacing.sm)
        .frame(minHeight: minimumHeight)
        .background(
            ClipAllTheme.quietFill,
            in: RoundedRectangle(cornerRadius: ClipAllTheme.Radius.row, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ClipAllTheme.Radius.row, style: .continuous)
                .stroke(ClipAllTheme.border.opacity(0.62), lineWidth: 0.75)
        }
    }
}

extension ClipAllSettingsRow where Leading == ClipAllSettingsRowLabel {
    init(
        _ title: String,
        subtitle: String? = nil,
        symbolName: String,
        alignment: VerticalAlignment = .center,
        minimumHeight: CGFloat = ClipAllTheme.Size.settingsRowMinimumHeight,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(alignment: alignment, minimumHeight: minimumHeight) {
            ClipAllSettingsRowLabel(
                title: title,
                subtitle: subtitle,
                symbolName: symbolName
            )
        } trailing: {
            trailing()
        }
    }
}

private struct ClipAllControlSlotModifier: ViewModifier {
    let width: CGFloat?
    let minimumHeight: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, ClipAllTheme.Spacing.xs)
            .frame(width: width)
            .frame(minHeight: minimumHeight)
            .clipAllInset(cornerRadius: ClipAllTheme.Radius.control)
    }
}

extension View {
    func clipAllControlSlot(
        width: CGFloat? = nil,
        minimumHeight: CGFloat = ClipAllTheme.Size.controlHeight
    ) -> some View {
        modifier(ClipAllControlSlotModifier(width: width, minimumHeight: minimumHeight))
    }
}

struct ClipAllTag: View {
    enum Tone {
        case neutral
        case accent
        case success
        case warning
        case muted
    }

    let text: String
    var tone: Tone = .neutral
    var systemImage: String?

    init(_ text: String, tone: Tone = .neutral, systemImage: String? = nil) {
        self.text = text
        self.tone = tone
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: ClipAllTheme.Spacing.xxs) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, ClipAllTheme.Spacing.xs)
        .padding(.vertical, ClipAllTheme.Spacing.xxs)
        .background(backgroundColor, in: Capsule())
        .overlay {
            Capsule()
                .stroke(foregroundColor.opacity(0.16), lineWidth: 0.75)
        }
    }

    private var foregroundColor: Color {
        switch tone {
        case .neutral: ClipAllTheme.textPrimary
        case .accent: ClipAllTheme.accent
        case .success: ClipAllTheme.success
        case .warning: ClipAllTheme.warning
        case .muted: ClipAllTheme.textSecondary
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .neutral, .muted: ClipAllTheme.quietFill
        case .accent: ClipAllTheme.accentSoft
        case .success: ClipAllTheme.success.opacity(0.11)
        case .warning: ClipAllTheme.warning.opacity(0.12)
        }
    }
}

struct ClipAllExampleBlock: View {
    let text: String
    var isEmphasized = false

    var body: some View {
        Text(text)
            .font(ClipAllTheme.Typography.monospacedSupporting)
            .foregroundStyle(ClipAllTheme.textPrimary)
            .textSelection(.enabled)
            .padding(.horizontal, ClipAllTheme.Spacing.sm)
            .padding(.vertical, ClipAllTheme.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isEmphasized ? ClipAllTheme.accentSoft : ClipAllTheme.quietFill,
                in: RoundedRectangle(cornerRadius: ClipAllTheme.Radius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ClipAllTheme.Radius.control, style: .continuous)
                    .stroke(
                        isEmphasized ? ClipAllTheme.accent.opacity(0.28) : ClipAllTheme.border,
                        lineWidth: 0.75
                    )
            }
    }
}

struct ClipAllEmptyState: View {
    let title: String
    let systemImage: String
    let message: String
    var minimumHeight: CGFloat = 104

    var body: some View {
        HStack(spacing: ClipAllTheme.Spacing.md) {
            ClipAllIconBadge(
                symbolName: systemImage,
                size: ClipAllTheme.Size.iconMedium,
                tone: .neutral
            )
            VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.xxs) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(ClipAllTheme.textPrimary)
                Text(message)
                    .font(ClipAllTheme.Typography.supporting)
                    .foregroundStyle(ClipAllTheme.textSecondary)
            }
            Spacer()
        }
        .padding(ClipAllTheme.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
        .background(
            ClipAllTheme.quietFill,
            in: RoundedRectangle(cornerRadius: ClipAllTheme.Radius.row, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ClipAllTheme.Radius.row, style: .continuous)
                .stroke(ClipAllTheme.border.opacity(0.62), lineWidth: 0.75)
        }
    }
}

enum ClipAllButtonVariant: Equatable {
    case primary
    case secondary
}

struct ClipAllButtonStyle: ButtonStyle {
    let variant: ClipAllButtonVariant

    func makeBody(configuration: Configuration) -> Body {
        Body(configuration: configuration, variant: variant)
    }

    struct Body: View {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        let configuration: Configuration
        let variant: ClipAllButtonVariant

        var body: some View {
            configuration.label
                .font(.callout.weight(.medium))
                .foregroundStyle(variant == .primary ? ClipAllTheme.onAccent : ClipAllTheme.textPrimary)
                .padding(.horizontal, ClipAllTheme.Spacing.sm)
                .padding(.vertical, 7)
                .background(backgroundColor, in: RoundedRectangle(
                    cornerRadius: ClipAllTheme.Radius.control,
                    style: .continuous
                ))
                .overlay {
                    RoundedRectangle(cornerRadius: ClipAllTheme.Radius.control, style: .continuous)
                        .stroke(
                            isFocused ? ClipAllTheme.focusRing : borderColor,
                            lineWidth: isFocused ? 2 : 0.75
                        )
                }
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : ClipAllTheme.Interaction.disabledOpacity)
        }

        private var backgroundColor: Color {
            if variant == .primary {
                return configuration.isPressed ? ClipAllTheme.accent.opacity(0.82) : ClipAllTheme.accent
            }
            return configuration.isPressed ? ClipAllTheme.pressedFill : ClipAllTheme.elevatedSurface
        }

        private var borderColor: Color {
            variant == .primary ? ClipAllTheme.accent : ClipAllTheme.border
        }
    }
}

struct ClipAllSettingsSection<Content: View>: View {
    let title: String
    let subtitle: String?
    let helpText: String?
    let content: Content
    @State private var isShowingHelp = false

    init(
        _ title: String,
        subtitle: String? = nil,
        helpText: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.helpText = helpText
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.xxs) {
                HStack(spacing: ClipAllTheme.Spacing.xxs) {
                    Text(title)
                        .font(ClipAllTheme.Typography.sectionTitle)
                        .foregroundStyle(ClipAllTheme.textPrimary)
                    if let helpText {
                        Button {
                            isShowingHelp.toggle()
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(ClipAllTheme.textSecondary)
                        .help("查看\(title)说明")
                        .accessibilityLabel("查看\(title)说明")
                        .popover(isPresented: $isShowingHelp) {
                            Text(helpText)
                                .font(ClipAllTheme.Typography.body)
                                .foregroundStyle(ClipAllTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(ClipAllTheme.Spacing.md)
                                .frame(width: 320)
                        }
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(ClipAllTheme.Typography.supporting)
                        .foregroundStyle(ClipAllTheme.textSecondary)
                }
            }
            content
        }
        .padding(.vertical, ClipAllTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ClipAllTheme.separator)
                .frame(height: 1)
        }
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
                        opacity: ClipAllTheme.Interaction.hoverOpacity
                    )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: ClipAllTheme.Radius.row, style: .continuous)
                    .stroke(ClipAllTheme.border.opacity(0.62), lineWidth: 0.75)
            }
    }
}

struct ClipAllSelectableRowStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> Body {
        Body(configuration: configuration, isSelected: isSelected)
    }

    struct Body: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
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
                            opacity: isSelected
                                ? ClipAllTheme.Interaction.selectedHoverOpacity
                                : ClipAllTheme.Interaction.hoverOpacity
                        )
                        if configuration.isPressed {
                            RoundedRectangle(cornerRadius: ClipAllTheme.Radius.row, style: .continuous)
                                .fill(ClipAllTheme.pressedFill)
                        }
                    }
                }
                .overlay {
                    ZStack {
                        if isSelected {
                            RoundedRectangle(
                                cornerRadius: ClipAllTheme.Radius.row,
                                style: .continuous
                            )
                            .stroke(ClipAllTheme.accent.opacity(0.24), lineWidth: 1)
                        }
                        if isFocused {
                            RoundedRectangle(
                                cornerRadius: ClipAllTheme.Radius.row,
                                style: .continuous
                            )
                            .stroke(ClipAllTheme.focusRing, lineWidth: 2)
                        }
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
                .opacity(isEnabled ? 1 : ClipAllTheme.Interaction.disabledOpacity)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.08),
                    value: configuration.isPressed
                )
        }
    }
}

struct ClipAllHoverHighlight: NSViewRepresentable {
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

final class ClipAllHoverTrackingView: NSView {
    var cornerRadius: CGFloat {
        didSet { layer?.cornerRadius = cornerRadius }
    }
    var highlightOpacity: CGFloat {
        didSet { updateHighlight() }
    }

    private var isHighlighted = false

    init(cornerRadius: CGFloat, highlightOpacity: CGFloat) {
        self.cornerRadius = cornerRadius
        self.highlightOpacity = highlightOpacity
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

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
