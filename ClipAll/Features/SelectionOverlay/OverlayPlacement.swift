import CoreGraphics
import Foundation

enum OverlayAttachmentEdge: Sendable {
    case top
    case bottom
}

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

    static func attachmentEdge(for frame: CGRect, anchor: CGRect) -> OverlayAttachmentEdge {
        let distanceFromTopToSelection = abs(frame.maxY - anchor.minY)
        let distanceFromBottomToSelection = abs(frame.minY - anchor.maxY)
        return distanceFromTopToSelection <= distanceFromBottomToSelection ? .top : .bottom
    }

    static func resizedFrame(
        from currentFrame: CGRect,
        panelSize: CGSize,
        visibleFrame: CGRect,
        attachmentEdge: OverlayAttachmentEdge
    ) -> CGRect {
        let minX = visibleFrame.minX + edgeInset
        let minY = visibleFrame.minY + edgeInset
        let maxVisibleX = visibleFrame.maxX - edgeInset
        let maxVisibleY = visibleFrame.maxY - edgeInset
        let width = min(panelSize.width, max(1, maxVisibleX - minX))
        let maxX = max(minX, maxVisibleX - width)
        let x = min(max(currentFrame.minX, minX), maxX)

        switch attachmentEdge {
        case .top:
            let topY = min(max(currentFrame.maxY, minY + 40), maxVisibleY)
            let height = min(panelSize.height, max(40, topY - minY))
            return CGRect(x: x, y: topY - height, width: width, height: height)
        case .bottom:
            let bottomY = min(max(currentFrame.minY, minY), maxVisibleY - 40)
            let height = min(panelSize.height, max(40, maxVisibleY - bottomY))
            return CGRect(x: x, y: bottomY, width: width, height: height)
        }
    }
}
