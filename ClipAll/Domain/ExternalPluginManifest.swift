import Foundation

struct ExternalPluginRuntimeManifest: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case javascriptCore
    }

    let kind: Kind
    let entry: String
}

struct ExternalPluginConfigurationFieldManifest: Codable, Equatable, Sendable {
    enum FieldType: String, Codable, Sendable {
        case choice
        case toggle
        case text
    }

    let id: String
    let title: String
    let summary: String?
    let type: FieldType
    let defaultValue: PluginConfigurationValue
    let options: [PluginConfigurationOption]?
    let placeholder: String?
    let visibleWhen: PluginConfigurationCondition?
}

struct ExternalCapabilityManifest: Codable, Equatable, Sendable {
    let id: CapabilityID
    let name: String
    let symbolName: String
    let purpose: String
    let supportedContentKinds: [ContentKind]
    let examples: [String]
    let exclusions: [String]
    let executionKind: CapabilityExecutionKind
    let handler: String
    let routingRules: [CapabilityRoutingRule]
}

struct ExternalPluginManifest: Codable, Equatable, Sendable {
    let manifestVersion: Int
    let id: PluginID
    let name: String
    let version: String
    let minimumClipAllVersion: String
    let summary: String
    let symbolName: String
    let runtime: ExternalPluginRuntimeManifest
    let configuration: [ExternalPluginConfigurationFieldManifest]
    let capabilities: [ExternalCapabilityManifest]
}

struct ExternalCapabilityDefinition: Equatable, Sendable {
    let descriptor: CapabilityDescriptor
    let handler: String
}

struct ExternalPluginDefinition: Equatable, Sendable {
    let descriptor: PluginDescriptor
    let runtimeEntry: String
    let capabilities: [ExternalCapabilityDefinition]
}

struct ValidatedExternalPluginPackage: Sendable {
    let packageURL: URL
    let definition: ExternalPluginDefinition
    let script: String
    let fingerprint: String
}
