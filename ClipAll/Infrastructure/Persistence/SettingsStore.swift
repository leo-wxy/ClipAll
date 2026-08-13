import Combine
import Foundation

struct GlobalShortcutConfiguration: Codable, Equatable, Sendable {
    let keyCode: UInt16
    let modifierFlagsRawValue: UInt

    static let standard = GlobalShortcutConfiguration(
        keyCode: 49,
        modifierFlagsRawValue: 1 << 18 | 1 << 19
    )
}

@MainActor
final class SettingsStore: ObservableObject {
    static let maximumPinnedCapabilities = 4
    static let maximumRecentCapabilities = 8

    private enum Key {
        static let monitoringEnabled = "selectionMonitoringEnabled"
        static let menuBarIconVisible = "menuBarIconVisible"
        static let dockIconVisible = "dockIconVisible"
        static let selectionFallbackEnabled = "selectionFallbackEnabled"
        static let selectionFallbackExcludedBundleIdentifiers =
            "selectionFallbackExcludedBundleIdentifiers.v1"
        static let dragSelectionEnabled = "dragSelectionEnabled"
        static let multiClickSelectionEnabled = "multiClickSelectionEnabled"
        static let selectionAutomaticDisplayPolicies =
            "selectionAutomaticDisplayPolicies.v1"
        static let pinnedCapabilityIDs = "pinnedCapabilityIDs"
        static let recentCapabilityIDs = "recentCapabilityIDs"
        static let globalShortcut = "globalShortcut"
        static let permissionOnboardingShown = "permissionOnboardingShown"
        static let developerModeEnabled = "developerModeEnabled"
        static let pluginEnabledStates = "pluginEnabledStates.v1"
    }

    private let defaults: UserDefaults

    @Published var isMonitoringEnabled: Bool {
        didSet { defaults.set(isMonitoringEnabled, forKey: Key.monitoringEnabled) }
    }

    @Published private(set) var isMenuBarIconVisible: Bool {
        didSet { defaults.set(isMenuBarIconVisible, forKey: Key.menuBarIconVisible) }
    }

    @Published private(set) var isDockIconVisible: Bool {
        didSet { defaults.set(isDockIconVisible, forKey: Key.dockIconVisible) }
    }

    @Published var isSelectionFallbackEnabled: Bool {
        didSet { defaults.set(isSelectionFallbackEnabled, forKey: Key.selectionFallbackEnabled) }
    }

    @Published private(set) var selectionFallbackExcludedBundleIdentifiers: [String] {
        didSet {
            defaults.set(
                selectionFallbackExcludedBundleIdentifiers,
                forKey: Key.selectionFallbackExcludedBundleIdentifiers
            )
        }
    }

    @Published var isDragSelectionEnabled: Bool {
        didSet { defaults.set(isDragSelectionEnabled, forKey: Key.dragSelectionEnabled) }
    }

    @Published var isMultiClickSelectionEnabled: Bool {
        didSet { defaults.set(isMultiClickSelectionEnabled, forKey: Key.multiClickSelectionEnabled) }
    }

    @Published private(set) var selectionAutomaticDisplayPolicies:
        [String: SelectionAutomaticDisplayPolicy] {
        didSet {
            persist(
                selectionAutomaticDisplayPolicies.mapValues(\.rawValue),
                key: Key.selectionAutomaticDisplayPolicies
            )
        }
    }

    @Published private(set) var pinnedCapabilityIDs: [CapabilityID] {
        didSet { persist(ids: pinnedCapabilityIDs, key: Key.pinnedCapabilityIDs) }
    }

    @Published private(set) var recentCapabilityIDs: [CapabilityID] {
        didSet { persist(ids: recentCapabilityIDs, key: Key.recentCapabilityIDs) }
    }

    @Published var globalShortcut: GlobalShortcutConfiguration {
        didSet { persist(globalShortcut, key: Key.globalShortcut) }
    }

    @Published var hasShownPermissionOnboarding: Bool {
        didSet { defaults.set(hasShownPermissionOnboarding, forKey: Key.permissionOnboardingShown) }
    }

    @Published var isDeveloperModeEnabled: Bool {
        didSet { defaults.set(isDeveloperModeEnabled, forKey: Key.developerModeEnabled) }
    }

