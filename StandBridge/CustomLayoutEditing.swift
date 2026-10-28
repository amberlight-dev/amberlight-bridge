import Foundation

nonisolated enum CustomBlock: String, CaseIterable, Identifiable {
    case title, label, bigNumber, text, pill, ring, bar, line, bars, list, symbol, spacer, divider, row, column

    var id: Self { self }

    var title: String {
        switch self {
        case .title: String(localized: "Titel")
        case .label: "Label"
        case .bigNumber: String(localized: "Große Zahl")
        case .text: "Text"
        case .pill: "Status-Pille"
        case .ring: String(localized: "Ring")
        case .bar: "Fortschritt"
        case .line: String(localized: "Linie")
        case .bars: String(localized: "Balken")
        case .list: "Liste"
        case .symbol: "Icon"
        case .spacer: "Abstand"
        case .divider: String(localized: "Trenner")
        case .row: String(localized: "Zeile")
        case .column: String(localized: "Spalte")
        }
    }

    var symbol: String {
        switch self {
        case .title: "textformat.size.larger"
        case .label: "textformat.size.smaller"
        case .bigNumber: "number"
        case .text: "text.alignleft"
        case .pill: "capsule.inset.filled"
        case .ring: "circle.dashed"
        case .bar: "minus.rectangle"
        case .line: "chart.xyaxis.line"
        case .bars: "chart.bar"
        case .list: "list.bullet"
        case .symbol: "star"
        case .spacer: "arrow.up.and.down"
        case .divider: "minus"
        case .row: "rectangle.split.3x1"
        case .column: "rectangle.split.1x2"
        }
    }

    var node: CustomNode {
        switch self {
        case .title: CustomNode(type: .text, text: "{caption}", size: .l, bold: true)
        case .label: CustomNode(type: .text, text: "{caption}", size: .xs)
        case .bigNumber: CustomNode(type: .text, text: "{value}", size: .xl)
        case .text: CustomNode(type: .text, text: "{value}", size: .s)
        case .pill: CustomNode(type: .pill, text: "{value}", size: .s, toneWhen: [.init(when: "value >= 1", tone: .green, label: String(localized: "Aktiv"))])
        case .ring: CustomNode(type: .ring, children: [CustomNode(type: .text, text: "{value}", size: .s)], value: "value", max: "100")
        case .bar: CustomNode(type: .bar, value: "value", max: "100")
        case .line: CustomNode(type: .line)
        case .bars: CustomNode(type: .bars)
        case .list: CustomNode(type: .list)
        case .symbol: CustomNode(type: .symbol, text: "star.fill", size: .m)
        case .spacer: CustomNode(type: .spacer)
        case .divider: CustomNode(type: .divider)
        case .row: CustomNode(type: .hstack, children: [], spacing: 8)
        case .column: CustomNode(type: .vstack, children: [], spacing: 4)
        }
    }

    static let dragPrefix = "block:"
    static let valuePrefix = "value:"
}

