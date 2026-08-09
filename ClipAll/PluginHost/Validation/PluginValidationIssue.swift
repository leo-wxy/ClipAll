import Foundation

struct PluginValidationIssue: Error, LocalizedError, Equatable, Sendable {
    let code: String
    let message: String
    let location: String?

    init(code: String, message: String, location: String? = nil) {
        self.code = code
        self.message = message
        self.location = location
    }

    var errorDescription: String? {
        if let location, !location.isEmpty {
            return "\(message)（\(location)）"
        }
        return message
    }
}