    @Published private(set) var pluginEnabledStates: [PluginID: Bool] {
        didSet { persistPluginEnabledStates() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Key.monitoringEnabled) == nil {
            isMonitoringEnabled = true
        } else {
            isMonitoringEnabled = defaults.bool(forKey: Key.monitoringEnabled)
        }

        let storedMenuBarVisibility = defaults.object(forKey: Key.menuBarIconVisible) == nil
            || defaults.bool(forKey: Key.menuBarIconVisible)
        let storedDockVisibility = defaults.object(forKey: Key.dockIconVisible) == nil
            || defaults.bool(forKey: Key.dockIconVisible)
        if !storedMenuBarVisibility, !storedDockVisibility {
            isMenuBarIconVisible = true
            isDockIconVisible = false
            defaults.set(true, forKey: Key.menuBarIconVisible)
        } else {
            isMenuBarIconVisible = storedMenuBarVisibility
            isDockIconVisible = storedDockVisibility
        }

        if defaults.object(forKey: Key.selectionFallbackEnabled) == nil {
            isSelectionFallbackEnabled = true
        } else {
            isSelectionFallbackEnabled = defaults.bool(forKey: Key.selectionFallbackEnabled)
        }
        selectionFallbackExcludedBundleIdentifiers = Array(Set(
            (defaults.stringArray(forKey: Key.selectionFallbackExcludedBundleIdentifiers) ?? [])
                .compactMap(Self.normalizedBundleIdentifier)
        )).sorted()
        isDragSelectionEnabled = defaults.object(forKey: Key.dragSelectionEnabled) == nil
            || defaults.bool(forKey: Key.dragSelectionEnabled)
        isMultiClickSelectionEnabled = defaults.object(forKey: Key.multiClickSelectionEnabled) == nil
            || defaults.bool(forKey: Key.multiClickSelectionEnabled)
        selectionAutomaticDisplayPolicies = Self.sanitizeAutomaticDisplayPolicies(
            Self.load(
                [String: String].self,
                defaults: defaults,
                key: Key.selectionAutomaticDisplayPolicies
            ) ?? [:]
        )

        if defaults.object(forKey: Key.pinnedCapabilityIDs) == nil {
            pinnedCapabilityIDs = [.search, .translate]
        } else {
            pinnedCapabilityIDs = Self.sanitizePinned(
                Self.loadIDs(defaults: defaults, key: Key.pinnedCapabilityIDs)
            )
        }
        recentCapabilityIDs = Array(
            Self.loadIDs(defaults: defaults, key: Key.recentCapabilityIDs)
                .uniqued()
                .prefix(Self.maximumRecentCapabilities)
        )
        globalShortcut = Self.load(
            GlobalShortcutConfiguration.self,
            defaults: defaults,
            key: Key.globalShortcut
        ) ?? .standard
        hasShownPermissionOnboarding = defaults.bool(forKey: Key.permissionOnboardingShown)
        isDeveloperModeEnabled = defaults.bool(forKey: Key.developerModeEnabled)
        let storedPluginStates = Self.load(
            [String: Bool].self,
            defaults: defaults,
            key: Key.pluginEnabledStates
        ) ?? [:]
        pluginEnabledStates = Dictionary(
            uniqueKeysWithValues: storedPluginStates.map { (PluginID($0.key), $0.value) }
        )
    }

    @discardableResult
    func setMenuBarIconVisible(_ isVisible: Bool) -> Bool {
        guard isVisible || isDockIconVisible else { return false }
        isMenuBarIconVisible = isVisible
        return true
    }

    @discardableResult
    func setDockIconVisible(_ isVisible: Bool) -> Bool {
        guard isVisible || isMenuBarIconVisible else { return false }
        isDockIconVisible = isVisible
        return true
    }

    func setSelectionFallbackExcluded(_ bundleIdentifier: String, isExcluded: Bool) {
        guard let normalized = Self.normalizedBundleIdentifier(bundleIdentifier) else { return }
        var updated = Set(selectionFallbackExcludedBundleIdentifiers)
        if isExcluded {
            updated.insert(normalized)
        } else {
            updated.remove(normalized)
        }
        selectionFallbackExcludedBundleIdentifiers = updated.sorted()
    }

    func allowsSelectionFallback(for bundleIdentifier: String?) -> Bool {
        guard isSelectionFallbackEnabled, let bundleIdentifier else { return false }
        return !selectionFallbackExcludedBundleIdentifiers.contains(bundleIdentifier)
    }

    var selectionApplicationBundleIdentifiers: [String] {
        Array(
            Set(selectionAutomaticDisplayPolicies.keys)
                .union(selectionFallbackExcludedBundleIdentifiers)
        ).sorted()
    }

    func automaticDisplayPolicy(
        for bundleIdentifier: String?
    ) -> SelectionAutomaticDisplayPolicy {
        guard let bundleIdentifier else { return .followGlobal }
        return selectionAutomaticDisplayPolicies[bundleIdentifier] ?? .followGlobal
    }

    func allowsAutomaticDisplay(
        for intent: PointerSelectionIntent,
        bundleIdentifier: String?
    ) -> Bool {
        automaticDisplayPolicy(for: bundleIdentifier).allows(
            intent,
            isDragEnabled: isDragSelectionEnabled,
            isMultiClickEnabled: isMultiClickSelectionEnabled
        )
    }

    func addSelectionApplication(_ bundleIdentifier: String) {
        let normalized = Self.normalizedBundleIdentifier(bundleIdentifier)
        guard let normalized,
              selectionAutomaticDisplayPolicies[normalized] == nil else { return }
        selectionAutomaticDisplayPolicies[normalized] = .followGlobal
    }

