import Foundation

nonisolated enum CustomLayout {
    struct Scope {
        var raw: [String: Any] = [:]
        var text: [String: String] = [:]
        var mainTone: CustomWidgetDisplay.Tone?
        var placeholders = false
    }

    static func scope(for definition: CustomWidgetDefinition, json: Any, at date: Date) -> Scope {
        let main = CustomEvaluator.selectedValue(definition.selection, in: json)
        var scope = Scope()
        scope.raw["value"] = main
        scope.raw["now"] = date.formatted(.iso8601)
        scope.text["value"] = CustomEvaluator.formatted(main, display: definition.display)
        scope.text["caption"] = definition.display.caption.isEmpty ? definition.name : definition.display.caption
        if definition.display.style == .status {
            scope.mainTone = CustomEvaluator.rule(matching: main, in: definition.display.rules)?.tone ?? .gray
        }
        var plain = definition.display
        plain.prefix = ""
        plain.suffix = ""
        plain.unit = ""
        for named in definition.values ?? [] {
            let value = CustomEvaluator.selectedValue(named.selection, in: json)
            scope.raw[named.name] = value
            var display = plain
            if let format = named.format { display.format = format }
            scope.text[named.name] = CustomEvaluator.formatted(value, display: display)
        }
        return scope
    }

    static func resolve(_ node: CustomNode, scope: Scope, depth: Int = 1) -> CustomNode? {
        guard depth <= CustomNode.maxDepth + 1, holds(node.when, scope) else { return nil }
        var out = node
        out.when = nil
        out.value = nil
        out.max = nil
        out.since = nil
        out.plus = nil
        out.plusUnit = nil
        out.toneWhen = nil
        let rule = node.toneWhen?.first { holds($0.when, scope) }
        out.tone = rule?.tone ?? node.tone ?? inheritedTone(node.type, scope)
        if node.color == "status" {
            out.color = nil
            out.tone = scope.mainTone ?? .gray
        }
        if let children = node.children {
            out.children = children.compactMap { resolve($0, scope: scope, depth: depth + 1) }
            if out.children?.isEmpty == true, node.type != .ring { return nil }
        }
        switch node.type {
        case .text:
            guard let template = node.text, let filled = fill(template, scope), !filled.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            out.text = filled
        case .pill:
            if let label = rule?.label, !label.isEmpty {
                out.text = label
            } else {
                guard let filled = fill(node.text ?? "", scope), !filled.isEmpty else { return nil }
                out.text = filled
            }
        case .ring, .bar:
            let number = node.value.flatMap { JSONPath.number(scope.raw[$0]) } ?? (scope.placeholders ? 0 : nil)
            guard let number else { return nil }
            let limit = node.max.flatMap { Double($0) ?? JSONPath.number(scope.raw[$0]) } ?? 1
            out.progress = limit > 0 ? min(max(number / limit, 0), 1) : 0
        case .timer:
            guard let start = timerStart(node, scope) ?? (scope.placeholders ? date(scope.raw["now"]) : nil) else { return nil }
            out.start = start
            out.plusUnit = nil
        default:
            break
        }
        return out
    }

    static func timerStart(_ node: CustomNode, _ scope: Scope) -> Date? {
        guard let since = node.since.flatMap({ date(scope.raw[$0]) }) else { return nil }
        let amount = node.plus.flatMap { JSONPath.number(scope.raw[$0]) } ?? 0
        return since.addingTimeInterval(-amount * unitSeconds(node.plusUnit))
    }

    static func unitSeconds(_ unit: String?) -> Double {
        switch unit {
        case "seconds": 1
        case "minutes": 60
        default: 3600
        }
    }

    static func referencedNames(in expression: String?) -> [String] {
        guard var text = expression?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return [] }
        if text.hasPrefix("!") { text.removeFirst() }
        let left = [">=", "<=", "!=", "==", ">", "<"].lazy.compactMap { text.range(of: $0) }.first.map { String(text[..<$0.lowerBound]) } ?? text
        let name = left.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? [] : [name]
    }

    static func fill(_ template: String, _ scope: Scope) -> String? {
        var result = ""
        var cursor = template.startIndex
        for match in template.matches(of: /\{(\w+)\}/) {
            guard let text = scope.text[String(match.1)] ?? (scope.placeholders ? "{\(match.1)}" : nil) else { return nil }
            result += template[cursor..<match.range.lowerBound] + text
            cursor = match.range.upperBound
        }
        return result + template[cursor...]
    }

    static func holds(_ expression: String?, _ scope: Scope) -> Bool {
        guard let expression = expression?.trimmingCharacters(in: .whitespaces), !expression.isEmpty else { return true }
        if expression.hasPrefix("!") { return !holds(String(expression.dropFirst()), scope) }
        for symbol in [">=", "<=", "!=", "==", ">", "<"] {
            guard let range = expression.range(of: symbol) else { continue }
            let left = scope.raw[expression[..<range.lowerBound].trimmingCharacters(in: .whitespaces)]
            let right = expression[range.upperBound...].trimmingCharacters(in: .whitespaces)
            return compare(left, symbol, right)
        }
        if let number = JSONPath.number(scope.raw[expression]) { return number != 0 }
        return JSONPath.isPresent(scope.raw[expression])
    }

    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let strategies: [Date.ISO8601FormatStyle] = [
            .iso8601,
            Date.ISO8601FormatStyle(includingFractionalSeconds: true),
            Date.ISO8601FormatStyle(timeZoneSeparator: .colon),
            Date.ISO8601FormatStyle(timeZoneSeparator: .colon, includingFractionalSeconds: true),
        ]
        return strategies.lazy.compactMap { try? Date(text, strategy: $0) }.first
    }

    private static func inheritedTone(_ kind: CustomNode.Kind, _ scope: Scope) -> CustomWidgetDisplay.Tone? {
        switch kind {
        case .dot, .ring, .bar, .symbol: scope.mainTone
        default: nil
        }
    }

    private static func compare(_ left: Any?, _ symbol: String, _ right: String) -> Bool {
        if let number = JSONPath.number(left), let target = Double(right) {
            switch symbol {
            case ">=": return number >= target
            case "<=": return number <= target
            case ">": return number > target
            case "<": return number < target
            case "!=": return number != target
            default: return number == target
            }
        }
        let same = JSONPath.text(left)?.caseInsensitiveCompare(right) == .orderedSame
        switch symbol {
        case "==": return same
        case "!=": return !same
        default: return false
        }
    }
}
