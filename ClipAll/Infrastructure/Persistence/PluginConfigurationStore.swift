import Combine
import Foundation

@MainActor
final class PluginConfigurationStore: ObservableObject {
    enum StoreError: Error, LocalizedError, Equatable {
        case unknownField(pluginID: PluginID, fieldID: String)
        case invalidValue(fieldID: String)
        case secretRequiresKeychain(fieldID: String)

        var errorDescription: String? {
            switch self {
            case let .unknownField(pluginID, fieldID):
                "插件 \(pluginID.rawValue) 没有配置项 \(fieldID)"
            case let .invalidValue(fieldID):
                "配置项 \(fieldID) 的值无效"
            case let .secretRequiresKeychain(fieldID):
                "配置项 \(fieldID) 必须存入 Keychain"
            }
        }
    }

    private static let storageKey = "pluginConfigurationValues.v1"

    @Published private(set) var values: [PluginID: [String: PluginConfigurationValue]]

    private let defaults: UserDefaults
    private var fieldsByPlugin: [PluginID: [String: PluginConfigurationField]] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        values = Self.load(defaults: defaults)
    }

    func register(_ descriptor: PluginDescriptor) {
        let fields = Dictionary(uniqueKeysWithValues: descriptor.configurationFields.map { ($0.id, $0) })
        precondition(fields.count == descriptor.configurationFields.count, "同一插件内配置字段 ID 不能重复")
        fieldsByPlugin[descriptor.id] = fields

        var pluginValues = values[descriptor.id] ?? [:]
        var didChange = false
        for field in descriptor.configurationFields where !field.kind.isSecret {
            if let current = pluginValues[field.id], field.kind.accepts(current) {
                continue
            }
            pluginValues[field.id] = field.defaultValue
            didChange = true
        }

        if didChange || values[descriptor.id] == nil {
            values[descriptor.id] = pluginValues
            persist()
        }
    }

    func value(pluginID: PluginID, fieldID: String) -> PluginConfigurationValue? {
        if let value = values[pluginID]?[fieldID] {
            return value
        }
        return fieldsByPlugin[pluginID]?[fieldID]?.defaultValue
    }

    func fields(pluginID: PluginID) -> [PluginConfigurationField] {
        Array(fieldsByPlugin[pluginID]?.values ?? [:].values).sorted { $0.id < $1.id }
    }

    func resolvedValues(pluginID: PluginID) -> [String: PluginConfigurationValue] {
        guard let fields = fieldsByPlugin[pluginID] else { return [:] }
        return fields.values.reduce(into: [:]) { result, field in
            guard !field.kind.isSecret else { return }
            result[field.id] = value(pluginID: pluginID, fieldID: field.id) ?? field.defaultValue
        }
    }

    func string(pluginID: PluginID, fieldID: String, fallback: String = "") -> String {
        value(pluginID: pluginID, fieldID: fieldID)?.stringValue ?? fallback
    }

    func bool(pluginID: PluginID, fieldID: String, fallback: Bool = false) -> Bool {
        value(pluginID: pluginID, fieldID: fieldID)?.boolValue ?? fallback
    }

    func set(_ value: PluginConfigurationValue, pluginID: PluginID, fieldID: String) throws {
        guard let field = fieldsByPlugin[pluginID]?[fieldID] else {
            throw StoreError.unknownField(pluginID: pluginID, fieldID: fieldID)
        }
        guard !field.kind.isSecret else {
            throw StoreError.secretRequiresKeychain(fieldID: fieldID)
        }
        guard field.kind.accepts(value) else {
            throw StoreError.invalidValue(fieldID: fieldID)
        }

        values[pluginID, default: [:]][fieldID] = value
        persist()
    }

    func isVisible(_ field: PluginConfigurationField, pluginID: PluginID) -> Bool {
        guard let condition = field.visibleWhen else { return true }
        return value(pluginID: pluginID, fieldID: condition.fieldID) == condition.equals
    }

    func reset(pluginID: PluginID) {
        guard let fields = fieldsByPlugin[pluginID] else {
            values.removeValue(forKey: pluginID)
            persist()
            return
        }

        values[pluginID] = fields.values.reduce(into: [:]) { result, field in
            guard !field.kind.isSecret else { return }
            result[field.id] = field.defaultValue
        }
        persist()
    }

    func unregister(pluginID: PluginID) {
        fieldsByPlugin.removeValue(forKey: pluginID)
    }

    func removeData(pluginID: PluginID) {
        fieldsByPlugin.removeValue(forKey: pluginID)
        values.removeValue(forKey: pluginID)
        persist()
    }

    private func persist() {
        let payload = Dictionary(uniqueKeysWithValues: values.map { pluginID, fields in
            (pluginID.rawValue, fields)
        })
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func load(defaults: UserDefaults) -> [PluginID: [String: PluginConfigurationValue]] {
        guard let data = defaults.data(forKey: storageKey),
              let payload = try? JSONDecoder().decode(
                  [String: [String: PluginConfigurationValue]].self,
                  from: data
              ) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: payload.map { (PluginID($0.key), $0.value) })
    }
}
