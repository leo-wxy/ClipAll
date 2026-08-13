import CoreGraphics

enum SelectionFallbackPolicy: String, Equatable, Sendable {
    case disabled
    case rejectKnownNonText
    case enabled
}

enum SelectionAutomaticDisplayPolicy: String, CaseIterable, Codable, Hashable, Sendable {
    case followGlobal
    case dragOnly
    case disabled

    func allows(
        _ intent: PointerSelectionIntent,
        isDragEnabled: Bool,
        isMultiClickEnabled: Bool
    ) -> Bool {
        switch self {
        case .followGlobal:
            switch intent {
            case .drag, .shiftClick:
                isDragEnabled
            case .multiClick:
                isMultiClickEnabled
            }
        case .dragOnly:
            intent != .multiClick
        case .disabled:
            false
        }
    }
}

enum PointerSelectionIntent: String, Equatable, Sendable {
    case drag
    case multiClick
    case shiftClick

    var fallbackPolicy: SelectionFallbackPolicy {
        switch self {
        case .drag:
            .enabled
        case .multiClick:
            .rejectKnownNonText
        case .shiftClick:
            .disabled
        }
    }
}

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

    mutating func end(
        at location: CGPoint,
        clickCount: Int,
        isShiftPressed: Bool = false
    ) -> PointerSelectionIntent? {
        update(at: location)
        let intent: PointerSelectionIntent?
        if isShiftPressed {
            intent = .shiftClick
        } else if clickCount >= 2 {
            intent = .multiClick
        } else if exceededDragThreshold {
            intent = .drag
        } else {
            intent = nil
        }
        reset()
        return intent
    }

    mutating func reset() {
        startLocation = nil
        exceededDragThreshold = false
    }
}
