import CoreGraphics

struct PointerSelectionGesture: Sendable {
    static let minimumDragDistance: CGFloat = 4

    private var startLocation: CGPoint?
    private var exceededDragThreshold = false

    mutating func begin(at location: CGPoint) {
        startLocation = location
        exceededDragThreshold = false
    }

    mutating func update(at location: CGPoint) {
        guard let startLocation else { return }
        let distance = hypot(location.x - startLocation.x, location.y - startLocation.y)
        if distance >= Self.minimumDragDistance {
            exceededDragThreshold = true
        }
    }

    mutating func end(at location: CGPoint, clickCount: Int) -> Bool {
        update(at: location)
        let shouldCapture = exceededDragThreshold || clickCount >= 2
        reset()
        return shouldCapture
    }

    mutating func reset() {
        startLocation = nil
        exceededDragThreshold = false
    }
}
