import Combine
import Foundation

enum ManagedPluginState: String, Sendable {
    case enabled
    case disabled
}

struct ManagedPlugin: Identifiable, Sendable {
    var id: PluginID { package.definition.descriptor.id }
    let package: ValidatedExternalPluginPackage
    var state: ManagedPluginState
}

struct InvalidInstalledPlugin: Identifiable, Sendable {
    var id: String { packageURL.path }
    let packageURL: URL
    let issue: PluginValidationIssue
}

enum PluginLifecycleError: Error, LocalizedError, Equatable, Sendable {
    case pluginNotManaged(PluginID)
    case pluginConflict(String)
    case developerModeDisabled
    case operationUnavailable(String)

    var errorDescription: String? {
        switch self {
        case let .pluginNotManaged(id):
            "找不到插件：\(id.rawValue)"
        case let .pluginConflict(message):
            message
        case .developerModeDisabled:
            "请先在设置中开启开发者模式"
        case let .operationUnavailable(message):
            message
        }
    }
}

@MainActor
final class PluginLifecycleController: ObservableObject {
    @Published private(set) var plugins: [ManagedPlugin] = []
    @Published private(set) var invalidPlugins: [InvalidInstalledPlugin] = []
    @Published private(set) var isLoading = false

    private let installationStore: PluginInstallationStore
    private let registry: CapabilityRegistry
    private let settings: SettingsStore
    private let configurationStore: PluginConfigurationStore
    private let runnerClient: PluginRunnerClient
    private let packageValidator: PluginPackageValidator
    private let developmentStore: DevelopmentPluginStore
    private let deletePluginSecrets: (PluginID) throws -> Void
    private var isMutationInProgress = false

    init(
        installationStore: PluginInstallationStore,
        registry: CapabilityRegistry,
        settings: SettingsStore,
        configurationStore: PluginConfigurationStore,
        runnerClient: PluginRunnerClient,
        packageValidator: PluginPackageValidator = PluginPackageValidator(),
        developmentStore: DevelopmentPluginStore,
        deletePluginSecrets: @escaping (PluginID) throws -> Void
    ) {
        self.installationStore = installationStore
        self.registry = registry
        self.settings = settings
        self.configurationStore = configurationStore
        self.runnerClient = runnerClient
        self.packageValidator = packageValidator
        self.developmentStore = developmentStore
        self.deletePluginSecrets = deletePluginSecrets
    }

    func loadInstalled() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let results = try await installationStore.loadInstalled()
            var loaded: [ManagedPlugin] = []
            var invalid: [InvalidInstalledPlugin] = []

            for result in results {
                switch result {
                case let .valid(package):
                    configurationStore.register(package.definition.descriptor)
                    let enabled = settings.isPluginEnabled(package.definition.descriptor.id)
                    if enabled {
                        do {
                            try activate(package)
                            loaded.append(ManagedPlugin(package: package, state: .enabled))
                        } catch {
                            invalid.append(InvalidInstalledPlugin(
                                packageURL: package.packageURL,
                                issue: PluginValidationIssue(
                                    code: "registry_conflict",
                                    message: error.localizedDescription,
                                    location: package.definition.descriptor.id.rawValue
                                )
                            ))
                        }
                    } else {
                        loaded.append(ManagedPlugin(package: package, state: .disabled))
                    }
                case let .invalid(packageURL, issue):
                    invalid.append(InvalidInstalledPlugin(packageURL: packageURL, issue: issue))
                }
            }

