import Foundation

enum TranslationProviderID: String, Codable, Hashable, Sendable {
    case system
    case openAICompatible = "openai-compatible"
}

enum TranslationConfigurationKey {
    static let provider = "provider"
    static let targetLanguage = "targetLanguage"
    static let endpoint = "endpoint"
    static let model = "model"
    static let apiKey = "apiKey"
}

struct TranslationRequest: Equatable, Sendable {
    let text: String
    let providerID: TranslationProviderID
    let targetLanguageIdentifier: String
    let endpoint: String?
    let model: String?
}
