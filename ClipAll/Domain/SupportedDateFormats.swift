import Foundation

enum SupportedDateFormats {
    private static let explicitISOPattern =
        #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2})$"#

    private static let localPatterns: [(regularExpression: String, dateFormat: String)] = [
        (#"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"#, "yyyy-MM-dd HH:mm:ss"),
        (#"^\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}$"#, "yyyy/MM/dd HH:mm:ss"),
        (#"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$"#, "yyyy-MM-dd'T'HH:mm:ss"),
        (#"^\d{4}-\d{2}-\d{2}$"#, "yyyy-MM-dd"),
    ]

    static func looksLikeSupportedDate(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if matches(value, regularExpression: explicitISOPattern) {
            return validExplicitISO(value)
        }
        for pattern in localPatterns where matches(value, regularExpression: pattern.regularExpression) {
            return validLocalDate(value, format: pattern.dateFormat)
        }
        return false
    }

    private static func validExplicitISO(_ value: String) -> Bool {
        if value.last != "Z" {
            let offset = value.suffix(6)
            guard offset.first == "+" || offset.first == "-",
                  let hour = Int(offset.dropFirst().prefix(2)),
                  let minute = Int(offset.suffix(2)),
                  hour <= 14,
                  minute <= 59,
                  hour < 14 || minute == 0 else {
                return false
            }
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = value.contains(".")
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter.date(from: value) != nil
    }

    private static func validLocalDate(_ value: String, format: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }

    private static func matches(_ value: String, regularExpression: String) -> Bool {
        value.range(of: regularExpression, options: .regularExpression) != nil
    }
}
