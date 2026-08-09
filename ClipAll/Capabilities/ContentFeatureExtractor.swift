import Foundation
import NaturalLanguage

struct ContentFeatures: Equatable, Sendable {
    let kinds: Set<ContentKind>
    let languageIdentifier: String?

    func contains(_ kind: ContentKind) -> Bool {
        kinds.contains(kind)
    }
}

struct ContentFeatureExtractor: Sendable {
    func extract(from text: String, targetLanguageIdentifier: String) -> ContentFeatures {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return ContentFeatures(kinds: [], languageIdentifier: nil)
        }

        var kinds: Set<ContentKind> = [.text]

        if value.range(of: #"^\d{10}$"#, options: .regularExpression) != nil {
            kinds.insert(.unixTimestampSeconds)
        }
        if value.range(of: #"^\d{13}$"#, options: .regularExpression) != nil {
            kinds.insert(.unixTimestampMilliseconds)
        }
        if SupportedDateFormats.looksLikeSupportedDate(value) {
            kinds.insert(.dateTime)
        }
        if isURL(value) {
            kinds.insert(.url)
        }
        if value.range(
            of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            kinds.insert(.email)
        }
        if looksLikeCode(value) {
            kinds.insert(.code)
        }
        if looksLikeAddress(value) {
            kinds.insert(.address)
        }

        let language = dominantLanguage(for: value)
        if let language,
           !samePrimaryLanguage(language, targetLanguageIdentifier),
           value.unicodeScalars.contains(where: CharacterSet.letters.contains) {
            kinds.insert(.foreignLanguage)
        }

        return ContentFeatures(kinds: kinds, languageIdentifier: language)
    }

    private func isURL(_ value: String) -> Bool {
        if let url = URL(string: value),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
           url.host != nil {
            return true
        }

        return value.range(
            of: #"^(?:www\.)?[A-Z0-9-]+(?:\.[A-Z0-9-]+)+(?:/\S*)?$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private func looksLikeCode(_ value: String) -> Bool {
        let markers = ["func ", "let ", "var ", "const ", "class ", "struct ", "=>", "{", "}", ";"]
        let markerCount = markers.reduce(into: 0) { count, marker in
            if value.contains(marker) { count += 1 }
        }
        return markerCount >= 2 || value.contains("\n    ") || value.contains("\n\t")
    }

    private func looksLikeAddress(_ value: String) -> Bool {
        let chineseAddress = value.range(
            of: #".+(?:省|市|区|县|镇|路|街|巷|号).+"#,
            options: .regularExpression
        ) != nil
        let latinAddress = value.range(
            of: #"^\d+\s+.+\s(?:Street|St|Road|Rd|Avenue|Ave|Lane|Ln|Boulevard|Blvd)\.?$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        return chineseAddress || latinAddress
    }

    private func dominantLanguage(for value: String) -> String? {
        guard value.count >= 3 else { return nil }
        return NLLanguageRecognizer.dominantLanguage(for: value)?.rawValue
    }

    private func samePrimaryLanguage(_ lhs: String, _ rhs: String) -> Bool {
        lhs.split(separator: "-").first?.lowercased() == rhs.split(separator: "-").first?.lowercased()
    }
}
