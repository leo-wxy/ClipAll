import CoreGraphics
import Foundation

struct OverlayPlacement: Sendable {
    static let edgeInset: CGFloat = 10
    static let selectionGap: CGFloat = 8
    static let minimumPanelHeight: CGFloat = 36

    static func calculate(
        anchor: CGRect,
        triggerLocation: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> CGRect {
        let minimumY = visibleFrame.minY + edgeInset
        let maximumY = visibleFrame.maxY - edgeInset
        let fitsBelow = anchor.minY - selectionGap - panelSize.height >= minimumY
        let fitsAbove = anchor.maxY + selectionGap + panelSize.height <= maximumY
        let placementAnchor = fitsBelow || fitsAbove
            ? anchor
            : CGRect(origin: triggerLocation, size: CGSize(width: 1, height: 1))

        let preferredX = placementAnchor.midX - panelSize.width / 2
        let clampedX = min(
            max(preferredX, visibleFrame.minX + edgeInset),
            max(visibleFrame.minX + edgeInset, visibleFrame.maxX - panelSize.width - edgeInset)
        )

        let belowY = placementAnchor.minY - selectionGap - panelSize.height
        let aboveY = placementAnchor.maxY + selectionGap
        let preferredY = belowY >= minimumY ? belowY : aboveY
        let clampedY = min(
            max(preferredY, minimumY),
            max(minimumY, maximumY - panelSize.height)
        )

        return CGRect(origin: CGPoint(x: clampedX, y: clampedY), size: panelSize)
    }

    static func resizedFrame(
        anchoredTopLeft: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> CGRect {
        let minX = visibleFrame.minX + edgeInset
        let minY = visibleFrame.minY + edgeInset
        let maxVisibleX = visibleFrame.maxX - edgeInset
        let maxVisibleY = visibleFrame.maxY - edgeInset
        let width = min(panelSize.width, max(1, maxVisibleX - minX))
        let maxX = max(minX, maxVisibleX - width)
        let x = min(max(anchoredTopLeft.x, minX), maxX)

        let topY = min(max(anchoredTopLeft.y, minY + minimumPanelHeight), maxVisibleY)
        let height = min(panelSize.height, max(minimumPanelHeight, topY - minY))
        return CGRect(x: x, y: topY - height, width: width, height: height)
    }
}
