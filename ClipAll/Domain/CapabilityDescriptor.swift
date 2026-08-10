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

struct CapabilityInputMatcher: Codable, Hashable, Sendable {
    enum MatcherType: String, Codable, Hashable, Sendable {
        case dateFormat
    }

    let type: MatcherType
    let formats: [String]
}

struct CapabilityRoutingRule: Codable, Hashable, Sendable {
    let contentKind: ContentKind
    let score: Int
    let reason: String
    let inputMatchers: [CapabilityInputMatcher]

    init(
        contentKind: ContentKind,
        score: Int,
        reason: String,
        inputMatchers: [CapabilityInputMatcher] = []
    ) {
        self.contentKind = contentKind
        self.score = score
        self.reason = reason
        self.inputMatchers = inputMatchers
    }

    private enum CodingKeys: String, CodingKey {
        case contentKind
        case score
        case reason
        case inputMatchers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contentKind = try container.decode(ContentKind.self, forKey: .contentKind)
        score = try container.decode(Int.self, forKey: .score)
        reason = try container.decode(String.self, forKey: .reason)
        if container.contains(.inputMatchers) {
            inputMatchers = try container.decode(
                [CapabilityInputMatcher].self,
                forKey: .inputMatchers
            )
        } else {
            inputMatchers = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contentKind, forKey: .contentKind)
        try container.encode(score, forKey: .score)
        try container.encode(reason, forKey: .reason)
        if !inputMatchers.isEmpty {
            try container.encode(inputMatchers, forKey: .inputMatchers)
        }
    }
}

struct CapabilityDescriptor: Identifiable, Codable, Hashable, Sendable {
    let id: CapabilityID
    let pluginID: PluginID
    let name: String
    let symbolName: String
    let purpose: String
    let supportedContentKinds: Set<ContentKind>
    let examples: [String]
    let routingRules: [CapabilityRoutingRule]
}
