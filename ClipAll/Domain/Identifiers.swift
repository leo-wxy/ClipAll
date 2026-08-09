import Foundation

struct CapabilityID: RawRepresentable, Hashable, Codable, Sendable, Comparable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: StringLiteralType) {
        rawValue = value
    }

    static func < (lhs: CapabilityID, rhs: CapabilityID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension CapabilityID {
    static let search: CapabilityID = "builtin.search"
    static let translate: CapabilityID = "builtin.translate"
    static let timestampToDate: CapabilityID = "com.clipall.plugin.timestamp-tools.timestamp-to-date"
    static let dateToTimestamp: CapabilityID = "com.clipall.plugin.timestamp-tools.date-to-timestamp"
}

struct PluginID: RawRepresentable, Hashable, Codable, Sendable, Comparable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: StringLiteralType) {
        rawValue = value
    }

    static func < (lhs: PluginID, rhs: PluginID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension PluginID {
    static let system: PluginID = "builtin.system"
    static let search: PluginID = "builtin.search"
    static let translation: PluginID = "builtin.translation"
    static let timestampTools: PluginID = "com.clipall.plugin.timestamp-tools"
}

struct SearchProviderID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: StringLiteralType) {
        rawValue = value
    }
}

extension SearchProviderID {
    static let google: SearchProviderID = "google"
    static let bing: SearchProviderID = "bing"
    static let duckDuckGo: SearchProviderID = "duckduckgo"
}
