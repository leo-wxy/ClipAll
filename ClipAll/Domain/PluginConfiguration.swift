import Foundation

enum PluginConfigurationValue: Equatable, Hashable, Sendable {
    case string(String)
    case bool(Bool)

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }
}

extension PluginConfigurationValue: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.typeMismatch(
                PluginConfigurationValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "配置值只支持字符串或布尔值"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        }
    }
}

struct PluginConfigurationOption: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: String
    let title: String
}

enum PluginConfigurationFieldKind: Codable, Equatable, Hashable, Sendable {
    case choice(options: [PluginConfigurationOption])
    case toggle
    case text(placeholder: String?)
    case secret(placeholder: String?)

    var isSecret: Bool {
        if case .secret = self { return true }
        return false
    }

    func accepts(_ value: PluginConfigurationValue) -> Bool {
        switch (self, value) {
        case let (.choice(options), .string(selectedID)):
            options.contains(where: { $0.id == selectedID })
        case (.toggle, .bool):
            true
        case (.text, .string), (.secret, .string):
            true
        default:
            false
        }
    }
}

struct PluginConfigurationCondition: Codable, Equatable, Hashable, Sendable {
    let fieldID: String
    let equals: PluginConfigurationValue
}

struct PluginConfigurationField: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: String
    let title: String
    let summary: String?
    let kind: PluginConfigurationFieldKind
    let defaultValue: PluginConfigurationValue
    let visibleWhen: PluginConfigurationCondition?

    init(
        id: String,
        title: String,
        summary: String? = nil,
        kind: PluginConfigurationFieldKind,
        defaultValue: PluginConfigurationValue,
        visibleWhen: PluginConfigurationCondition? = nil
    ) {
        precondition(kind.accepts(defaultValue), "配置默认值必须匹配字段类型")
        self.id = id
        self.title = title
        self.summary = summary
        self.kind = kind
        self.defaultValue = defaultValue
        self.visibleWhen = visibleWhen
    }
}
