import SwiftUI

enum ClipAllTheme {
    static let accent = Color(red: 0.96, green: 0.27, blue: 0.10)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color(nsColor: .underPageBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let border = Color.primary.opacity(0.08)
    static let quietFill = Color.primary.opacity(0.045)
}

private struct ClipAllSurfaceModifier: ViewModifier {
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
            .shadow(color: .black.opacity(0.035), radius: 10, y: 4)
    }
}

extension View {
    func clipAllSurface(cornerRadius: CGFloat = 14) -> some View {
        modifier(ClipAllSurfaceModifier(cornerRadius: cornerRadius))
    }
}
