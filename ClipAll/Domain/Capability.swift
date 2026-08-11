import Foundation

enum CapabilityInputLimits {
    static let maximumTextBytes = 65_536
}

enum CapabilityAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
}

enum CapabilityExecutionPresentation: Equatable, Sendable {
    case overlay
    case external
}

enum CapabilityError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedInput(String)
    case invalidInput(String)
    case unavailable(String)
    case permissionRequired(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case let .unsupportedInput(message),
             let .invalidInput(message),
             let .unavailable(message),
             let .permissionRequired(message):
            message
        case .cancelled:
            "操作已取消"
        }
    }
}

@MainActor
protocol CapabilityExecuting: AnyObject {
    var descriptor: CapabilityDescriptor { get }
    var executionPresentation: CapabilityExecutionPresentation { get }

    func availability(for context: SelectionContext) -> CapabilityAvailability
    func execute(in context: SelectionContext) async throws -> CapabilityOutput
}

extension CapabilityExecuting {
    var executionPresentation: CapabilityExecutionPresentation { .overlay }

    func availability(for context: SelectionContext) -> CapabilityAvailability {
        context.normalizedText.isEmpty ? .unavailable(reason: "当前没有可处理的文字") : .available
    }
}
