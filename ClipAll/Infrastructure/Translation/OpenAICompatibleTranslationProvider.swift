import Foundation

protocol TranslationHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionTranslationHTTPClient: TranslationHTTPClient {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

@MainActor
final class OpenAICompatibleTranslationProvider {
    private let secrets: any PluginSecretProviding
    private let httpClient: any TranslationHTTPClient

    init(
        secrets: any PluginSecretProviding,
        httpClient: any TranslationHTTPClient = URLSessionTranslationHTTPClient()
    ) {
        self.secrets = secrets
        self.httpClient = httpClient
    }

    func translate(_ translation: TranslationRequest) async throws -> CapabilityResult {
        guard translation.providerID == .openAICompatible else {
            throw CapabilityError.unavailable("当前翻译请求不是 AI 翻译")
        }
        guard translation.text.utf8.count <= CapabilityInputLimits.maximumTextBytes else {
            throw CapabilityError.unsupportedInput("所选文字超过翻译处理上限")
        }
        guard let endpoint = translation.endpoint,
              let url = URL(string: endpoint),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              url.host != nil else {
            throw CapabilityError.unavailable("请在设置中填写有效的 AI endpoint")
        }
        guard let model = translation.model?.trimmingCharacters(in: .whitespacesAndNewlines),
              !model.isEmpty else {
            throw CapabilityError.unavailable("请在设置中填写 AI model")
        }
        guard let apiKey = try secrets.secret(
            pluginID: .translation,
            fieldID: TranslationConfigurationKey.apiKey
        )?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            throw CapabilityError.unavailable("请先在设置中保存 AI API Key")
        }

        let payload = ChatRequest(
            model: model,
            messages: [
                Message(
                    role: "system",
                    content: "Translate the user's text into \(translation.targetLanguageIdentifier). Return only the translation."
                ),
                Message(role: "user", content: translation.text),
            ]
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await httpClient.data(for: request)
        } catch is CancellationError {
            throw CapabilityError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw CapabilityError.cancelled
        } catch {
            throw CapabilityError.unavailable("无法连接 AI 翻译服务：\(error.localizedDescription)")
        }
        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CapabilityError.unavailable("AI 翻译服务返回了无效响应")
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw CapabilityError.unavailable("AI 翻译请求失败（HTTP \(httpResponse.statusCode)）")
        }
        guard data.count <= 2_000_000 else {
            throw CapabilityError.unavailable("AI 翻译响应超过大小上限")
        }
        guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = decoded.choices.first?.message.content
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw CapabilityError.unavailable("AI 翻译返回格式无效")
        }

        return CapabilityResult(
            title: "翻译",
            subtitle: "AI 翻译 · \(model)",
            items: [
                CapabilityResultItem(
                    id: "translation",
                    label: "译文",
                    value: content,
                    annotation: "目标语言：\(translation.targetLanguageIdentifier)"
                ),
            ]
        )
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
    }

    private struct Message: Codable {
        let role: String
        let content: String
    }

    private struct ChatResponse: Decodable {
        let choices: [Choice]
    }

    private struct Choice: Decodable {
        let message: Message
    }
}