            plugins = loaded.sorted { $0.package.definition.descriptor.name < $1.package.definition.descriptor.name }
            invalidPlugins = invalid.sorted { $0.packageURL.lastPathComponent < $1.packageURL.lastPathComponent }
            if settings.isDeveloperModeEnabled {
                loadDevelopmentReferences()
            }
        } catch {
            invalidPlugins = [InvalidInstalledPlugin(
                packageURL: URL(fileURLWithPath: "Installed"),
                issue: PluginValidationIssue(code: "package_read", message: error.localizedDescription)
            )]
        }
    }

    func prepareImport(from sourceURL: URL) async throws -> PreparedPluginImport {
        try await installationStore.prepareImport(from: sourceURL)
    }

    func discardImport(_ prepared: PreparedPluginImport) async {
        await installationStore.discard(prepared)
    }

    func repairBundledPluginIfNeeded(
        pluginID: PluginID,
        from bundledURL: URL
    ) async throws -> Bool {
        guard pluginID == .timestampTools else { return false }

        let installedName = "\(pluginID.rawValue).clipallplugin"
        guard invalidPlugins.contains(where: {
            $0.packageURL.lastPathComponent == installedName
                && ["incompatible_host", "manifest_version"].contains($0.issue.code)
        }) else {
            return false
        }

        let prepared = try await prepareImport(from: bundledURL)
        guard prepared.package.definition.descriptor.id == pluginID else {
            await discardImport(prepared)
            throw PluginLifecycleError.pluginConflict(
                "随 App 提供的示例插件 ID 与待修复插件不一致"
            )
        }
        guard prepared.replacesExistingPlugin else {
            await discardImport(prepared)
            return false
        }

        do {
            try await install(prepared, replacingExisting: true)
            return true
        } catch {
            await discardImport(prepared)
            throw error
        }
    }

    func install(
        _ prepared: PreparedPluginImport,
        replacingExisting: Bool
    ) async throws {
        try beginMutation()
        defer { isMutationInProgress = false }
        try preflightRegistryConflicts(
            prepared.package,
            replacingPluginID: replacingExisting ? prepared.package.definition.descriptor.id : nil
        )
        let pluginID = prepared.package.definition.descriptor.id
        let previous = plugins.first(where: { $0.id == pluginID })
        let shouldEnable = previous.map { $0.state == .enabled } ?? true
        let previousConfigurationValues = configurationStore.values[pluginID]
        let previousCapabilityIDs = Set(
            previous?.package.definition.capabilities.map(\.descriptor.id) ?? []
        )
        let pending = try await installationStore.commit(
            prepared,
            replacingExisting: replacingExisting
        )
        let installed = pending.package
        let installedCapabilityIDs = Set(installed.definition.capabilities.map(\.descriptor.id))

        var activatedNewPackage = false
        do {
            if previous?.state == .enabled {
                _ = registry.unregister(pluginID: pluginID)
            }
            configurationStore.register(installed.definition.descriptor)
            if shouldEnable {
                try activate(installed)
                activatedNewPackage = true
            }
            try await installationStore.finalize(pending)
        } catch {
            let originalError = error
            if activatedNewPackage {
                _ = registry.unregister(pluginID: pluginID)
            }

            var restorationFailed = false
            do {
                try await installationStore.rollback(pending)
            } catch {
                restorationFailed = true
            }

            if let previous {
                configurationStore.register(previous.package.definition.descriptor)
                if previous.state == .enabled {
                    do {
                        try activate(previous.package)
                    } catch {
                        restorationFailed = true
                    }
                }
            } else {
                configurationStore.unregister(pluginID: pluginID)
            }
            configurationStore.restoreValues(
                previousConfigurationValues,
                pluginID: pluginID
            )

            if restorationFailed {
                throw PluginInstallationError.transactionFailed
            }
            throw originalError
        }

        settings.removeCapabilityReferences(previousCapabilityIDs.subtracting(installedCapabilityIDs))
        settings.setPlugin(pluginID, isEnabled: shouldEnable)
        upsert(ManagedPlugin(
            package: installed,
            state: shouldEnable ? .enabled : .disabled
        ))
        let installedName = "\(pluginID.rawValue).clipallplugin"
        invalidPlugins.removeAll { $0.packageURL.lastPathComponent == installedName }
    }

    func setEnabled(_ enabled: Bool, pluginID: PluginID) async throws {
        try beginMutation()
        defer { isMutationInProgress = false }
        guard let index = plugins.firstIndex(where: { $0.id == pluginID }) else {
            throw PluginLifecycleError.pluginNotManaged(pluginID)
        }
        guard (plugins[index].state == .enabled) != enabled else { return }
        guard plugins[index].package.definition.descriptor.source == .installed else {
            throw PluginLifecycleError.operationUnavailable("开发插件请使用重新载入或移除引用")
        }

        if enabled {
            let package = try await installationStore.validateInstalled(pluginID: pluginID)
            guard let refreshedIndex = plugins.firstIndex(where: { $0.id == pluginID }) else {
                throw PluginLifecycleError.pluginNotManaged(pluginID)
            }
            guard plugins[refreshedIndex].package.definition.descriptor.source == .installed else {
                throw PluginLifecycleError.operationUnavailable("开发插件请使用重新载入或移除引用")
            }
            guard plugins[refreshedIndex].state == .disabled else { return }
            configurationStore.register(package.definition.descriptor)
            try preflightRegistryConflicts(package, replacingPluginID: pluginID)
            try activate(package)
            plugins[refreshedIndex] = ManagedPlugin(package: package, state: .enabled)
        } else {
            let removedIDs = registry.unregister(pluginID: pluginID)
            settings.removeCapabilityReferences(removedIDs)
            plugins[index].state = .disabled
        }
        settings.setPlugin(pluginID, isEnabled: enabled)
        sortPlugins()
    }

    func uninstall(pluginID: PluginID) async throws {
        try beginMutation()
        defer { isMutationInProgress = false }
        guard let existing = plugins.first(where: { $0.id == pluginID }) else {
            throw PluginLifecycleError.pluginNotManaged(pluginID)
        }
        guard existing.package.definition.descriptor.source == .installed else {
            throw PluginLifecycleError.operationUnavailable("开发插件只能移除引用，不会删除源码")
        }

        try deletePluginSecrets(pluginID)

        let wasEnabled = existing.state == .enabled
        let removedIDs = wasEnabled ? registry.unregister(pluginID: pluginID) : []

        do {
            try await installationStore.uninstall(pluginID: pluginID)
        } catch {
            if wasEnabled { try? activate(existing.package) }
            throw error
        }

        settings.removeCapabilityReferences(removedIDs)
        plugins.removeAll(where: { $0.id == pluginID })
        settings.removePluginState(pluginID)
        configurationStore.removeData(pluginID: pluginID)
    }

    func plugin(id: PluginID) -> ManagedPlugin? {
        plugins.first(where: { $0.id == id })
    }

    func loadDevelopment(from sourceURL: URL) throws {
        guard !isMutationInProgress else {
            throw PluginLifecycleError.operationUnavailable("另一个插件操作正在进行")
        }
        guard settings.isDeveloperModeEnabled else {
            throw PluginLifecycleError.developerModeDisabled
        }

        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
        let package = try packageValidator.validate(packageURL: sourceURL, source: .development)
        let pluginID = package.definition.descriptor.id
        let previous = plugins.first(where: { $0.id == pluginID })
        if let previous, previous.package.definition.descriptor.source != .development {
            throw PluginLifecycleError.pluginConflict("同 ID 的已安装插件正在使用，请先卸载")
        }

        try preflightRegistryConflicts(package, replacingPluginID: previous?.id)
        if previous?.state == .enabled { _ = registry.unregister(pluginID: pluginID) }
        configurationStore.register(package.definition.descriptor)
        do {
            try activate(package)
        } catch {
            if let previous, previous.state == .enabled { try? activate(previous.package) }
            throw error
        }

        do {
            try developmentStore.save(pluginID: pluginID, url: sourceURL)
        } catch {
            _ = registry.unregister(pluginID: pluginID)
            if let previous {
                configurationStore.register(previous.package.definition.descriptor)
                if previous.state == .enabled { try? activate(previous.package) }
            } else {
                configurationStore.unregister(pluginID: pluginID)
            }
            throw error
        }
        let previousIDs = Set(previous?.package.definition.capabilities.map(\.descriptor.id) ?? [])
        let replacementIDs = Set(package.definition.capabilities.map(\.descriptor.id))
        settings.removeCapabilityReferences(previousIDs.subtracting(replacementIDs))
        upsert(ManagedPlugin(package: package, state: .enabled))
    }

    func reloadDevelopment(pluginID: PluginID) throws {
        guard !isMutationInProgress else {
            throw PluginLifecycleError.operationUnavailable("另一个插件操作正在进行")
        }
        guard settings.isDeveloperModeEnabled else {
            throw PluginLifecycleError.developerModeDisabled
        }
        guard let previous = plugins.first(where: { $0.id == pluginID }),
              previous.package.definition.descriptor.source == .development else {
            throw PluginLifecycleError.operationUnavailable("该插件不是开发引用")
        }

        let reference = try developmentStore.resolve(pluginID: pluginID)
        let accessed = reference.url.startAccessingSecurityScopedResource()
        defer { if accessed { reference.url.stopAccessingSecurityScopedResource() } }
        let package = try packageValidator.validate(packageURL: reference.url, source: .development)
        guard package.definition.descriptor.id == pluginID else {
            throw PluginLifecycleError.pluginConflict("重新载入不能改变插件 ID")
        }
        try preflightRegistryConflicts(package, replacingPluginID: pluginID)

        _ = registry.unregister(pluginID: pluginID)
        configurationStore.register(package.definition.descriptor)
        do {
            try activate(package)
            let previousIDs = Set(previous.package.definition.capabilities.map(\.descriptor.id))
            let replacementIDs = Set(package.definition.capabilities.map(\.descriptor.id))
            settings.removeCapabilityReferences(previousIDs.subtracting(replacementIDs))
            upsert(ManagedPlugin(package: package, state: .enabled))
        } catch {
            configurationStore.register(previous.package.definition.descriptor)
            try? activate(previous.package)
            throw error
        }
    }

    func removeDevelopmentReference(pluginID: PluginID) throws {
        guard !isMutationInProgress else {
            throw PluginLifecycleError.operationUnavailable("另一个插件操作正在进行")
        }
        guard let plugin = plugins.first(where: { $0.id == pluginID }),
              plugin.package.definition.descriptor.source == .development else {
            throw PluginLifecycleError.operationUnavailable("该插件不是开发引用")
        }
        let removedIDs = registry.unregister(pluginID: pluginID)
        settings.removeCapabilityReferences(removedIDs)
        configurationStore.unregister(pluginID: pluginID)
        developmentStore.remove(pluginID: pluginID)
        plugins.removeAll(where: { $0.id == pluginID })
    }

    func setDeveloperModeEnabled(_ enabled: Bool) {
        guard !isMutationInProgress else { return }
        guard settings.isDeveloperModeEnabled != enabled else { return }
        settings.isDeveloperModeEnabled = enabled
        if enabled {
            loadDevelopmentReferences()
        } else {
            let developmentIDs = plugins
                .filter { $0.package.definition.descriptor.source == .development }
                .map(\.id)
            for pluginID in developmentIDs {
                let removedIDs = registry.unregister(pluginID: pluginID)
                settings.removeCapabilityReferences(removedIDs)
                configurationStore.unregister(pluginID: pluginID)
            }
            plugins.removeAll { $0.package.definition.descriptor.source == .development }
        }
    }

    func makeDebugSession(pluginID: PluginID) throws -> PluginDebugSession {
        guard settings.isDeveloperModeEnabled else {
            throw PluginLifecycleError.developerModeDisabled
        }
        guard let package = plugins.first(where: { $0.id == pluginID })?.package else {
            throw PluginLifecycleError.pluginNotManaged(pluginID)
        }
        return PluginDebugSession(
            package: package,
            configurationStore: configurationStore,
            runnerClient: runnerClient
        )
    }

    private func activate(_ package: ValidatedExternalPluginPackage) throws {
        let executors: [any CapabilityExecuting] = package.definition.capabilities.map { definition in
            ExternalPluginExecutor(
                definition: definition,
                script: package.script,
                sourceName: package.definition.runtimeEntry,
                configurationStore: configurationStore,
                runnerClient: runnerClient
            )
        }
        try registry.register(
            descriptor: package.definition.descriptor,
            capabilities: executors
        )
    }

    private func loadDevelopmentReferences() {
        for result in developmentStore.resolveAll() {
            switch result {
            case let .success(reference):
                do {
                    let accessed = reference.url.startAccessingSecurityScopedResource()
                    defer { if accessed { reference.url.stopAccessingSecurityScopedResource() } }
                    let package = try packageValidator.validate(
                        packageURL: reference.url,
                        source: .development
                    )
                    guard package.definition.descriptor.id == reference.id else {
                        throw PluginLifecycleError.pluginConflict(
                            "开发引用中的插件 ID 已改变：\(reference.id.rawValue) → \(package.definition.descriptor.id.rawValue)"
                        )
                    }
                    guard plugins.allSatisfy({ $0.id != package.definition.descriptor.id }) else {
                        throw PluginLifecycleError.pluginConflict("同 ID 的插件已经载入")
                    }
                    try preflightRegistryConflicts(package, replacingPluginID: nil)
                    configurationStore.register(package.definition.descriptor)
                    try activate(package)
                    plugins.append(ManagedPlugin(package: package, state: .enabled))
                } catch {
                    invalidPlugins.append(InvalidInstalledPlugin(
                        packageURL: reference.url,
                        issue: PluginValidationIssue(
                            code: "development_load",
                            message: error.localizedDescription,
                            location: reference.id.rawValue
                        )
                    ))
                }
            case let .failure(error):
                invalidPlugins.append(InvalidInstalledPlugin(
                    packageURL: URL(fileURLWithPath: "Development"),
                    issue: PluginValidationIssue(
                        code: "development_reference",
                        message: error.localizedDescription
                    )
                ))
            }
        }
        sortPlugins()
    }

    private func preflightRegistryConflicts(
        _ package: ValidatedExternalPluginPackage,
        replacingPluginID: PluginID?
    ) throws {
        let incoming = Set(package.definition.capabilities.map(\.descriptor.id))
        let conflicts = registry.descriptors.filter { descriptor in
            incoming.contains(descriptor.id) && descriptor.pluginID != replacingPluginID
        }
        if let conflict = conflicts.first {
            throw PluginLifecycleError.pluginConflict("能力标识已被占用：\(conflict.id.rawValue)")
        }

        if registry.plugins.contains(where: {
            $0.id == package.definition.descriptor.id && $0.id != replacingPluginID
        }) {
            throw PluginLifecycleError.pluginConflict(
                "插件标识已被占用：\(package.definition.descriptor.id.rawValue)"
            )
        }
    }

    private func beginMutation() throws {
        guard !isMutationInProgress else {
            throw PluginLifecycleError.operationUnavailable("另一个插件操作正在进行")
        }
        isMutationInProgress = true
    }

    private func upsert(_ plugin: ManagedPlugin) {
        plugins.removeAll(where: { $0.id == plugin.id })
        plugins.append(plugin)
        sortPlugins()
    }

    private func sortPlugins() {
        plugins.sort { $0.package.definition.descriptor.name < $1.package.definition.descriptor.name }
    }
}
