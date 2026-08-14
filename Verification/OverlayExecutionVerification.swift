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
        try verifyConfigurationStore(configuration)

        print("Overlay execution verification passed")
    }

    private static func verifyConfigurationStore(_ store: PluginConfigurationStore) throws {
        let pluginID: PluginID = "verification.configuration"
        let otherPluginID: PluginID = "verification.configuration.other"
        let timeZone = PluginConfigurationField(
            id: "timeZone",
            title: "时区",
            kind: .choice(options: [
                .init(id: "system", title: "系统"),
                .init(id: "utc", title: "UTC"),
            ]),
            defaultValue: .string("system")
        )
        let enabled = PluginConfigurationField(
            id: "enabled",
            title: "启用",
            kind: .toggle,
            defaultValue: .bool(true)
        )
        let secret = PluginConfigurationField(
            id: "apiKey",
            title: "API Key",
            kind: .secret(placeholder: nil),
            defaultValue: .string("")
        )
        store.register(descriptor(id: pluginID, fields: [timeZone, enabled, secret]))
        try expect(
            store.resolvedValues(pluginID: pluginID) == [
                "timeZone": .string("system"),
                "enabled": .bool(true),
            ],
            "resolved 配置应合并默认值并过滤 secret"
        )

        try store.set(.string("utc"), pluginID: pluginID, fieldID: "timeZone")
        try expect(store.bool(pluginID: pluginID, fieldID: "enabled"), "单字段更新不得覆盖 sibling")
        try expectStoreError(.invalidValue(fieldID: "enabled")) {
            try store.set(.string("true"), pluginID: pluginID, fieldID: "enabled")
        }
        try expectStoreError(.unknownField(pluginID: pluginID, fieldID: "missing")) {
            try store.set(.string("value"), pluginID: pluginID, fieldID: "missing")
        }
        try expectStoreError(.secretRequiresKeychain(fieldID: "apiKey")) {
            try store.set(.string("secret"), pluginID: pluginID, fieldID: "apiKey")
        }

        store.register(descriptor(id: otherPluginID, fields: [enabled]))
        try store.set(.bool(false), pluginID: otherPluginID, fieldID: "enabled")
        try expect(store.bool(pluginID: pluginID, fieldID: "enabled"), "pluginID 之间必须隔离")

        store.unregister(pluginID: pluginID)
        store.register(descriptor(id: pluginID, fields: [enabled]))
        try expect(
            store.resolvedValues(pluginID: pluginID) == ["enabled": .bool(true)],
            "重载或升级应保留现有字段并过滤 stale 字段"
        )

        store.removeData(pluginID: pluginID)
        try expect(store.resolvedValues(pluginID: pluginID).isEmpty, "remove 应清空插件配置")
        try expect(store.value(pluginID: pluginID, fieldID: "enabled") == nil, "remove 不得留下持久值")

        try expect(
            PluginSecretStore.account("verification.configuration.token", belongsTo: pluginID),
            "Keychain account 应匹配精确 pluginID 前缀"
        )
        try expect(
            !PluginSecretStore.account("verification.configuration-other.token", belongsTo: pluginID),
            "相似 pluginID 不得被误删"
        )
    }

    private static func descriptor(
        id: PluginID,
        fields: [PluginConfigurationField]
    ) -> PluginDescriptor {
        PluginDescriptor(
            id: id,
            name: "验证插件",
            summary: "配置验证",
            symbolName: "gearshape",
            version: "1.0.0",
            source: .development,
            configurationFields: fields
        )
    }

    private static func expectStoreError(
        _ expected: PluginConfigurationStore.StoreError,
        operation: () throws -> Void
    ) throws {
        do {
            try operation()
            throw OverlayExecutionVerificationError.failed("期望配置写入失败：\(expected)")
        } catch let error as PluginConfigurationStore.StoreError {
            try expect(error == expected, "配置写入错误不匹配：\(error)")
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw OverlayExecutionVerificationError.failed(message) }
    }
}
