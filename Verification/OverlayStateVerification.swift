import Foundation

private enum OverlayStateVerificationError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

@main
@MainActor
enum OverlayStateVerification {
    static func main() throws {
        try verifyPlacement()
        try verifyEmptyPinnedPersistence()
        print("Overlay state verification passed")
    }

    private static func verifyPlacement() throws {
        let visible = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let size = CGSize(width: 200, height: 120)

        let below = OverlayPlacement.calculate(
            anchor: CGRect(x: 600, y: 400, width: 20, height: 20),
            panelSize: size,
            visibleFrame: visible
        )
        try expect(below.origin == CGPoint(x: 510, y: 272), "空间足够时应显示在选区下方")

        let above = OverlayPlacement.calculate(
            anchor: CGRect(x: 600, y: 20, width: 20, height: 20),
            panelSize: size,
            visibleFrame: visible
        )
        try expect(above.origin == CGPoint(x: 510, y: 48), "下方空间不足时应显示在选区上方")

        let expandedBelow = OverlayPlacement.resizedFrame(
            anchoredTopLeft: CGPoint(x: below.minX, y: below.maxY),
            panelSize: CGSize(width: 200, height: 240),
            visibleFrame: visible
        )
        try expect(expandedBelow.maxY == below.maxY, "选区下方的浮层展开时应保持上边缘不动")

        let collapsedBelow = OverlayPlacement.resizedFrame(
            anchoredTopLeft: CGPoint(x: below.minX, y: below.maxY),
            panelSize: CGSize(width: size.width, height: OverlayPlacement.minimumPanelHeight),
            visibleFrame: visible
        )
        try expect(collapsedBelow.maxY == below.maxY, "浮层展开后再收缩仍应回到同一上边缘")
        try expect(
            collapsedBelow.height == OverlayPlacement.minimumPanelHeight,
            "收缩高度必须与 36pt 操作栏一致，不能产生垂直居中的 2pt 位移"
        )

        let expandedAbove = OverlayPlacement.resizedFrame(
            anchoredTopLeft: CGPoint(x: above.minX, y: above.maxY),
            panelSize: CGSize(width: 200, height: 240),
            visibleFrame: visible
        )
        try expect(expandedAbove.maxY == above.maxY, "选区上方的浮层展开时也应保持上边缘不动")

        let constrainedAtBottom = OverlayPlacement.resizedFrame(
            anchoredTopLeft: CGPoint(x: below.minX, y: 100),
            panelSize: CGSize(width: 200, height: 240),
            visibleFrame: visible
        )
        try expect(constrainedAtBottom.maxY == 100, "屏幕底部空间不足时仍应保持上边缘不动")
        try expect(constrainedAtBottom.minY == 10, "屏幕底部空间不足时应限制窗口高度而不是越界")

        let secondary = CGRect(x: -1_280, y: -120, width: 1_280, height: 800)
        let clamped = OverlayPlacement.calculate(
            anchor: CGRect(x: -1_400, y: -100, width: 20, height: 20),
            panelSize: size,
            visibleFrame: secondary
        )
        try expect(
            clamped.minX >= secondary.minX + OverlayPlacement.edgeInset
                && clamped.maxX <= secondary.maxX - OverlayPlacement.edgeInset
                && clamped.minY >= secondary.minY + OverlayPlacement.edgeInset
                && clamped.maxY <= secondary.maxY - OverlayPlacement.edgeInset,
            "负坐标副屏上的浮层应完整留在可见区域"
        )
    }

    private static func verifyEmptyPinnedPersistence() throws {
        let suite = "ClipAll.OverlayVerification.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw OverlayStateVerificationError.failed("无法创建隔离 UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let initial = SettingsStore(defaults: defaults)
        try expect(initial.pinnedCapabilityIDs == [.search, .translate], "首次启动应固定搜索和翻译")
        _ = initial.setPinned(.search, isPinned: false)
        _ = initial.setPinned(.translate, isPinned: false)
        try expect(initial.pinnedCapabilityIDs.isEmpty, "用户应能取消全部固定能力")

        let reloaded = SettingsStore(defaults: defaults)
        try expect(reloaded.pinnedCapabilityIDs.isEmpty, "空固定列表重启后不应恢复默认值")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw OverlayStateVerificationError.failed(message) }
    }
}
