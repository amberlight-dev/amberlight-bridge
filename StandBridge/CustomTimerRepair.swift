import Foundation

nonisolated enum CustomTimerRepair {
    typealias NamedValue = CustomWidgetDefinition.NamedValue

    static let values: [NamedValue] = [
        NamedValue(name: "running", selection: .init(arrayPath: "", valueField: "timer_started_at", aggregation: .countPresent), format: .number),
        NamedValue(name: "runningStart", selection: .init(arrayPath: "", valueField: "timer_started_at", aggregation: .first, filter: "timer_started_at")),
        NamedValue(name: "runningSeconds", selection: .init(arrayPath: "", valueField: "seconds", aggregation: .sum, filter: "timer_started_at"), format: .number),
    ]

    static func appliesAutomatically(to definition: CustomWidgetDefinition) -> Bool {
        if definition.template == "moco-timer" { return true }
        let host = definition.origin.flatMap { URL(string: $0)?.host() } ?? ""
        return host.hasSuffix("mocoapp.com") && definition.endpoint.path.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) == "activities"
    }

    static let version = 2

    @discardableResult
    static func repair(_ definition: inout CustomWidgetDefinition) -> Bool {
        guard (definition.repairVersion ?? 0) < version, appliesAutomatically(to: definition) else { return false }
        let values = definition.values ?? []
        let trees = [definition.display.layout, definition.display.compact, definition.display.wide]
        definition.repairVersion = version
        guard trees.contains(where: { $0.map { needsBinding(in: $0, values: values) } ?? false }) else { return true }
        addRunningValues(to: &definition)
        definition.display.layout = definition.display.layout.map { fixed($0, values: values) }
        definition.display.compact = definition.display.compact.map { fixed($0, values: values) }
        definition.display.wide = definition.display.wide.map { fixed($0, values: values) }
        return true
    }

    static func addRunningValues(to definition: inout CustomWidgetDefinition) {
        var current = definition.values ?? []
        for canonical in values {
            if let index = current.firstIndex(where: { $0.name == canonical.name }) {
                current[index].selection = canonical.selection
                current[index].format = canonical.format
            } else {
                current.append(canonical)
            }
        }
        definition.values = current
    }

    static func bindRunning(_ node: inout CustomNode) {
        node.since = "runningStart"
        node.plus = "runningSeconds"
        node.plusUnit = "seconds"
    }

    static func needsBinding(in node: CustomNode, values: [NamedValue]) -> Bool {
        (node.type == .timer && needsBinding(node, values: values)) || (node.children ?? []).contains { needsBinding(in: $0, values: values) }
    }

    private static func needsBinding(_ node: CustomNode, values: [NamedValue]) -> Bool {
        guard let since = node.since, since != "now", let source = values.first(where: { $0.name == since }) else { return true }
        guard source.selection.valueField == "timer_started_at" else { return false }
        return since != "runningStart" || node.plus != "runningSeconds" || node.plusUnit != "seconds"
            || source.selection.filter?.trimmingCharacters(in: .whitespaces) != "timer_started_at"
    }

    private static func fixed(_ node: CustomNode, values: [NamedValue]) -> CustomNode {
        var out = node
        if node.type == .timer, needsBinding(node, values: values) { bindRunning(&out) }
        out.children = node.children?.map { fixed($0, values: values) }
        return out
    }
}
