import Foundation

enum SearchProvider: String, CaseIterable, Sendable {
    case google
    case bing
    case duckDuckGo = "duckduckgo"

    var title: String {
        switch self {
        case .google: "Google"
        case .bing: "Bing"
        case .duckDuckGo: "DuckDuckGo"
        }
    }

    func url(for query: String) -> URL? {
        var components: URLComponents
        switch self {
        case .google:
            components = URLComponents(string: "https://www.google.com/search")!
        case .bing:
            components = URLComponents(string: "https://www.bing.com/search")!
        case .duckDuckGo:
            components = URLComponents(string: "https://duckduckgo.com/")!
        }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }
}

@MainActor
final class SearchCapability: CapabilityExecuting {
    let descriptor = CapabilityDescriptor(
        id: .search,
        pluginID: .search,
        name: "搜索",
        symbolName: "magnifyingglass",
        purpose: "使用所选搜索引擎在默认浏览器中搜索文字。",
        supportedContentKinds: Set(ContentKind.allCases),
        examples: ["Swift concurrency", "上海天气"],
        routingRules: [
            CapabilityRoutingRule(contentKind: .text, score: 25, reason: "可作为网页搜索关键词"),
            CapabilityRoutingRule(contentKind: .url, score: 20, reason: "可搜索这个网址"),
            CapabilityRoutingRule(contentKind: .code, score: 30, reason: "可搜索相关代码资料"),
        ]
    )
    let executionPresentation = CapabilityExecutionPresentation.external

    private let configurationStore: PluginConfigurationStore
    private let browser: BrowserService

    init(configurationStore: PluginConfigurationStore, browser: BrowserService) {
        self.configurationStore = configurationStore
        self.browser = browser
    }

    func execute(in context: SelectionContext) async throws -> CapabilityOutput {
        let rawProvider = configurationStore.string(
            pluginID: .search,
            fieldID: SearchPlugin.providerFieldID,
            fallback: SearchProvider.google.rawValue
        )
        let provider = SearchProvider(rawValue: rawProvider) ?? .google
        guard let url = provider.url(for: context.normalizedText) else {
            throw CapabilityError.invalidInput("无法生成搜索地址")
        }
        guard browser.open(url) else {
            throw CapabilityError.unavailable("默认浏览器无法打开搜索")
        }
        return .external
    }
}

@MainActor
final class SearchPlugin: ClipAllPlugin {
    static let providerFieldID = "provider"

    let descriptor: PluginDescriptor
    let capabilities: [any CapabilityExecuting]

    init(configurationStore: PluginConfigurationStore, browser: BrowserService) {
        descriptor = PluginDescriptor(
            id: .search,
            name: "搜索",
            summary: "在默认浏览器中搜索选中文字。",
            symbolName: "magnifyingglass",
            version: "1.0.0",
            source: .builtIn,
            configurationFields: [
                PluginConfigurationField(
                    id: Self.providerFieldID,
                    title: "搜索引擎",
                    summary: "执行搜索时打开的提供方。",
                    kind: .choice(options: SearchProvider.allCases.map {
                        PluginConfigurationOption(id: $0.rawValue, title: $0.title)
                    }),
                    defaultValue: .string(SearchProvider.google.rawValue)
                ),
            ]
        )
        capabilities = [SearchCapability(configurationStore: configurationStore, browser: browser)]
    }
}
