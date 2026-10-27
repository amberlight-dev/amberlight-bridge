import Foundation

nonisolated enum CustomBindings {
    static let reserved: Set<String> = ["value", "now", "caption"]

    @discardableResult
    static func add(path: String, json: Any, to definition: inout CustomWidgetDefinition) -> String {
        let name = uniqueName(for: path, taken: Set((definition.values ?? []).map(\.name)))
        definition.values = (definition.values ?? []) + [CustomWidgetDefinition.NamedValue(name: name, selection: selection(for: path, json: json))]
        definition.display.layout = appending(CustomNode(type: .text, text: "{\(name)}", size: .m), to: definition.display.layout)
        return name
    }

    static func selection(for path: String, json: Any) -> CustomWidgetDefinition.Selection {
        guard let split = JSONPath.elementSplit(path) else { return .init(valuePath: path) }
        let numeric = isNumeric(JSONPath.resolve(path, in: json))
        return .init(arrayPath: split.array, valueField: split.field, aggregation: numeric ? .sum : .first)
    }

    static func uniqueName(for path: String, taken: Set<String>) -> String {
        let key = JSONPath.parse(path)?.reversed().compactMap { segment -> String? in
            if case .key(let name) = segment { name } else { nil }
        }.first ?? "wert"
        var base = String(key.map { $0.isLetter || $0.isNumber ? $0 : "_" })
        if base.first?.isNumber ?? true { base = "v" + base }
        var name = base
        var counter = 2
        while taken.contains(name) || reserved.contains(name) {
            name = "\(base)\(counter)"
            counter += 1
        }
        return name
    }

    static func appending(_ node: CustomNode, to layout: CustomNode?) -> CustomNode {
        guard let layout else { return CustomNode(type: .vstack, children: [node]) }
        guard layout.type == .vstack else { return CustomNode(type: .vstack, children: [layout, node]) }
        var stack = layout
        stack.children = (layout.children ?? []) + [node]
        return stack
    }

    private static func isNumeric(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) != CFBooleanGetTypeID()
    }
}
