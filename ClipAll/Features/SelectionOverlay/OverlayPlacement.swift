import CoreGraphics
import Foundation

struct OverlayPlacement: Sendable {
    static let edgeInset: CGFloat = 10
    static let selectionGap: CGFloat = 8

    static func calculate(
        anchor: CGRect,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> CGRect {
        let preferredX = anchor.midX - panelSize.width / 2
        let clampedX = min(
            max(preferredX, visibleFrame.minX + edgeInset),
            max(visibleFrame.minX + edgeInset, visibleFrame.maxX - panelSize.width - edgeInset)
        )

        let belowY = anchor.minY - selectionGap - panelSize.height
        let aboveY = anchor.maxY + selectionGap
        let fitsBelow = belowY >= visibleFrame.minY + edgeInset
        let preferredY = fitsBelow ? belowY : aboveY
        let clampedY = min(
            max(preferredY, visibleFrame.minY + edgeInset),
            max(visibleFrame.minY + edgeInset, visibleFrame.maxY - panelSize.height - edgeInset)
        )

        return CGRect(origin: CGPoint(x: clampedX, y: clampedY), size: panelSize)
    }
}