nonisolated enum CustomLayoutEditing {
    typealias Display = CustomWidgetDefinition.Display

    static func root(of display: Display, tree: CustomSizing.SizeClass) -> CustomNode? {
        switch tree {
        case .main: display.layout
        case .compact: display.compact
        case .wide: display.wide
        }
    }

    static func setRoot(_ node: CustomNode?, of display: inout Display, tree: CustomSizing.SizeClass) {
        switch tree {
        case .main: display.layout = node
        case .compact: display.compact = node
        case .wide: display.wide = node
        }
    }

    static func node(at ref: CustomNodeRef, in display: Display) -> CustomNode? {
        guard var node = root(of: display, tree: ref.tree) else { return nil }
        for index in ref.path {
            guard let children = node.children, children.indices.contains(index) else { return nil }
            node = children[index]
        }
        return node
    }

    static func update(_ display: inout Display, at ref: CustomNodeRef, _ change: (inout CustomNode) -> Void) {
        guard var root = root(of: display, tree: ref.tree) else { return }
        modify(&root, path: ref.path[...], change)
        setRoot(root, of: &display, tree: ref.tree)
    }

    @discardableResult
    static func insert(_ node: CustomNode, near ref: CustomNodeRef?, in display: inout Display, tree: CustomSizing.SizeClass) -> CustomNodeRef {
        guard var root = root(of: display, tree: tree) else {
            setRoot(CustomNode(type: .vstack, children: [node], spacing: 4), of: &display, tree: tree)
            return CustomNodeRef(tree: tree, path: [0])
        }
        if !root.type.isContainer {
            root = CustomNode(type: .vstack, children: [root], spacing: 4)
            setRoot(root, of: &display, tree: tree)
        }
        let target = ref.flatMap { $0.tree == tree ? self.node(at: $0, in: display) : nil }
        let (parent, index): (CustomNodeRef, Int) = {
            guard let ref, ref.tree == tree, let target else { return (CustomNodeRef(tree: tree, path: []), root.children?.count ?? 0) }
            if target.type.isContainer { return (ref, target.children?.count ?? 0) }
            guard let parent = ref.parent else { return (CustomNodeRef(tree: tree, path: []), root.children?.count ?? 0) }
            return (parent, (ref.path.last ?? 0) + 1)
        }()
        update(&display, at: parent) { container in
            var children = container.children ?? []
            children.insert(node, at: min(index, children.count))
            container.children = children
        }
        return CustomNodeRef(tree: tree, path: parent.path + [index])
    }

    @discardableResult
    static func remove(at ref: CustomNodeRef, in display: inout Display) -> CustomNodeRef? {
        guard let parent = ref.parent, let index = ref.path.last else {
            setRoot(nil, of: &display, tree: ref.tree)
            return nil
        }
        var remaining = 0
        update(&display, at: parent) { container in
            container.children?.remove(at: index)
            remaining = container.children?.count ?? 0
        }
        if remaining == 0 { return parent.path.isEmpty ? nil : parent }
        return CustomNodeRef(tree: ref.tree, path: parent.path + [min(index, remaining - 1)])
    }

    @discardableResult
    static func move(at ref: CustomNodeRef, by offset: Int, in display: inout Display) -> CustomNodeRef {
        guard let parent = ref.parent, let index = ref.path.last,
              let count = node(at: parent, in: display)?.children?.count else { return ref }
        let target = index + offset
        guard (0..<count).contains(target) else { return ref }
        update(&display, at: parent) { container in container.children?.swapAt(index, target) }
        return CustomNodeRef(tree: ref.tree, path: parent.path + [target])
    }

    static func bind(_ name: String, to ref: CustomNodeRef, in display: inout Display) {
        update(&display, at: ref) { node in
            let token = "{\(name)}"
            switch node.type {
            case .ring, .bar:
                node.value = name
            case .timer:
                node.since = name
            case .text, .pill:
                let current = node.text ?? ""
                node.text = current.isEmpty || isSinglePlaceholder(current) ? token : current + " " + token
            default:
                break
            }
        }
    }

    static func customize(_ tree: CustomSizing.SizeClass, in display: inout Display) {
        guard tree != .main, root(of: display, tree: tree) == nil,
              let layout = CustomSizing.layout(of: display, for: tree) else { return }
        setRoot(stripped(layout), of: &display, tree: tree)
    }

    static func stripped(_ node: CustomNode) -> CustomNode {
        var out = node
        out.ref = nil
        out.children = node.children?.map(stripped)
        return out
    }

    private static func isSinglePlaceholder(_ text: String) -> Bool {
        text.wholeMatch(of: /\{\w+\}/) != nil
    }

    private static func modify(_ node: inout CustomNode, path: ArraySlice<Int>, _ change: (inout CustomNode) -> Void) {
        guard let index = path.first else { return change(&node) }
        guard var children = node.children, children.indices.contains(index) else { return }
        modify(&children[index], path: path.dropFirst(), change)
        node.children = children
    }
}
