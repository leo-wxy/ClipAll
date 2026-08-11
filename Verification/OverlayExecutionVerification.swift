import Foundation

private enum OverlayExecutionVerificationError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

@MainActor
private final class OverlayExecutionVerificationSecrets: PluginSecretProviding {
    func secret(pluginID: PluginID, fieldID: String) throws -> String? { nil }
}

@MainActor
private final class VerificationExternalCapability: CapabilityExecuting {
    let descriptor = CapabilityDescriptor(
        id: "verification.external",
        pluginID: "verification.plugin",
        name: "外部验证",
        symbolName: "safari",
        purpose: "验证外部能力关闭时序",
        supportedContentKinds: [.text],
        examples: [],
        routingRules: []
    )
    let executionPresentation = CapabilityExecutionPresentation.external

    var isOverlayVisible: @MainActor () -> Bool = { false }
    private(set) var executionCount = 0
    private(set) var wasVisibleWhenExecuted: Bool?

    func execute(in context: SelectionContext) async throws -> CapabilityOutput {
        executionCount += 1
        wasVisibleWhenExecuted = isOverlayVisible()
        return .external
    }
}

@main
@MainActor
private enum OverlayExecutionVerification {
    static func main() async throws {
        let suite = "ClipAll.OverlayExecutionVerification.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw OverlayExecutionVerificationError.failed("无法创建隔离 UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let registry = CapabilityRegistry()
        let executor = VerificationExternalCapability()
        try registry.register(executor)
        let settings = SettingsStore(defaults: defaults)
        let configuration = PluginConfigurationStore(defaults: defaults)
        let store = SelectionOverlayStore(
            registry: registry,
            settings: settings,
            configuration: configuration,
            clipboard: ClipboardService(),
            textPaster: PasteService(),
            openAITranslation: OpenAICompatibleTranslationProvider(
                secrets: OverlayExecutionVerificationSecrets()
            )
        )
        executor.isOverlayVisible = { [weak store] in store?.isVisible ?? false }

        guard let context = SelectionContext(text: "external overlay verification") else {
            throw OverlayExecutionVerificationError.failed("无法创建验证选区")
        }
        store.present(context)
        store.execute(executor.descriptor.id)

        try expect(!store.isVisible, "外部能力必须在 execute 返回前同步关闭浮窗")
        try expect(store.phase == .ready, "外部能力不得进入 executing 或 message 阶段")

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .milliseconds(100))
        while executor.executionCount == 0, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }

        try expect(executor.executionCount == 1, "外部能力应执行一次")
        try expect(executor.wasVisibleWhenExecuted == false, "外部副作用必须发生在浮窗隐藏之后")
        try expect(
            settings.recentCapabilityIDs.first == executor.descriptor.id,
            "外部能力成功后应记录最近使用"
        )

        print("Overlay execution verification passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw OverlayExecutionVerificationError.failed(message) }
    }
}
