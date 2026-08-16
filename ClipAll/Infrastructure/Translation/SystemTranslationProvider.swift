import Foundation
import Translation

@MainActor
enum SystemTranslationProvider {
    static func result(
        from response: TranslationSession.Response,
        request: TranslationRequest
    ) -> CapabilityResult {
        CapabilityResult(
            title: "翻译",
            subtitle: "Apple 系统翻译 · 设备端",
            items: [
                CapabilityResultItem(
                    id: "translation",
                    label: "译文",
                    value: response.targetText,
                    annotation: "\(response.sourceLanguage.minimalIdentifier) · \(response.targetLanguage.minimalIdentifier)"
                ),
            ]
        )
    }

    static func userMessage(for error: Error) -> String {
        if TranslationError.unsupportedSourceLanguage ~= error {
            return "系统翻译暂不支持识别出的源语言"
        }
        if TranslationError.unsupportedTargetLanguage ~= error {
            return "系统翻译暂不支持目标语言"
        }
        if TranslationError.unsupportedLanguagePairing ~= error {
            return "系统翻译暂不支持这组语言"
        }
        if TranslationError.unableToIdentifyLanguage ~= error {
            return "无法识别所选文字的语言"
        }
        if TranslationError.nothingToTranslate ~= error {
            return "所选内容没有可翻译的文字"
        }
        if TranslationError.internalError ~= error {
            return "系统翻译暂时不可用，请稍后重试"
        }
        return (error as? LocalizedError)?.errorDescription ?? "翻译失败"
    }
}