    func setAutomaticDisplayPolicy(
        _ policy: SelectionAutomaticDisplayPolicy,
        for bundleIdentifier: String
    ) {
        guard let normalized = Self.normalizedBundleIdentifier(bundleIdentifier) else { return }
        selectionAutomaticDisplayPolicies[normalized] = policy
    }

    func removeSelectionApplication(_ bundleIdentifier: String) {
        let normalized = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        selectionAutomaticDisplayPolicies.removeValue(forKey: normalized)
        setSelectionFallbackExcluded(normalized, isExcluded: false)
    }

    @discardableResult
    func setPinned(_ id: CapabilityID, isPinned: Bool) -> Bool {
        if isPinned {
            guard !pinnedCapabilityIDs.contains(id),
                  pinnedCapabilityIDs.count < Self.maximumPinnedCapabilities else {
                return false
            }
            pinnedCapabilityIDs.append(id)
        } else {
            pinnedCapabilityIDs.removeAll(where: { $0 == id })
        }
        return true
    }

    func movePinned(fromOffsets: IndexSet, toOffset: Int) {
        var updated = pinnedCapabilityIDs
        let moving = fromOffsets.sorted().map { updated[$0] }
        for index in fromOffsets.sorted(by: >) {
            updated.remove(at: index)
        }

        let removedBeforeDestination = fromOffsets.filter { $0 < toOffset }.count
        let destination = max(0, min(updated.count, toOffset - removedBeforeDestination))
        updated.insert(contentsOf: moving, at: destination)
        pinnedCapabilityIDs = Self.sanitizePinned(updated)
    }

    func movePinned(_ id: CapabilityID, by offset: Int) {
        guard let source = pinnedCapabilityIDs.firstIndex(of: id) else { return }
        let destination = max(0, min(pinnedCapabilityIDs.count - 1, source + offset))
        guard source != destination else { return }
        var updated = pinnedCapabilityIDs
        let item = updated.remove(at: source)
        updated.insert(item, at: destination)
        pinnedCapabilityIDs = updated
    }

    func recordUse(of id: CapabilityID) {
        var updated = recentCapabilityIDs.filter { $0 != id }
        updated.insert(id, at: 0)
        recentCapabilityIDs = Array(updated.prefix(Self.maximumRecentCapabilities))
    }

    func reconcileCapabilities(availableIDs: Set<CapabilityID>) {
        pinnedCapabilityIDs = pinnedCapabilityIDs.filter(availableIDs.contains)
        recentCapabilityIDs = recentCapabilityIDs.filter(availableIDs.contains)
    }

    func removeCapabilityReferences(_ ids: Set<CapabilityID>) {
        guard !ids.isEmpty else { return }
        pinnedCapabilityIDs.removeAll(where: ids.contains)
        recentCapabilityIDs.removeAll(where: ids.contains)
    }

    func isPluginEnabled(_ id: PluginID) -> Bool {
        pluginEnabledStates[id] ?? true
    }

    func setPlugin(_ id: PluginID, isEnabled: Bool) {
        pluginEnabledStates[id] = isEnabled
    }

    func removePluginState(_ id: PluginID) {
        pluginEnabledStates.removeValue(forKey: id)
    }

    private func persist(ids: [CapabilityID], key: String) {
        defaults.set(ids.map(\.rawValue), forKey: key)
    }

    private func persist<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func persistPluginEnabledStates() {
        let payload = Dictionary(
            uniqueKeysWithValues: pluginEnabledStates.map { ($0.key.rawValue, $0.value) }
        )
        persist(payload, key: Key.pluginEnabledStates)
    }

    private static func normalizedBundleIdentifier(_ bundleIdentifier: String) -> String? {
        let normalized = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized != Bundle.main.bundleIdentifier else { return nil }
        return normalized
    }

    private static func loadIDs(defaults: UserDefaults, key: String) -> [CapabilityID] {
        (defaults.stringArray(forKey: key) ?? []).map { CapabilityID($0) }
    }

    private static func load<Value: Decodable>(
        _ type: Value.Type,
        defaults: UserDefaults,
        key: String
    ) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func sanitizePinned(_ ids: [CapabilityID]) -> [CapabilityID] {
        Array(ids.uniqued().prefix(maximumPinnedCapabilities))
    }

    private static func sanitizeAutomaticDisplayPolicies(
        _ stored: [String: String]
    ) -> [String: SelectionAutomaticDisplayPolicy] {
        var sanitized: [String: SelectionAutomaticDisplayPolicy] = [:]
        for (bundleIdentifier, rawPolicy) in stored {
            let normalized = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty,
                  normalized != Bundle.main.bundleIdentifier,
                  let policy = SelectionAutomaticDisplayPolicy(rawValue: rawPolicy) else {
                continue
            }
            sanitized[normalized] = policy
        }
        return sanitized
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
