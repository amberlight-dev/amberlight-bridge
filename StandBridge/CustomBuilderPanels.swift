import SwiftUI

struct CustomBuilderSidebar: View {
    let names: [String]
    let texts: [String: String]
    let onValue: (String) -> Void
    let onBlock: (CustomBlock) -> Void

    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section(String(localized: "Werte")) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(names, id: \.self) { name in
                            Button { onValue(name) } label: { chip(name) }
                                .buttonStyle(.plain)
                                .draggable(CustomBlock.valuePrefix + name) { chip(name) }
                                .help("Auf einen Baustein ziehen bindet ihn an {\(name)}")
                        }
                    }
                }
                section(String(localized: "Bausteine")) {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(CustomBlock.allCases) { block in
                            Button { onBlock(block) } label: { tile(block) }
                                .buttonStyle(.plain)
                                .draggable(CustomBlock.dragPrefix + block.rawValue) { tile(block) }
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func chip(_ name: String) -> some View {
        HStack(spacing: 6) {
            Text("{\(name)}")
                .font(.system(.callout, design: .monospaced).weight(.medium))
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            Text(texts[name] ?? "–")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.35)))
        .contentShape(Capsule())
    }

    private func tile(_ block: CustomBlock) -> some View {
        VStack(spacing: 4) {
            Image(systemName: block.symbol).font(.title3)
            Text(block.title).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        .contentShape(.rect(cornerRadius: 8))
    }
}

struct CustomLayoutOutline: View {
    let root: CustomNode?
    let tree: CustomSizing.SizeClass
    @Binding var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ebenen").font(.headline).padding([.horizontal, .top], 14).padding(.bottom, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if let root {
                        rows(root, path: [], depth: 0)
                    } else {
                        Text("Noch leer").font(.callout).foregroundStyle(.secondary).padding(.horizontal, 14)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rows(_ node: CustomNode, path: [Int], depth: Int) -> AnyView {
        let ref = CustomNodeRef(tree: tree, path: path).id
        return AnyView(VStack(alignment: .leading, spacing: 1) {
            Button { selection = ref } label: {
                HStack(spacing: 6) {
                    Image(systemName: Self.symbol(node.type)).frame(width: 16)
                    Text(Self.summary(node)).lineLimit(1)
                    Spacer()
                }
                .padding(.leading, CGFloat(depth) * 14 + 6)
                .padding(.vertical, 4)
                .padding(.trailing, 6)
                .background(selection == ref ? Color.accentColor.opacity(0.2) : .clear, in: .rect(cornerRadius: 5))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            ForEach(Array((node.children ?? []).enumerated()), id: \.offset) { index, child in
                rows(child, path: path + [index], depth: depth + 1)
            }
        })
    }

    static func symbol(_ kind: CustomNode.Kind) -> String {
        switch kind {
        case .vstack: "rectangle.split.1x2"
        case .hstack: "rectangle.split.3x1"
        case .zstack: "square.stack"
        case .spacer: "arrow.up.and.down"
        case .divider: "minus"
        case .text: "textformat"
        case .symbol: "star"
        case .dot: "circle.fill"
        case .timer: "timer"
        case .ring: "circle.dashed"
        case .bar: "minus.rectangle"
        case .line: "chart.xyaxis.line"
        case .bars: "chart.bar"
        case .list: "list.bullet"
        case .pill: "capsule.inset.filled"
        }
    }

    static func summary(_ node: CustomNode) -> String {
        switch node.type {
        case .vstack: String(localized: "Spalte")
        case .hstack: String(localized: "Zeile")
        case .zstack: "Ebenen"
        case .spacer: "Abstand"
        case .divider: String(localized: "Trenner")
        case .text: node.text ?? "Text"
        case .pill: String(localized: "Pille ") + (node.text ?? "")
        case .symbol: node.text ?? String(localized: "Icon")
        case .dot: String(localized: "Punkt")
        case .timer: String(localized: "Timer")
        case .ring: String(localized: "Ring ") + (node.value.map { "{\($0)}" } ?? "")
        case .bar: String(localized: "Fortschritt ") + (node.value.map { "{\($0)}" } ?? "")
        case .line: String(localized: "Linie")
        case .bars: String(localized: "Balken")
        case .list: "Liste"
        }
    }
}
