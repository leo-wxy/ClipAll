import Foundation

enum ContentKind: String, CaseIterable, Codable, Hashable, Sendable {
    case text
    case foreignLanguage
    case url
    case email
    case code
    case address
    case unixTimestampSeconds
    case unixTimestampMilliseconds
    case dateTime
}

enum CapabilityExecutionKind: String, Codable, Hashable, Sendable {
    case immediate
    case resultPanel
    case external
}

struct CapabilityRoutingRule: Codable, Hashable, Sendable {
    let contentKind: ContentKind
    let score: Int
    let reason: String
}

struct CapabilityDescriptor: Identifiable, Codable, Hashable, Sendable {
    let id: CapabilityID
    let pluginID: PluginID
    let name: String
    let symbolName: String
    let purpose: String
    let supportedContentKinds: Set<ContentKind>
    let examples: [String]
    let exclusions: [String]
    let executionKind: CapabilityExecutionKind
    let routingRules: [CapabilityRoutingRule]
}
