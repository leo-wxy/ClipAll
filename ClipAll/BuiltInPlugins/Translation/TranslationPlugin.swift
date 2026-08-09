import Foundation

@MainActor
final class TranslationCapability: CapabilityExecuting {
    let descriptor = CapabilityDescriptor(
        id: .translate,
        pluginID: .translation,
        name: "翻译",
        symbolName: "character.book.closed",
        purpose: "使用系统设备端翻译或显式配置的 AI 提供方翻译文字。",
        supportedContentKinds: [.text, .foreignLanguage],
        examples: ["A good tool should shorten the distance from reading to action."],
        exclusions: ["纯数字", "空白内容"],
        executionKind: .resultPanel,
        routingRules: [
            CapabilityRoutingRule(contentKind: .foreignLanguage, score: 78, reason: "检测到与目标语言不同的文字"),
            CapabilityRoutingRule(contentKind: .text, score: 18, reason: "可翻译普通文本"),
        ]
    )

    private let configurationStore: PluginConfigurationStore

    init(configurationStore: PluginConfigurationStore) {
        self.configurationStore = configurationStore
    }

    func availability(for context: SelectionContext) -> CapabilityAvailability {
        guard !context.normalizedText.isEmpty else {
            return .unavailable(reason: "当前没有可翻译的文字")
        }
        guard context.normalizedText.utf8.count <= CapabilityInputLimits.maximumTextBytes else {
            return .unavailable(reason: "所选文字超过翻译处理上限")
        }
        return .available
    }

    func execute(in context: SelectionContext) async throws -> CapabilityOutput {
        guard case .available = availability(for: context) else {
            throw CapabilityError.unsupportedInput("当前文字无法翻译")
        }
        let rawProvider = configurationStore.string(
            pluginID: .translation,
            fieldID: TranslationPlugin.providerFieldID,
            fallback: TranslationProviderID.system.rawValue
        )
        let provider = TranslationProviderID(rawValue: rawProvider) ?? .system
        let targetLanguage = configurationStore.string(
            pluginID: .translation,
            fieldID: TranslationPlugin.targetLanguageFieldID,
            fallback: "zh-Hans"
        )
        let endpoint = configurationStore.string(
            pluginID: .translation,
            fieldID: TranslationPlugin.endpointFieldID
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let model = configurationStore.string(
            pluginID: .translation,
            fieldID: TranslationPlugin.modelFieldID
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        if provider == .openAICompatible, endpoint.isEmpty || model.isEmpty {
            throw CapabilityError.unavailable("请先在设置中填写 AI endpoint 和 model")
        }
        return .translation(TranslationRequest(
            text: context.normalizedText,
            providerID: provider,
            targetLanguageIdentifier: targetLanguage,
            endpoint: endpoint.isEmpty ? nil : endpoint,
            model: model.isEmpty ? nil : model
        ))
    }
}

@MainActor
final class TranslationPlugin: ClipAllPlugin {
    static let providerFieldID = TranslationConfigurationKey.provider
    static let targetLanguageFieldID = TranslationConfigurationKey.targetLanguage
    static let endpointFieldID = TranslationConfigurationKey.endpoint
    static let modelFieldID = TranslationConfigurationKey.model
    static let apiKeyFieldID = TranslationConfigurationKey.apiKey

    let descriptor: PluginDescriptor
    let capabilities: [any CapabilityExecuting]

    init(configurationStore: PluginConfigurationStore) {
        let aiCondition = PluginConfigurationCondition(
            fieldID: Self.providerFieldID,
            equals: .string(TranslationProviderID.openAICompatible.rawValue)
        )
        descriptor = PluginDescriptor(
            id: .translation,
            name: "翻译",
            summary: "设备端系统翻译或 OpenAI-compatible AI 翻译。",
            symbolName: "character.book.closed",
            version: "1.0.0",
            source: .builtIn,
            configurationFields: [
                PluginConfigurationField(
                    id: Self.providerFieldID,
                    title: "翻译提供方",
                    kind: .choice(options: [
                        PluginConfigurationOption(id: TranslationProviderID.system.rawValue, title: "Apple 系统翻译 · 设备端"),
                        PluginConfigurationOption(id: TranslationProviderID.openAICompatible.rawValue, title: "OpenAI-compatible AI"),
                    ]),
                    defaultValue: .string(TranslationProviderID.system.rawValue)
                ),
                PluginConfigurationField(
                    id: Self.targetLanguageFieldID,
                    title: "目标语言",
                    kind: .choice(options: [
                        PluginConfigurationOption(id: "zh-Hans", title: "简体中文"),
                        PluginConfigurationOption(id: "en", title: "English"),
                        PluginConfigurationOption(id: "ja", title: "日本語"),
                        PluginConfigurationOption(id: "ko", title: "한국어"),
                        PluginConfigurationOption(id: "de", title: "Deutsch"),
                        PluginConfigurationOption(id: "fr", title: "Français"),
                        PluginConfigurationOption(id: "es", title: "Español"),
                    ]),
                    defaultValue: .string("zh-Hans")
                ),
                PluginConfigurationField(
                    id: Self.endpointFieldID,
                    title: "Endpoint",
                    summary: "完整的 OpenAI-compatible chat completions 地址。",
                    kind: .text(placeholder: "https://…/v1/chat/completions"),
                    defaultValue: .string(""),
                    visibleWhen: aiCondition
                ),
                PluginConfigurationField(
                    id: Self.modelFieldID,
                    title: "Model",
                    kind: .text(placeholder: "模型标识"),
                    defaultValue: .string(""),
                    visibleWhen: aiCondition
                ),
                PluginConfigurationField(
                    id: Self.apiKeyFieldID,
                    title: "API Key",
                    summary: "仅保存在 macOS Keychain。",
                    kind: .secret(placeholder: "sk-…"),
                    defaultValue: .string(""),
                    visibleWhen: aiCondition
                ),
            ]
        )
        capabilities = [TranslationCapability(configurationStore: configurationStore)]
    }
}
