import Foundation

nonisolated enum CustomEvaluator {
    static let maxPoints = 50

    static func display(for definition: CustomWidgetDefinition, json: Any, history: [CustomWidgetDisplay.Sample] = [], at date: Date = .now, editing: Bool = false) -> CustomWidgetDisplay {
        let value = selectedValue(definition.selection, in: json)
        let number = JSONPath.number(value)
        let text = formatted(value, display: definition.display)
        var result = empty(definition)
        result.updatedAt = date
        result.history = history
        switch definition.display.style {
        case .status:
            let match = rule(matching: value, in: definition.display.rules)
            result.tone = match?.tone ?? .gray
            result.text = match.flatMap { $0.label.isEmpty ? nil : $0.label } ?? text
        case .gauge:
            result.text = text
            result.progress = number.map { progress(of: $0, display: definition.display) }
        case .text, .line, .bar, .list:
            result.text = text
        }
        result.points = series(definition.selection, in: json, display: definition.display)
        result.lines = lines(for: definition, json: json, at: date)
        if let layout = CustomSizing.composed(definition.display, annotated: editing) {
            var scope = CustomLayout.scope(for: definition, json: json, at: date)
            scope.placeholders = editing
            result.root = CustomLayout.resolve(layout, scope: scope)
        }
        if value == nil, result.points.isEmpty, definition.display.layout == nil { result.error = "Wert nicht gefunden" }
        return result
    }

    static func empty(_ definition: CustomWidgetDefinition, error: String? = nil) -> CustomWidgetDisplay {
        CustomWidgetDisplay(
            id: definition.id, name: definition.name, symbol: definition.symbol, style: definition.display.style,
            caption: definition.display.caption.isEmpty ? definition.name : definition.display.caption, error: error
        )
    }

    static func selectedValue(_ selection: CustomWidgetDefinition.Selection, in json: Any) -> Any? {
        guard let arrayPath = selection.arrayPath else { return JSONPath.resolve(selection.valuePath, in: json) }
        guard let array = JSONPath.resolve(arrayPath, in: json) as? [Any] else { return nil }
        return aggregate(filtered(array, by: selection.filter).map { field(selection.valueField, of: $0) }, by: selection.aggregation)
    }

    static func aggregate(_ values: [Any?], by aggregation: CustomWidgetDefinition.Aggregation) -> Any? {
        let numbers = values.compactMap(JSONPath.number)
        switch aggregation {
        case .count: return Double(values.count)
        case .countPresent: return Double(values.filter(JSONPath.isPresent).count)
        case .sum: return numbers.reduce(0, +)
        case .average: return numbers.isEmpty ? nil : numbers.reduce(0, +) / Double(numbers.count)
        case .minimum: return numbers.min()
        case .maximum: return numbers.max()
        case .first: return values.first ?? nil
        case .last: return values.last ?? nil
        }
    }

    static func filtered(_ array: [Any], by filter: String?) -> [Any] {
        guard let filter = filter?.trimmingCharacters(in: .whitespaces), !filter.isEmpty else { return array }
        let negated = filter.contains("!=")
        let parts = filter.components(separatedBy: negated ? "!=" : "==").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return array.filter { JSONPath.isPresent(field(filter, of: $0)) } }
        return array.filter { element in
            let value = field(parts[0], of: element)
            let matches: Bool
            if let number = JSONPath.number(value), let target = Double(parts[1]) {
                matches = number == target
            } else {
                matches = JSONPath.text(value)?.caseInsensitiveCompare(parts[1]) == .orderedSame
            }
            return matches != negated
        }
    }

    static func lines(for definition: CustomWidgetDefinition, json: Any, at date: Date = .now) -> [String]? {
        guard let templates = definition.display.lines, !templates.isEmpty else { return nil }
        let scope = CustomLayout.scope(for: definition, json: json, at: date)
        return templates.compactMap { CustomLayout.fill($0, scope) }.filter { !$0.isEmpty }
    }

    static func series(_ selection: CustomWidgetDefinition.Selection, in json: Any, display: CustomWidgetDefinition.Display) -> [CustomWidgetDisplay.Point] {
        guard let path = selection.seriesPath, let array = JSONPath.resolve(path, in: json) as? [Any] else { return [] }
        var points: [CustomWidgetDisplay.Point] = []
        for (index, element) in filtered(array, by: selection.filter).enumerated() {
            let raw = field(selection.seriesField, of: element)
            let rawLabel = JSONPath.text(field(selection.labelField, of: element)) ?? "\(index + 1)"
            let label = selection.labelsAreDates ? dayLabel(rawLabel) : rawLabel
            let value = JSONPath.number(raw)
            if selection.groupsLabels, let existing = points.firstIndex(where: { $0.label == label }) {
                let sum = (points[existing].value ?? 0) + (value ?? 0)
                points[existing].value = sum
                points[existing].text = formatted(sum, display: display)
            } else {
                points.append(CustomWidgetDisplay.Point(label: label, value: value, text: formatted(value ?? raw, display: display)))
            }
        }
        return Array(points.prefix(maxPoints))
    }

    static func formatted(_ value: Any?, display: CustomWidgetDefinition.Display) -> String? {
        let core: String
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            core = format(number.doubleValue, display: display)
        } else if let number = value as? Double {
            core = format(number, display: display)
        } else if let text = JSONPath.text(value) {
            core = text
        } else {
            return nil
        }
        let unit = display.unit.isEmpty ? "" : "\u{202F}" + display.unit
        return display.prefix + core + unit + display.suffix
    }

    static func format(_ number: Double, display: CustomWidgetDefinition.Display) -> String {
        let decimals = min(max(display.decimals, 0), 6)
        switch display.format {
        case .number:
            return number.formatted(.number.precision(.fractionLength(decimals)).locale(locale))
        case .percent:
            return (number * 100).formatted(.number.precision(.fractionLength(decimals)).locale(locale)) + "\u{202F}%"
        case .hoursMinutes:
            let minutes = Int((abs(number) * 60).rounded())
            return (number < 0 ? "-" : "") + String(format: "%d:%02d", minutes / 60, minutes % 60)
        }
    }

    static func rule(matching value: Any?, in rules: [CustomWidgetDefinition.StatusRule]) -> CustomWidgetDefinition.StatusRule? {
        let number = JSONPath.number(value)
        let text = JSONPath.text(value)
        return rules.first { rule in
            let operand = rule.operand.trimmingCharacters(in: .whitespaces)
            switch rule.comparison {
            case .equals:
                if let number, let target = Double(operand) { return number == target }
                return text?.caseInsensitiveCompare(operand) == .orderedSame
            case .atLeast:
                guard let number, let target = Double(operand) else { return false }
                return number >= target
            case .below:
                guard let number, let target = Double(operand) else { return false }
                return number < target
            }
        }
    }

    static func progress(of value: Double, display: CustomWidgetDefinition.Display) -> Double {
        let range = display.gaugeMax - display.gaugeMin
        guard range > 0 else { return 0 }
        return min(max((value - display.gaugeMin) / range, 0), 1)
    }

    private static func field(_ path: String, of element: Any) -> Any? {
        path.isEmpty ? element : JSONPath.resolve(path, in: element)
    }

    private static let locale = Locale(identifier: "de_AT")

    private static func dayLabel(_ raw: String) -> String {
        guard let date = try? Date(String(raw.prefix(10)), strategy: .iso8601.year().month().day()) else { return raw }
        return date.formatted(.dateTime.weekday(.abbreviated).locale(locale))
    }
}
