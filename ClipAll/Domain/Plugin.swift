import Foundation

enum PluginSource: String, Codable, Hashable, Sendable {
    case builtIn
    case installed
    case development

    var isExternal: Bool { self != .builtIn }
}

struct PluginDescriptor: Identifiable, Codable, Hashable, Sendable {
    let id: PluginID
    let name: String
    let summary: String
    let symbolName: String
    let version: String
    let source: PluginSource
    let configurationFields: [PluginConfigurationField]

    init(
        id: PluginID,
        name: String,
        summary: String,
        symbolName: String,
        version: String,
        source: PluginSource,
        configurationFields: [PluginConfigurationField] = []
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.symbolName = symbolName
        self.version = version
        self.source = source
        self.configurationFields = configurationFields
    }

}

@MainActor
protocol ClipAllPlugin: AnyObject {
    var descriptor: PluginDescriptor { get }
    var capabilities: [any CapabilityExecuting] { get }
}
