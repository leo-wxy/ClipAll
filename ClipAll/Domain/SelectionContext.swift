import CoreGraphics
import Foundation

struct SelectionContext: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let sourceBundleIdentifier: String?
    let sourceApplicationName: String?
    let selectionBounds: CGRect?
    let triggerLocation: CGPoint
    let createdAt: Date

    var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init?(
        id: UUID = UUID(),
        text: String,
        sourceBundleIdentifier: String? = nil,
        sourceApplicationName: String? = nil,
        selectionBounds: CGRect? = nil,
        triggerLocation: CGPoint = .zero,
        createdAt: Date = Date()
    ) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        self.id = id
        self.text = text
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.sourceApplicationName = sourceApplicationName
        self.selectionBounds = selectionBounds
        self.triggerLocation = triggerLocation
        self.createdAt = createdAt
    }
}
