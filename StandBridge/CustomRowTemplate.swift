import Foundation

nonisolated enum CustomRowTemplate {
    enum Filter: String, CaseIterable {
        case time, date, weekday, minutes, upper, lower

        var title: String {
            switch self {
            case .time: String(localized: "Uhrzeit (HH:mm)")
            case .date: String(localized: "Datum (TT.MM.)")
            case .weekday: String(localized: "Wochentag")
            case .minutes: String(localized: "Minuten bis dahin")
            case .upper: String(localized: "Großbuchstaben")
            case .lower: String(localized: "Kleinbuchstaben")
            }
        }
    }

    static func fill(_ template: String, _ element: Any, now: Date = .now) -> String? {
        var result = ""
        var cursor = template.startIndex
        for match in template.matches(of: /\{([^{}|]+)(?:\|(\w+))?\}/) {
            let paths = match.1.components(separatedBy: "??").map { $0.trimmingCharacters(in: .whitespaces) }
            let value = paths.lazy.compactMap { JSONPath.resolve($0, in: element) }.first(where: JSONPath.isPresent)
            let text = value.flatMap { apply(match.2.flatMap { Filter(rawValue: String($0)) }, to: $0, now: now) } ?? ""
            result += template[cursor..<match.range.lowerBound] + text
            cursor = match.range.upperBound
        }
        result += template[cursor...]
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func apply(_ filter: Filter?, to value: Any, now: Date = .now) -> String? {
        switch filter {
        case nil: return JSONPath.text(value)
        case .time: return clock(value)
        case .date: return day(value).map { $0.formatted(.dateTime.day(.twoDigits).month(.twoDigits).locale(locale)) }
        case .weekday: return day(value).map { $0.formatted(.dateTime.weekday(.abbreviated).locale(locale)) }
        case .minutes:
            guard let date = CustomLayout.date(value) else { return nil }
            let minutes = Int((date.timeIntervalSince(now) / 60).rounded())
            return minutes <= 0 ? String(localized: "jetzt") : String(localized: "in \(minutes) min")
        case .upper: return JSONPath.text(value)?.uppercased()
        case .lower: return JSONPath.text(value)?.lowercased()
        }
    }

    static func clock(_ value: Any?) -> String? {
        if let date = CustomLayout.date(value) {
            return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
        }
        guard let raw = JSONPath.text(value)?.trimmingCharacters(in: .whitespaces) else { return nil }
        let digits = raw.filter(\.isNumber)
        guard digits.count == raw.count, digits.count >= 3 else { return raw }
        let padded = digits.count % 2 == 1 && digits.count < 6 ? "0" + digits : digits
        let clock = padded.count >= 6 ? String(padded.suffix(6)) : String(padded.suffix(4))
        return clock.prefix(2) + ":" + clock.dropFirst(2).prefix(2)
    }

    private static func day(_ value: Any) -> Date? {
        if let date = CustomLayout.date(value) { return date }
        guard let raw = JSONPath.text(value) else { return nil }
        return try? Date(String(raw.prefix(10)), strategy: .iso8601.year().month().day())
    }

    private static let locale = Locale(identifier: "de_AT")
}
