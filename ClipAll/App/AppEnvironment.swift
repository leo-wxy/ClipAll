import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class AppEnvironment: ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.wxy.ClipAll",
        category: "AppEnvironment"
    )

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
    private var startupTask: Task<Void, Never>?
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
        let textPaster = PasteService()
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
            textPaster: textPaster,
            openAITranslation: openAITranslation
        )
        let overlayCoordinator = SelectionOverlayCoordinator(store: overlayStore)
        let selectionCapture = SelectionCaptureService(
            isFallbackAllowed: { bundleIdentifier in
                settings.allowsSelectionFallback(for: bundleIdentifier)
            }
        )
        let selectionMonitor = SelectionMonitor(
            captureService: selectionCapture,
            shortcut: settings.globalShortcut,
            allowsAutomaticDisplay: { intent, bundleIdentifier in
                settings.allowsAutomaticDisplay(
                    for: intent,
                    bundleIdentifier: bundleIdentifier
                )
            },
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
        settings.$isDockIconVisible
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.synchronizeDockVisibility() }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didFinishLaunchingNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.synchronizeDockVisibility() }
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

        Task { @MainActor [weak self] in
            await self?.start()
        }
    }

    func start() async {
        if let startupTask {
            await startupTask.value
            return
        }
        guard !hasStarted else { return }

        // Keep one independent startup task so scene rebuilding cannot leave
        // monitoring permanently disabled.
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performStartup()
        }
        startupTask = task
        await task.value
    }

    private func performStartup() async {
        defer { startupTask = nil }

        Self.logger.notice("Application startup began")
        permissions.refresh()
        if !permissions.isTrusted, !settings.hasShownPermissionOnboarding {
            settings.hasShownPermissionOnboarding = true
            permissions.requestPermission()
        }

        // Base selection capture must not wait for plugin discovery or repair.
        // Copy/search/translation remain usable even when an external plugin is
        // slow or invalid.
        hasStarted = true
        synchronizeSelectionMonitoring()

        await pluginLifecycle.loadInstalled()
        if let bundledTimestampToolsURL {
            do {
                _ = try await pluginLifecycle.repairBundledPluginIfNeeded(
                    pluginID: .timestampTools,
                    from: bundledTimestampToolsURL
                )
            } catch {
                startupIssue = "无法更新随附的时间工具：\(error.localizedDescription)"
            }
        }
        settings.reconcileCapabilities(availableIDs: Set(registry.descriptors.map(\.id)))
        Self.logger.notice("Application startup completed")
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
            Self.logger.notice(
                "Selection monitoring disabled: started=\(self.hasStarted, privacy: .public), enabled=\(self.settings.isMonitoringEnabled, privacy: .public), trusted=\(self.permissions.isTrusted, privacy: .public)"
            )
            selectionMonitor.stop()
            overlayCoordinator.dismiss()
            return
        }
        Self.logger.notice("Selection monitoring requested")
        selectionMonitor.start()
    }

    private func synchronizeDockVisibility() {
        NSApplication.shared.setActivationPolicy(
            settings.isDockIconVisible ? .regular : .accessory
        )
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
