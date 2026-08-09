import Foundation

private enum OpenAITranslationVerificationError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

@MainActor
private final class StubSecrets: PluginSecretProviding {
    let value: String?

    init(_ value: String?) {
        self.value = value
    }

    func secret(pluginID: PluginID, fieldID: String) throws -> String? {
        guard pluginID == .translation,
              fieldID == TranslationConfigurationKey.apiKey else {
            throw OpenAITranslationVerificationError.failed("读取了错误的 Keychain 字段")
        }
        return value
    }
}

private struct StubHTTPClient: TranslationHTTPClient {
    let statusCode: Int
    let body: Data
    let validatesRequest: Bool

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if validatesRequest {
            guard request.url?.absoluteString == "https://example.test/v1/chat/completions",
                  request.httpMethod == "POST",
                  request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key",
                  request.value(forHTTPHeaderField: "Content-Type") == "application/json",
                  let body = request.httpBody,
                  let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                  payload["model"] as? String == "test-model",
                  let messages = payload["messages"] as? [[String: Any]],
                  messages.count == 2,
                  messages.last?["content"] as? String == "Hello" else {
                throw OpenAITranslationVerificationError.failed("AI 翻译请求格式不正确")
            }
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (body, response)
    }
}

@main
@MainActor
enum OpenAITranslationVerification {
    static func main() async throws {
        let successBody = Data(
            #"{"choices":[{"message":{"role":"assistant","content":"你好"}}]}"#.utf8
        )
        let provider = OpenAICompatibleTranslationProvider(
            secrets: StubSecrets("test-key"),
            httpClient: StubHTTPClient(
                statusCode: 200,
                body: successBody,
                validatesRequest: true
            )
        )
        let result = try await provider.translate(request())
        try expect(result.items.first?.value == "你好", "应返回 AI 译文")
        try expect(result.subtitle == "AI 翻译 · test-model", "结果应标注模型")

        try await expectCapabilityError(containing: "API Key") {
            try await OpenAICompatibleTranslationProvider(
                secrets: StubSecrets(nil),
                httpClient: StubHTTPClient(statusCode: 200, body: successBody, validatesRequest: false)
            ).translate(request())
        }

        try await expectCapabilityError(containing: "HTTP 401") {
            try await OpenAICompatibleTranslationProvider(
                secrets: StubSecrets("test-key"),
                httpClient: StubHTTPClient(statusCode: 401, body: Data(), validatesRequest: false)
            ).translate(request())
        }

        try await expectCapabilityError(containing: "返回格式无效") {
            try await OpenAICompatibleTranslationProvider(
                secrets: StubSecrets("test-key"),
                httpClient: StubHTTPClient(
                    statusCode: 200,
                    body: Data(#"{"choices":[]}"#.utf8),
                    validatesRequest: false
                )
            ).translate(request())
        }

        let invalid = TranslationRequest(
            text: "Hello",
            providerID: .openAICompatible,
            targetLanguageIdentifier: "zh-Hans",
            endpoint: "file:///tmp/not-allowed",
            model: "test-model"
        )
        try await expectCapabilityError(containing: "endpoint") {
            try await provider.translate(invalid)
        }

        let insecure = TranslationRequest(
            text: "Hello",
            providerID: .openAICompatible,
            targetLanguageIdentifier: "zh-Hans",
            endpoint: "http://example.test/v1/chat/completions",
            model: "test-model"
        )
        try await expectCapabilityError(containing: "endpoint") {
            try await provider.translate(insecure)
        }

        print("OpenAI translation verification passed")
    }

    private static func request() -> TranslationRequest {
        TranslationRequest(
            text: "Hello",
            providerID: .openAICompatible,
            targetLanguageIdentifier: "zh-Hans",
            endpoint: "https://example.test/v1/chat/completions",
            model: "test-model"
        )
    }

    private static func expectCapabilityError(
        containing expectedText: String,
        operation: @MainActor () async throws -> CapabilityResult
    ) async throws {
        do {
            _ = try await operation()
            throw OpenAITranslationVerificationError.failed("期望翻译失败，但执行成功")
        } catch let error as CapabilityError {
            try expect(
                error.localizedDescription.contains(expectedText),
                "错误应包含 \(expectedText)，实际为：\(error.localizedDescription)"
            )
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw OpenAITranslationVerificationError.failed(message) }
    }
}
