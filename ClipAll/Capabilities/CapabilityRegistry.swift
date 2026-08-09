import Combine
import Foundation

@MainActor
final class CapabilityRegistry: ObservableObject {
    enum RegistryError: Error, LocalizedError, Equatable {
        case duplicateCapability(CapabilityID)
        case duplicatePlugin(PluginID)
        case capabilityPluginMismatch(capabilityID: CapabilityID, pluginID: PluginID)

        var errorDescription: String? {
            switch self {
            case let .duplicateCapability(id):
                "能力标识重复：\(id.rawValue)"
            case let .duplicatePlugin(id):
                "插件标识重复：\(id.rawValue)"
            case let .capabilityPluginMismatch(capabilityID, pluginID):
                "能力 \(capabilityID.rawValue) 不属于插件 \(pluginID.rawValue)"
            }
        }
    }

    @Published private(set) var descriptors: [CapabilityDescriptor] = []
    @Published private(set) var plugins: [PluginDescriptor] = []

    private var executorsByID: [CapabilityID: any CapabilityExecuting] = [:]
    private var capabilityIDsByPlugin: [PluginID: Set<CapabilityID>] = [:]

    func register(_ capability: any CapabilityExecuting) throws {
        let id = capability.descriptor.id
        guard executorsByID[id] == nil else {
            throw RegistryError.duplicateCapability(id)
        }

        executorsByID[id] = capability
        capabilityIDsByPlugin[capability.descriptor.pluginID, default: []].insert(id)
        descriptors.append(capability.descriptor)
        descriptors.sort { $0.id < $1.id }
    }

    func register(_ plugin: any ClipAllPlugin) throws {
        try register(descriptor: plugin.descriptor, capabilities: plugin.capabilities)
    }

    func register(
        descriptor plugin: PluginDescriptor,
        capabilities newCapabilities: [any CapabilityExecuting]
    ) throws {
        guard !plugins.contains(where: { $0.id == plugin.id }) else {
            throw RegistryError.duplicatePlugin(plugin.id)
        }

        var incomingIDs: Set<CapabilityID> = []
        for capability in newCapabilities {
            let descriptor = capability.descriptor
            guard descriptor.pluginID == plugin.id else {
                throw RegistryError.capabilityPluginMismatch(
                    capabilityID: descriptor.id,
                    pluginID: plugin.id
                )
            }
            guard executorsByID[descriptor.id] == nil,
                  incomingIDs.insert(descriptor.id).inserted else {
                throw RegistryError.duplicateCapability(descriptor.id)
            }
        }

        var updatedExecutors = executorsByID
        for capability in newCapabilities {
            updatedExecutors[capability.descriptor.id] = capability
        }
        executorsByID = updatedExecutors
        capabilityIDsByPlugin[plugin.id] = incomingIDs
        descriptors = (descriptors + newCapabilities.map(\.descriptor)).sorted { $0.id < $1.id }
        plugins = (plugins + [plugin]).sorted { $0.id < $1.id }
    }

    @discardableResult
    func unregister(pluginID: PluginID) -> Set<CapabilityID> {
        let ids = capabilityIDsByPlugin.removeValue(forKey: pluginID) ?? []
        guard !ids.isEmpty || plugins.contains(where: { $0.id == pluginID }) else {
            return []
        }

        for id in ids {
            executorsByID.removeValue(forKey: id)
        }
        descriptors = descriptors.filter { !ids.contains($0.id) }
        plugins = plugins.filter { $0.id != pluginID }
        return ids
    }

    func executor(for id: CapabilityID) -> (any CapabilityExecuting)? {
        executorsByID[id]
    }

    func descriptor(for id: CapabilityID) -> CapabilityDescriptor? {
        descriptors.first(where: { $0.id == id })
    }

    func plugin(for id: PluginID) -> PluginDescriptor? {
        plugins.first(where: { $0.id == id })
    }
}
