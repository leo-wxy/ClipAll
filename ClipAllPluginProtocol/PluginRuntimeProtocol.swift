import Foundation

public enum PluginRuntimeLimits {
    public static let protocolVersion = 2
    public static let maximumRequestBytes = 1_500_000
    public static let maximumResponseBytes = 256_000
    public static let maximumSelectionBytes = 65_536
    public static let maximumLogEntries = 100
    public static let maximumLogEntryCharacters = 500
    public static let maximumResultItems = 12
    public static let maximumResultStringCharacters = 32_768
}

public enum PluginRuntimeConfigurationValue: Hashable, Sendable {
    case string(String)
    case bool(Bool)
}

extension PluginRuntimeConfigurationValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.typeMismatch(
                PluginRuntimeConfigurationValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "插件配置值只支持字符串或布尔值"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        }
    }
}

public struct PluginRuntimeInput: Codable, Equatable, Sendable {
    public let pluginID: String
    public let text: String
    public let configuration: [String: PluginRuntimeConfigurationValue]

    public init(
        pluginID: String,
        text: String,
        configuration: [String: PluginRuntimeConfigurationValue]
    ) {
        self.pluginID = pluginID
        self.text = text
        self.configuration = configuration
    }
}

public struct PluginRuntimeRequest: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let script: String
    public let sourceName: String
    public let handler: String
    public let input: PluginRuntimeInput
    public let capturesLogs: Bool

    public init(
        protocolVersion: Int = PluginRuntimeLimits.protocolVersion,
        script: String,
        sourceName: String,
        handler: String,
        input: PluginRuntimeInput,
        capturesLogs: Bool
    ) {
        self.protocolVersion = protocolVersion
        self.script = script
        self.sourceName = sourceName
        self.handler = handler
        self.input = input
        self.capturesLogs = capturesLogs
    }
}

public enum PluginRuntimeResultValueStyle: String, Codable, Hashable, Sendable {
    case body
    case monospaced
}

public struct PluginRuntimeResultItem: Codable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let value: String
    public let annotation: String?
    public let style: PluginRuntimeResultValueStyle

    public init(
        id: String,
        label: String,
        value: String,
        annotation: String? = nil,
        style: PluginRuntimeResultValueStyle = .body
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.annotation = annotation
        self.style = style
    }
}

public struct PluginRuntimeResult: Codable, Equatable, Sendable {
    public let title: String
    public let subtitle: String?
    public let items: [PluginRuntimeResultItem]

    public init(title: String, subtitle: String? = nil, items: [PluginRuntimeResultItem]) {
        self.title = title
        self.subtitle = subtitle
        self.items = items
    }
}

public struct PluginRuntimeErrorPayload: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let sourceLocation: String?

    public init(code: String, message: String, sourceLocation: String? = nil) {
        self.code = code
        self.message = message
        self.sourceLocation = sourceLocation
    }
}

public enum PluginRuntimeResponseStatus: String, Codable, Sendable {
    case success
    case failure
}

public struct PluginRuntimeResponse: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let status: PluginRuntimeResponseStatus
    public let output: PluginRuntimeResult?
    public let error: PluginRuntimeErrorPayload?
    public let logs: [String]

    public init(
        protocolVersion: Int = PluginRuntimeLimits.protocolVersion,
        status: PluginRuntimeResponseStatus,
        output: PluginRuntimeResult?,
        error: PluginRuntimeErrorPayload?,
        logs: [String]
    ) {
        self.protocolVersion = protocolVersion
        self.status = status
        self.output = output
        self.error = error
        self.logs = logs
    }

    public static func success(_ output: PluginRuntimeResult, logs: [String] = []) -> Self {
        Self(status: .success, output: output, error: nil, logs: logs)
    }

    public static func failure(_ error: PluginRuntimeErrorPayload, logs: [String] = []) -> Self {
        Self(status: .failure, output: nil, error: error, logs: logs)
    }
}
