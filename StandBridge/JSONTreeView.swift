import SwiftUI

struct JSONNode: Identifiable {
    enum Kind { case object, array, scalar }

    let id: String
    let key: String
    let preview: String
    let kind: Kind
    var children: [JSONNode]?

    static let childLimit = 25

    static func tree(_ json: Any) -> [JSONNode] {
        var budget = 1500
        return [node(json, key: "Antwort", path: "", budget: &budget)]
    }

    private static func node(_ value: Any, key: String, path: String, budget: inout Int) -> JSONNode {
        budget -= 1
        switch value {
        case let object as [String: Any]:
            var children: [JSONNode] = []
            for name in object.keys.sorted() where budget > 0 {
                children.append(node(object[name]!, key: name, path: JSONPath.appending(.key(name), to: path), budget: &budget))
            }
            return JSONNode(id: path, key: key, preview: "{\(object.count)}", kind: .object, children: children)
        case let array as [Any]:
            var children: [JSONNode] = []
            for (index, element) in array.prefix(childLimit).enumerated() where budget > 0 {
                children.append(node(element, key: "[\(index)]", path: JSONPath.appending(.index(index), to: path), budget: &budget))
            }
            return JSONNode(id: path, key: key, preview: "[\(array.count)]", kind: .array, children: children)
        default:
            let text = JSONPath.text(value) ?? "null"
            return JSONNode(id: path, key: key, preview: value is String ? "\"\(text.prefix(80))\"" : text, kind: .scalar)
        }
    }
}

struct JSONTreeView: View {
    let nodes: [JSONNode]
    let selected: Set<String>
    let onValue: (String) -> Void
    let onArray: (String) -> Void
    let onField: (String, CustomFieldRole) -> Void
    let onBind: (String) -> Void

    var body: some View {
        List {
            ForEach(nodes) { node in
                JSONNodeRow(node: node, depth: 0, tree: self)
            }
        }
        .listStyle(.bordered)
        .alternatingRowBackgrounds()
        .font(.system(.callout, design: .monospaced))
    }
}

private struct JSONNodeRow: View {
    let node: JSONNode
    let depth: Int
    let tree: JSONTreeView

    @State private var expanded: Bool

    init(node: JSONNode, depth: Int, tree: JSONTreeView) {
        self.node = node
        self.depth = depth
        self.tree = tree
        _expanded = State(initialValue: depth < 2)
    }

    var body: some View {
        if let children = node.children, !children.isEmpty {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(children) { child in
                    JSONNodeRow(node: child, depth: depth + 1, tree: tree)
                }
            } label: {
                row
            }
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            Text(node.key)
                .fontWeight(.semibold)
            Text(node.preview)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if tree.selected.contains(node.id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
            if node.kind == .scalar {
                Button("Im Widget zeigen", systemImage: "plus.circle.fill") { tree.onBind(node.id) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tint)
                    .help("Als Feld im Widget zeigen")
            }
            actions
        }
        .contentShape(.rect)
        .onTapGesture(perform: primary)
        .help(node.id.isEmpty ? "Wurzel" : node.id)
    }

    private func primary() {
        switch node.kind {
        case .scalar: tree.onValue(node.id)
        case .array: tree.onArray(node.id)
        case .object: expanded.toggle()
        }
    }

    @ViewBuilder
    private var actions: some View {
        let field = JSONPath.elementSplit(node.id)
        Menu {
            if node.kind == .scalar {
                Button("Als Wert verwenden") { tree.onValue(node.id) }
            }
            if node.kind == .array {
                Button("Als Liste bzw. Reihe verwenden") { tree.onArray(node.id) }
            }
            if let field, node.kind == .scalar {
                Divider()
                ForEach(CustomFieldRole.allCases) { role in
                    Button("\(role.title): \(field.field)") { tree.onField(node.id, role) }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .opacity(node.kind == .object ? 0 : 1)
        .disabled(node.kind == .object)
    }
}

enum CustomFieldRole: String, CaseIterable, Identifiable {
    case aggregated, label, series

    var id: Self { self }

    var title: String {
        switch self {
        case .aggregated: "Feld für die Aggregation"
        case .label: "Label der Reihe"
        case .series: "Wert der Reihe"
        }
    }
}
