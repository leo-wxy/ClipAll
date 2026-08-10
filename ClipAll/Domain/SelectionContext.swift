import CoreGraphics
import Foundation

struct SelectionContext: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let sourceBundleIdentifier: String?
    let selectionBounds: CGRect?
    let triggerLocation: CGPoint

    var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init?(
        id: UUID = UUID(),
        text: String,
        sourceBundleIdentifier: String? = nil,
        selectionBounds: CGRect? = nil,
        triggerLocation: CGPoint = .zero
    ) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        self.id = id
        self.text = text
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.selectionBounds = selectionBounds
        self.triggerLocation = triggerLocation
    }
}
