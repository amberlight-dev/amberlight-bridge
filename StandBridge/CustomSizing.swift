import Foundation

nonisolated enum CustomSizing {
    enum SizeClass: String, CaseIterable, Identifiable, Codable {
        case compact, wide, main

        var id: Self { self }

        var title: String {
            switch self {
            case .compact: "1×1"
            case .wide: "2×1"
            case .main: String(localized: "2×2 und größer")
            }
        }
    }

    static func sizeClass(for span: GridSpan) -> SizeClass {
        span.w == 1 ? .compact : span.h == 1 ? .wide : .main
    }

    static func hasSizeRules(_ node: CustomNode) -> Bool {
        node.minW != nil || node.minH != nil || node.maxW != nil || node.maxH != nil
            || (node.children ?? []).contains(where: hasSizeRules)
    }

    static func usesDerivation(_ display: CustomWidgetDefinition.Display) -> Bool {
        guard let main = display.layout else { return false }
        return display.compact != nil || display.wide != nil || !hasSizeRules(main)
    }

    static func blocks(of node: CustomNode) -> [CustomNode] {
        if node.type.isContainer { return (node.children ?? []).flatMap(blocks) }
        return node.type == .spacer || node.type == .divider ? [] : [node]
    }

    static func ranked(_ blocks: [CustomNode]) -> [CustomNode] {
        blocks.enumerated()
            .sorted { ($0.element.priority ?? 0, -$0.offset) > ($1.element.priority ?? 0, -$1.offset) }
            .map(\.element)
    }

    static func derived(from main: CustomNode, for size: SizeClass) -> CustomNode? {
        let all = blocks(of: main)
        let top = ranked(all)
        switch size {
        case .main:
            return main
        case .compact:
            return top.first
        case .wide:
            let chosen = Array(all.filter { block in top.prefix(2).contains(block) }.prefix(2))
            guard chosen.count > 1 else { return chosen.first }
            let textual: Set<CustomNode.Kind> = [.text, .timer, .pill]
            let stacked = chosen.allSatisfy { textual.contains($0.type) }
            return CustomNode(type: stacked ? .vstack : .hstack, children: chosen, spacing: stacked ? 2 : 10)
        }
    }

    static func layout(of display: CustomWidgetDefinition.Display, for size: SizeClass) -> CustomNode? {
        guard let main = display.layout else { return nil }
        switch size {
        case .main: return main
        case .compact: return display.compact ?? (usesDerivation(display) ? derived(from: main, for: .compact) : main)
        case .wide: return display.wide ?? (usesDerivation(display) ? derived(from: main, for: .wide) : main)
        }
    }

    static func composed(_ display: CustomWidgetDefinition.Display, annotated: Bool = false) -> CustomNode? {
        guard var main = display.layout else { return nil }
        var compact = display.compact
        var wide = display.wide
        if annotated {
            main = annotate(main, tree: .main)
            compact = compact.map { annotate($0, tree: .compact) }
            wide = wide.map { annotate($0, tree: .wide) }
        }
        guard usesDerivation(display) else { return main }
        var small = compact ?? derived(from: main, for: .compact) ?? main
        var row = wide ?? derived(from: main, for: .wide) ?? main
        var large = main
        small.maxW = 1
        row.minW = 2
        row.maxH = 1
        large.minW = 2
        large.minH = 2
        return CustomNode(type: .zstack, children: [small, row, large])
    }

    static func annotate(_ node: CustomNode, tree: SizeClass, path: [Int] = []) -> CustomNode {
        var out = node
        out.ref = CustomNodeRef(tree: tree, path: path).id
        out.children = node.children?.enumerated().map { annotate($1, tree: tree, path: path + [$0]) }
        return out
    }
}

nonisolated struct CustomNodeRef: Hashable {
    var tree: CustomSizing.SizeClass
    var path: [Int]

    var id: String { tree.rawValue + ":" + path.map(String.init).joined(separator: ".") }

    init(tree: CustomSizing.SizeClass, path: [Int]) {
        self.tree = tree
        self.path = path
    }

    init?(_ id: String) {
        let parts = id.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let tree = CustomSizing.SizeClass(rawValue: String(parts[0])) else { return nil }
        let indices = parts[1].split(separator: ".").compactMap { Int($0) }
        guard indices.count == parts[1].split(separator: ".").count else { return nil }
        self.init(tree: tree, path: indices)
    }

    var parent: CustomNodeRef? { path.isEmpty ? nil : CustomNodeRef(tree: tree, path: Array(path.dropLast())) }
}
