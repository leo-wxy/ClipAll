import Foundation

enum SupportedDateFormats {
    private static let explicitISOPattern =
        #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2})$"#

    private static let localFormats = [
        "yyyy-MM-dd HH:mm:ss",
        "yyyy/MM/dd HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd",
    ]

    static func looksLikeSupportedDate(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if matches(value, regularExpression: explicitISOPattern) {
            return validExplicitISO(value)
        }
        return matches(value, declaredFormats: localFormats)
    }

    static func matches(_ text: String, declaredFormats: [String]) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        return declaredFormats.contains { format in
            parsedFormat(format)?.matches(value) == true
        }
    }

    static func isValidDeclaration(_ format: String) -> Bool {
        parsedFormat(format) != nil
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

    private static func matches(_ value: String, regularExpression: String) -> Bool {
        value.range(of: regularExpression, options: .regularExpression) != nil
    }

    private enum DateField: Hashable {
        case year
        case month
        case day
        case hour
        case minute
        case second
    }

    private struct FieldCapture {
        let field: DateField
        let group: Int
    }

    private struct ParsedDateFormat {
        let expression: NSRegularExpression
        let captures: [FieldCapture]

        func matches(_ value: String) -> Bool {
            let range = NSRange(value.startIndex..., in: value)
            guard let match = expression.firstMatch(in: value, range: range),
                  match.range == range else { return false }

            var fields: [DateField: Int] = [:]
            for capture in captures {
                guard let captureRange = Range(match.range(at: capture.group), in: value),
                      let number = Int(value[captureRange]) else { return false }
                fields[capture.field] = number
            }

            guard let year = fields[.year],
                  let month = fields[.month],
                  let day = fields[.day],
                  (1...9999).contains(year),
                  (1...12).contains(month),
                  (1...31).contains(day) else { return false }

            let hour = fields[.hour] ?? 0
            let minute = fields[.minute] ?? 0
            let second = fields[.second] ?? 0
            guard (0...23).contains(hour),
                  (0...59).contains(minute),
                  (0...59).contains(second) else { return false }

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let components = DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: second
            )
            guard let date = calendar.date(from: components) else { return false }
            let resolved = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: date
            )
            return resolved.year == year && resolved.month == month && resolved.day == day &&
                resolved.hour == hour && resolved.minute == minute && resolved.second == second
        }
    }

    private struct FieldToken {
        let text: String
        let field: DateField
        let digitPattern: String
    }

    private static let fieldTokens = [
        FieldToken(text: "yyyy", field: .year, digitPattern: #"\d{4}"#),
        FieldToken(text: "MM", field: .month, digitPattern: #"\d{2}"#),
        FieldToken(text: "dd", field: .day, digitPattern: #"\d{2}"#),
        FieldToken(text: "HH", field: .hour, digitPattern: #"\d{2}"#),
        FieldToken(text: "mm", field: .minute, digitPattern: #"\d{2}"#),
        FieldToken(text: "ss", field: .second, digitPattern: #"\d{2}"#),
        FieldToken(text: "M", field: .month, digitPattern: #"\d{1,2}"#),
        FieldToken(text: "d", field: .day, digitPattern: #"\d{1,2}"#),
        FieldToken(text: "H", field: .hour, digitPattern: #"\d{1,2}"#),
        FieldToken(text: "m", field: .minute, digitPattern: #"\d{1,2}"#),
        FieldToken(text: "s", field: .second, digitPattern: #"\d{1,2}"#),
    ]

    private static func parsedFormat(_ format: String) -> ParsedDateFormat? {
        guard !format.isEmpty, format.count <= 64 else { return nil }

        var pattern = "^"
        var captures: [FieldCapture] = []
        var seenFields: Set<DateField> = []
        var index = format.startIndex

        while index < format.endIndex {
            let suffix = format[index...]
            if let token = fieldTokens.first(where: { suffix.hasPrefix($0.text) }) {
                guard seenFields.insert(token.field).inserted else { return nil }
                captures.append(FieldCapture(field: token.field, group: captures.count + 1))
                pattern += "(" + token.digitPattern + ")"
                index = format.index(index, offsetBy: token.text.count)
                continue
            }

            let character = format[index]
            if character == "'" {
                var literal = ""
                var cursor = format.index(after: index)
                while cursor < format.endIndex, format[cursor] != "'" {
                    guard !format[cursor].unicodeScalars.contains(
                        where: CharacterSet.controlCharacters.contains
                    ) else { return nil }
                    literal.append(format[cursor])
                    cursor = format.index(after: cursor)
                }
                guard cursor < format.endIndex, !literal.isEmpty else { return nil }
                pattern += NSRegularExpression.escapedPattern(for: literal)
                index = format.index(after: cursor)
                continue
            }

            guard !isASCIIAlphabetic(character),
                  !character.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                return nil
            }
            pattern += NSRegularExpression.escapedPattern(for: String(character))
            index = format.index(after: index)
        }

        let required: Set<DateField> = [.year, .month, .day]
        guard required.isSubset(of: seenFields) else { return nil }
        let timeFields: Set<DateField> = [.hour, .minute, .second]
        let declaredTimeFields = seenFields.intersection(timeFields)
        guard declaredTimeFields.isEmpty || declaredTimeFields == timeFields else { return nil }

        guard let expression = try? NSRegularExpression(pattern: pattern + "$") else { return nil }
        return ParsedDateFormat(expression: expression, captures: captures)
    }

    private static func isASCIIAlphabetic(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let value = character.unicodeScalars.first?.value else { return false }
        return (65...90).contains(value) || (97...122).contains(value)
    }
}
