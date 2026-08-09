import Combine
import Foundation

enum SelectionOverlayPhase: Equatable {
    case ready
    case executing(CapabilityID)
    case result(CapabilityID, CapabilityResult)
    case translation(CapabilityID, TranslationRequest)
    case message(String)
    case failure(CapabilityID?, String)
}

struct PluginDiscoveryItem: Identifiable, Equatable, Sendable {
    var id: PluginID { plugin.id }

    let plugin: PluginDescriptor
    let preferredCapability: CapabilityDescriptor
}

struct PluginDiscoverySections: Equatable, Sendable {
    let matches: [PluginDiscoveryItem]
    let recent: [PluginDiscoveryItem]
}

@MainActor
final class SelectionOverlayStore: ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var context: SelectionContext?
    @Published private(set) var fixedCapabilities: [CapabilityDescriptor] = []
    @Published private(set) var recommendation: CapabilityMatch?
    @Published private(set) var rankedMatches: [CapabilityMatch] = []
    @Published private(set) var phase: SelectionOverlayPhase = .ready
    @Published private(set) var isMorePresented = false
    @Published var moreQuery = ""

    private let registry: CapabilityRegistry
    private let settings: SettingsStore
    private let configuration: PluginConfigurationStore
    private let clipboard: any ClipboardWriting
    private let textPaster: any TextPasting
    private let openAITranslation: OpenAICompatibleTranslationProvider
    private let featureExtractor: ContentFeatureExtractor
    private let router: CapabilityRouter
    private let discoveryModel: CapabilityDiscoveryModel

    private var executionTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?

    init(
        registry: CapabilityRegistry,
        settings: SettingsStore,
        configuration: PluginConfigurationStore,
        clipboard: any ClipboardWriting,
        textPaster: any TextPasting,
        openAITranslation: OpenAICompatibleTranslationProvider,
        featureExtractor: ContentFeatureExtractor = ContentFeatureExtractor(),
        router: CapabilityRouter = CapabilityRouter(),
        discoveryModel: CapabilityDiscoveryModel = CapabilityDiscoveryModel()
    ) {
        self.registry = registry
        self.settings = settings
        self.configuration = configuration
        self.clipboard = clipboard
        self.textPaster = textPaster
        self.openAITranslation = openAITranslation
        self.featureExtractor = featureExtractor
        self.router = router
        self.discoveryModel = discoveryModel
    }

    var currentContextID: UUID? { context?.id }

    var pluginNames: [PluginID: String] {
        Dictionary(uniqueKeysWithValues: registry.plugins.map { ($0.id, $0.name) })
    }

    var moreSections: CapabilityDiscoverySections {
        let pinnedIDs = Set(fixedCapabilities.map(\.id))
        let recommendationID = recommendation?.id
        let availableDescriptors = registry.descriptors.filter {
            !pinnedIDs.contains($0.id) && $0.id != recommendationID
        }
        let routed = rankedMatches.filter {
            !pinnedIDs.contains($0.id) && $0.id != recommendationID
        }
        return discoveryModel.sections(
            query: moreQuery,
            descriptors: availableDescriptors,
            routedMatches: routed,
            recentCapabilityIDs: settings.recentCapabilityIDs,
            pluginNames: pluginNames
        )
    }

    var morePluginSections: PluginDiscoverySections {
        let capabilitySections = moreSections
        let matches = pluginItems(from: capabilitySections.matches)
        let matchedPluginIDs = Set(matches.map(\.id))
        let recent = pluginItems(from: capabilitySections.recent).filter {
            !matchedPluginIDs.contains($0.id)
        }
        return PluginDiscoverySections(matches: matches, recent: recent)
    }

    func pluginName(for descriptor: CapabilityDescriptor) -> String {
        pluginNames[descriptor.pluginID] ?? descriptor.pluginID.rawValue
    }

    func execute(_ plugin: PluginDiscoveryItem) {
        execute(plugin.preferredCapability.id)
    }

    func present(_ context: SelectionContext) {
        executionTask?.cancel()
        feedbackTask?.cancel()
        self.context = context
        phase = .ready
        isMorePresented = false
        moreQuery = ""
        refreshRouting()
        isVisible = true
    }

    func dismiss() {
        executionTask?.cancel()
        feedbackTask?.cancel()
        executionTask = nil
        feedbackTask = nil
        isVisible = false
        context = nil
        fixedCapabilities = []
        recommendation = nil
        rankedMatches = []
        isMorePresented = false
        moreQuery = ""
        phase = .ready
    }

    func showMore() {
        guard context != nil else { return }
        if !moreQuery.isEmpty {
            moreQuery = ""
        }
        isMorePresented = true
    }

    func hideMore() {
        isMorePresented = false
        if !moreQuery.isEmpty {
            moreQuery = ""
        }
    }

    func copySelection() {
        guard let context else { return }
        if clipboard.write(context.text) {
            dismiss()
        } else {
            phase = .failure(nil, "无法写入剪贴板")
        }
    }

    func pasteClipboard() {
        guard context != nil else { return }
        if textPaster.paste() {
            dismiss()
        } else {
            phase = .failure(nil, "无法发送粘贴操作")
        }
    }

    func copyResultItem(_ item: CapabilityResultItem) {
        if clipboard.write(item.value) {
            dismiss()
        } else {
            phase = .failure(nil, "无法写入剪贴板")
        }
    }

    func execute(_ capabilityID: CapabilityID) {
        guard let context,
              let executor = registry.executor(for: capabilityID) else {
            phase = .failure(capabilityID, "能力当前不可用")
            return
        }

        switch executor.availability(for: context) {
        case .available:
            break
        case let .unavailable(reason):
            phase = .failure(capabilityID, reason)
            return
        }

        let contextID = context.id
        feedbackTask?.cancel()
        feedbackTask = nil
        isMorePresented = false
        moreQuery = ""
        phase = .executing(capabilityID)
        executionTask?.cancel()
        executionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let output = try await executor.execute(in: context)
                try Task.checkCancellation()
                guard self.context?.id == contextID else { return }
                if case let .translation(request) = output {
                    self.phase = .translation(capabilityID, request)
                    if request.providerID == .openAICompatible {
                        let result = try await self.openAITranslation.translate(request)
                        try Task.checkCancellation()
                        guard self.context?.id == contextID else { return }
                        self.settings.recordUse(of: capabilityID)
                        self.phase = .result(capabilityID, result)
                    }
                } else {
                    self.settings.recordUse(of: capabilityID)
                    self.apply(output, capabilityID: capabilityID, contextID: contextID)
                }
            } catch is CancellationError {
                return
            } catch CapabilityError.cancelled {
                return
            } catch {
                guard self.context?.id == contextID else { return }
                self.phase = .failure(
                    capabilityID,
                    (error as? LocalizedError)?.errorDescription ?? "能力执行失败"
                )
            }
        }
    }

    @discardableResult
    func applyTranslationResult(
        _ result: CapabilityResult,
        capabilityID: CapabilityID,
        contextID: UUID
    ) -> Bool {
        guard context?.id == contextID,
              case let .translation(activeCapabilityID, _) = phase,
              activeCapabilityID == capabilityID else { return false }
        phase = .result(capabilityID, result)
        settings.recordUse(of: capabilityID)
        return true
    }

    @discardableResult
    func failTranslation(
        _ message: String,
        capabilityID: CapabilityID,
        contextID: UUID
    ) -> Bool {
        guard context?.id == contextID,
              case let .translation(activeCapabilityID, _) = phase,
              activeCapabilityID == capabilityID else { return false }
        phase = .failure(capabilityID, message)
        return true
    }

    private func refreshRouting() {
        guard let context else { return }
        let targetLanguage = configuration.string(
            pluginID: .translation,
            fieldID: TranslationPlugin.targetLanguageFieldID,
            fallback: "zh-Hans"
        )
        let features = featureExtractor.extract(
            from: context.text,
            targetLanguageIdentifier: targetLanguage
        )
        let availableDescriptors = registry.descriptors.filter { descriptor in
            guard let executor = registry.executor(for: descriptor.id) else { return false }
            if case .available = executor.availability(for: context) { return true }
            return false
        }
        let pinnedIDs = Set(settings.pinnedCapabilityIDs)
        let routing = router.route(
            descriptors: availableDescriptors,
            features: features,
            sourceText: context.text,
            pinnedCapabilityIDs: pinnedIDs
        )
        fixedCapabilities = settings.pinnedCapabilityIDs.compactMap { id in
            availableDescriptors.first(where: { $0.id == id })
        }
        rankedMatches = routing.rankedMatches
        recommendation = routing.recommendation
    }

    private func pluginItems(from capabilities: [CapabilityDescriptor]) -> [PluginDiscoveryItem] {
        let capabilitiesByPlugin = Dictionary(grouping: capabilities, by: \.pluginID)
        var seenPluginIDs: Set<PluginID> = []

        return capabilities.compactMap { capability in
            let pluginID = capability.pluginID
            guard seenPluginIDs.insert(pluginID).inserted,
                  let plugin = registry.plugins.first(where: { $0.id == pluginID }),
                  let candidates = capabilitiesByPlugin[pluginID],
                  let preferredCapability = preferredCapability(from: candidates)
            else { return nil }

            return PluginDiscoveryItem(
                plugin: plugin,
                preferredCapability: preferredCapability
            )
        }
    }

    private func preferredCapability(
        from candidates: [CapabilityDescriptor]
    ) -> CapabilityDescriptor? {
        let candidateIDs = Set(candidates.map(\.id))
        if let routedID = rankedMatches.first(where: { candidateIDs.contains($0.id) })?.id,
           let routed = candidates.first(where: { $0.id == routedID }) {
            return routed
        }
        if let recentID = settings.recentCapabilityIDs.first(where: { candidateIDs.contains($0) }),
           let recent = candidates.first(where: { $0.id == recentID }) {
            return recent
        }
        return candidates.first
    }

    private func apply(
        _ output: CapabilityOutput,
        capabilityID: CapabilityID,
        contextID: UUID
    ) {
        guard context?.id == contextID else { return }
        switch output {
        case let .completed(message):
            showTransientMessage(message ?? "已完成")
        case let .result(result):
            phase = .result(capabilityID, result)
        case .external:
            showTransientMessage("已在浏览器中打开", dismissAfter: true)
        case let .translation(request):
            phase = .translation(capabilityID, request)
        }
    }

    private func showTransientMessage(_ message: String, dismissAfter: Bool = false) {
        guard let contextID = context?.id else { return }
        feedbackTask?.cancel()
        phase = .message(message)
        feedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard let self, self.context?.id == contextID else { return }
            if dismissAfter {
                self.dismiss()
            } else {
                self.phase = .ready
            }
        }
    }
}
