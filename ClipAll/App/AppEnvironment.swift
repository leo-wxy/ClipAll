import Combine
import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    let settings: SettingsStore
    let configuration: PluginConfigurationStore
    let secrets: PluginSecretStore
    let registry: CapabilityRegistry
    let permissions: AccessibilityPermissionService
    let pluginLifecycle: PluginLifecycleController
    let runnerClient: PluginRunnerClient
    let bundledTimestampToolsURL: URL?
    let selectionCapture: SelectionCaptureService
    let selectionMonitor: SelectionMonitor
    let overlayStore: SelectionOverlayStore
    let overlayCoordinator: SelectionOverlayCoordinator

    @Published private(set) var startupIssue: String?

    private var hasStarted = false
    private var cancellables: Set<AnyCancellable> = []

    init(
        defaults: UserDefaults = .standard,
        applicationSupportURL: URL? = nil,
        runnerURL: URL? = nil,
        bundledTimestampToolsURL: URL? = nil
    ) {
        let settings = SettingsStore(defaults: defaults)
        let configuration = PluginConfigurationStore(defaults: defaults)
        let secrets = PluginSecretStore()
        let registry = CapabilityRegistry()
        let permissions = AccessibilityPermissionService()
        let runnerClient = PluginRunnerClient(runnerURL: runnerURL ?? Self.resolveRunnerURL())
        let clipboard = ClipboardService()
        let openAITranslation = OpenAICompatibleTranslationProvider(secrets: secrets)
        let developmentStore = DevelopmentPluginStore(defaults: defaults)
        let pluginRoot = (applicationSupportURL ?? Self.defaultApplicationSupportURL())
            .appendingPathComponent("Plugins", isDirectory: true)
        let installationStore = PluginInstallationStore(rootDirectory: pluginRoot)

        self.settings = settings
        self.configuration = configuration
        self.secrets = secrets
        self.registry = registry
        self.permissions = permissions
        self.runnerClient = runnerClient
        self.bundledTimestampToolsURL = bundledTimestampToolsURL
            ?? Self.resolveBundledTimestampToolsURL()
        pluginLifecycle = PluginLifecycleController(
            installationStore: installationStore,
            registry: registry,
            settings: settings,
            configurationStore: configuration,
            runnerClient: runnerClient,
            developmentStore: developmentStore
        )

        do {
            let search = SearchPlugin(
                configurationStore: configuration,
                browser: BrowserService()
            )
            let translation = TranslationPlugin(configurationStore: configuration)
            for plugin in [search as any ClipAllPlugin, translation as any ClipAllPlugin] {
                configuration.register(plugin.descriptor)
                try registry.register(plugin)
            }
        } catch {
            startupIssue = error.localizedDescription
        }

        let overlayStore = SelectionOverlayStore(
            registry: registry,
            settings: settings,
            configuration: configuration,
            clipboard: clipboard,
            openAITranslation: openAITranslation
        )
        let overlayCoordinator = SelectionOverlayCoordinator(store: overlayStore)
        let selectionCapture = SelectionCaptureService()
        let selectionMonitor = SelectionMonitor(
            captureService: selectionCapture,
            shortcut: settings.globalShortcut,
            onSelection: { [weak overlayCoordinator] context in
                overlayCoordinator?.present(context)
            },
            onPermissionRequired: { [weak permissions] in
                permissions?.refresh()
            },
            onSelectionInvalidated: { [weak overlayCoordinator] in
                overlayCoordinator?.dismiss()
            }
        )
        self.overlayStore = overlayStore
        self.overlayCoordinator = overlayCoordinator
        self.selectionCapture = selectionCapture
        self.selectionMonitor = selectionMonitor

        settings.$isMonitoringEnabled
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.synchronizeSelectionMonitoring() }
            }
            .store(in: &cancellables)
        settings.$globalShortcut
            .removeDuplicates()
            .sink { [weak selectionMonitor] shortcut in
                Task { @MainActor in selectionMonitor?.updateShortcut(shortcut) }
            }
            .store(in: &cancellables)
        permissions.$isTrusted
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.synchronizeSelectionMonitoring() }
            }
            .store(in: &cancellables)
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await pluginLifecycle.loadInstalled()
        settings.reconcileCapabilities(availableIDs: Set(registry.descriptors.map(\.id)))
        permissions.refresh()
        if !permissions.isTrusted, !settings.hasShownPermissionOnboarding {
            settings.hasShownPermissionOnboarding = true
            permissions.requestPermission()
        }
        synchronizeSelectionMonitoring()
    }

    func captureSelectionNow() {
        permissions.refresh()
        synchronizeSelectionMonitoring()
        selectionMonitor.captureNow()
    }

    private func synchronizeSelectionMonitoring() {
        guard hasStarted,
              settings.isMonitoringEnabled,
              permissions.isTrusted else {
            selectionMonitor.stop()
            overlayCoordinator.dismiss()
            return
        }
        selectionMonitor.start()
    }

    private static func defaultApplicationSupportURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.wxy.ClipAll", isDirectory: true)
    }

    private static func resolveRunnerURL() -> URL {
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "ClipAllPluginRunner") {
            return bundled
        }
        if let executable = Bundle.main.executableURL {
            return executable.deletingLastPathComponent()
                .appendingPathComponent("ClipAllPluginRunner", isDirectory: false)
        }
        return URL(fileURLWithPath: "/missing/ClipAllPluginRunner")
    }

    private static func resolveBundledTimestampToolsURL() -> URL? {
        if let bundled = Bundle.main.url(
            forResource: "TimestampTools",
            withExtension: "clipallplugin"
        ) {
            return bundled
        }
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let candidate = resourceURL.appendingPathComponent(
            "TimestampTools.clipallplugin",
            isDirectory: true
        )
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }
}
