import Observation
import SwiftUI

@Observable
final class LayoutHistory {
    private(set) var past: [CustomWidgetDefinition] = []
    private(set) var future: [CustomWidgetDefinition] = []
    @ObservationIgnored private var lastKey: String?
    @ObservationIgnored private var lastAt = Date.distantPast

    static let limit = 100

    func record(_ state: CustomWidgetDefinition, key: String? = nil, now: Date = .now) {
        defer {
            lastKey = key
            lastAt = now
        }
        if let key, key == lastKey, now.timeIntervalSince(lastAt) < 1 { return }
        past = Array((past + [state]).suffix(Self.limit))
        future = []
    }

    func undo(_ current: CustomWidgetDefinition) -> CustomWidgetDefinition? {
        guard let previous = past.popLast() else { return nil }
        future.append(current)
        lastKey = nil
        return previous
    }

    func redo(_ current: CustomWidgetDefinition) -> CustomWidgetDefinition? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        lastKey = nil
        return next
    }
}

enum PreviewSize: String, CaseIterable, Identifiable {
    case small, wide, square, large

    var id: Self { self }

    var span: GridSpan {
        switch self {
        case .small: GridSpan(w: 1, h: 1)
        case .wide: GridSpan(w: 2, h: 1)
        case .square: GridSpan(w: 2, h: 2)
        case .large: GridSpan(w: 4, h: 2)
        }
    }

    var title: String { "\(span.w)×\(span.h)" }
    var sizeClass: CustomSizing.SizeClass { CustomSizing.sizeClass(for: span) }
}

struct CustomLayoutBuilder: View {
    @Binding var draft: CustomWidgetDefinition
    let json: Any?
    let history: [CustomWidgetDisplay.Sample]
    let undo: LayoutHistory

    @State private var size = PreviewSize.square
    @State private var selection: String?
    @FocusState private var focused: Bool

    private let cell: CGFloat = 100
    private let gap: CGFloat = 8

    var body: some View {
        HStack(spacing: 0) {
            CustomBuilderSidebar(
                names: valueNames, texts: texts,
                onValue: { tapValue($0) }, onBlock: { add($0, near: selectedRef) }
            )
            .frame(width: 230)
            Divider()
            center
                .frame(minWidth: 300, maxWidth: .infinity)
            Divider()
            inspectorColumn
                .frame(width: 260)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onDeleteCommand(perform: deleteSelection)
        .onMoveCommand { direction in
            switch direction {
            case .up, .left: moveSelection(by: -1)
            case .down, .right: moveSelection(by: 1)
            @unknown default: break
            }
        }
        .onAppear {
            if let raw = UserDefaults.standard.string(forKey: "builderSize"), let initial = PreviewSize(rawValue: raw) { size = initial }
            selection = UserDefaults.standard.string(forKey: "builderSelect")
        }
    }

    private var center: some View {
        VStack(spacing: 14) {
            HStack {
                Picker("Größe", selection: $size) {
                    ForEach(PreviewSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                Spacer()
                Button("Rückgängig", systemImage: "arrow.uturn.backward") { step(undo.undo) }
                    .keyboardShortcut("z")
                    .disabled(undo.past.isEmpty)
                Button("Wiederholen", systemImage: "arrow.uturn.forward") { step(undo.redo) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(undo.future.isEmpty)
            }
            .labelStyle(.iconOnly)
            sizeBanner
            GeometryReader { proxy in
                canvas(cell: fittingCell(in: proxy.size))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text("Bausteine und Werte links per Drag & Drop in die Vorschau ziehen oder anklicken. Entf löscht, Pfeiltasten verschieben.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(18)
    }

    @ViewBuilder
    private var sizeBanner: some View {
        let tree = size.sizeClass
        if tree != .main {
            HStack(spacing: 10) {
                if CustomLayoutEditing.root(of: draft.display, tree: tree) == nil {
                    Label(CustomSizing.usesDerivation(draft.display) || draft.display.layout == nil
                          ? "Automatisch aus der Hauptgröße abgeleitet"
                          : "Das Layout regelt diese Größe selbst", systemImage: "wand.and.stars")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Für diese Größe anpassen") {
                        mutate { CustomLayoutEditing.customize(tree, in: &$0.display) }
                        selection = nil
                    }
                    .disabled(draft.display.layout == nil)
                } else {
                    Label("Eigene Anordnung für \(size.title)", systemImage: "pencil.and.outline")
                    Spacer()
                    Button("Zurücksetzen") {
                        mutate { CustomLayoutEditing.setRoot(nil, of: &$0.display, tree: tree) }
                        selection = nil
                    }
                }
            }
            .font(.callout)
            .buttonStyle(.bordered)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        }
    }

    private func fittingCell(in available: CGSize) -> CGFloat {
        let span = size.span
        let byWidth = (available.width - 24 - CGFloat(span.w - 1) * gap) / CGFloat(span.w)
        let byHeight = (available.height - 24 - CGFloat(span.h - 1) * gap) / CGFloat(span.h)
        return max(44, min(cell, byWidth, byHeight))
    }

    private func canvas(cell: CGFloat) -> some View {
        let span = size.span
        let width = CGFloat(span.w) * cell + CGFloat(span.w - 1) * gap
        let height = CGFloat(span.h) * cell + CGFloat(span.h - 1) * gap
        return ZStack {
            if let display = preview, display.root != nil {
                CustomWidgetView(display: display, span: span, dimmed: false, notice: "")
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "square.dashed.inset.filled").font(.title2)
                    Text("Bausteine hierher ziehen").font(.caption)
                }
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
            }
        }
        .padding(12)
        .frame(width: width, height: height)
        .background(Color(white: 0.08), in: .rect(cornerRadius: 16, style: .continuous))
        .environment(\.colorScheme, .dark)
        .environment(\.customNodeEditing, CustomNodeEditing(
            selected: selection,
            select: { ref in
                selection = ref
                focused = true
            },
            drop: { payload, ref in handleDrop(payload, on: ref.flatMap(CustomNodeRef.init)) }
        ))
        .dropDestination(for: String.self) { items, _ in
            items.first.map { handleDrop($0, on: nil) } ?? false
        }
        .onTapGesture { selection = nil }
        .animation(.smooth(duration: 0.25), value: size)
    }

    private var inspectorColumn: some View {
        VStack(spacing: 0) {
            CustomLayoutOutline(root: activeRoot, tree: activeTree, selection: $selection)
                .frame(maxHeight: 220)
            Divider()
            ScrollView {
                if let ref = selectedRef, let node = CustomLayoutEditing.node(at: ref, in: draft.display) {
                    CustomNodeInspector(
                        node: node, names: valueNames, values: draft.values ?? [],
                        onChange: { key, change in mutate(key: "\(ref.id)-\(key)") { CustomLayoutEditing.update(&$0.display, at: ref, change) } },
                        onFormat: { name, format in
                            mutate { definition in
                                guard let index = definition.values?.firstIndex(where: { $0.name == name }) else { return }
                                definition.values?[index].format = format
                            }
                        },
                        timerPreview: timerPreview(for: node),
                        onSetupRunning: {
                            mutate { definition in
                                CustomTimerRepair.addRunningValues(to: &definition)
                                CustomLayoutEditing.update(&definition.display, at: ref) { CustomTimerRepair.bindRunning(&$0) }
                            }
                        },
                        onMove: { moveSelection(by: $0) },
                        onDelete: deleteSelection
                    )
                    .padding(14)
                } else {
                    ContentUnavailableView("Nichts ausgewählt", systemImage: "cursorarrow.click.2",
                                           description: Text("Klick einen Baustein in der Vorschau oder in den Ebenen an."))
                        .padding(.top, 30)
                }
            }
        }
    }

    private func timerPreview(for node: CustomNode) -> String? {
        guard node.type == .timer, let json,
              let start = CustomLayout.timerStart(node, CustomLayout.scope(for: draft, json: json, at: .now)) else { return nil }
        let seconds = Int(max(0, Date.now.timeIntervalSince(start)))
        return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    private var valueNames: [String] {
        ["value", "caption"] + (draft.values ?? []).map(\.name)
    }

    private var texts: [String: String] {
        guard let json else { return [:] }
        return CustomLayout.scope(for: draft, json: json, at: .now).text
    }

    private var activeTree: CustomSizing.SizeClass {
        let tree = size.sizeClass
        return tree != .main && CustomLayoutEditing.root(of: draft.display, tree: tree) != nil ? tree : .main
    }

    private var activeRoot: CustomNode? {
        CustomLayoutEditing.root(of: draft.display, tree: activeTree)
    }

    private var selectedRef: CustomNodeRef? {
        selection.flatMap(CustomNodeRef.init)
    }

    private var preview: CustomWidgetDisplay? {
        guard draft.display.layout != nil else { return nil }
        let samples = history.count > 1 ? history : (0..<12).map { index in
            CustomWidgetDisplay.Sample(at: .now.addingTimeInterval(Double(index - 12) * 900), value: 50 + sin(Double(index) / 2) * 12)
        }
        return CustomEvaluator.display(for: draft, json: json ?? [String: Any](), history: samples, editing: true)
    }

    private func mutate(key: String? = nil, _ change: (inout CustomWidgetDefinition) -> Void) {
        var next = draft
        change(&next)
        guard next != draft else { return }
        undo.record(draft, key: key)
        draft = next
    }

    private func step(_ action: (CustomWidgetDefinition) -> CustomWidgetDefinition?) {
        guard let restored = action(draft) else { return }
        draft = restored
        if let ref = selectedRef, CustomLayoutEditing.node(at: ref, in: draft.display) == nil { selection = nil }
    }

    private func add(_ block: CustomBlock, near ref: CustomNodeRef?) {
        var inserted: CustomNodeRef?
        mutate { inserted = CustomLayoutEditing.insert(block.node, near: ref, in: &$0.display, tree: activeTree) }
        selection = inserted?.id
        focused = true
    }

    private func tapValue(_ name: String) {
        if let ref = selectedRef, let node = CustomLayoutEditing.node(at: ref, in: draft.display), !node.type.isContainer {
            mutate { CustomLayoutEditing.bind(name, to: ref, in: &$0.display) }
        } else {
            var inserted: CustomNodeRef?
            mutate { inserted = CustomLayoutEditing.insert(CustomNode(type: .text, text: "{\(name)}", size: .m), near: selectedRef, in: &$0.display, tree: activeTree) }
            selection = inserted?.id
        }
    }

    private func handleDrop(_ payload: String, on ref: CustomNodeRef?) -> Bool {
        if payload.hasPrefix(CustomBlock.dragPrefix), let block = CustomBlock(rawValue: String(payload.dropFirst(CustomBlock.dragPrefix.count))) {
            add(block, near: ref.flatMap { $0.tree == activeTree ? $0 : nil })
            return true
        }
        guard payload.hasPrefix(CustomBlock.valuePrefix) else { return false }
        let name = String(payload.dropFirst(CustomBlock.valuePrefix.count))
        if let ref, let node = CustomLayoutEditing.node(at: ref, in: draft.display), !node.type.isContainer {
            mutate { CustomLayoutEditing.bind(name, to: ref, in: &$0.display) }
            selection = ref.id
        } else {
            var inserted: CustomNodeRef?
            mutate { inserted = CustomLayoutEditing.insert(CustomNode(type: .text, text: "{\(name)}", size: .m), near: ref, in: &$0.display, tree: activeTree) }
            selection = inserted?.id
        }
        focused = true
        return true
    }

    private func deleteSelection() {
        guard let ref = selectedRef else { return }
        var next: CustomNodeRef?
        mutate { next = CustomLayoutEditing.remove(at: ref, in: &$0.display) }
        selection = next?.id
    }

    private func moveSelection(by offset: Int) {
        guard let ref = selectedRef else { return }
        var moved = ref
        mutate { moved = CustomLayoutEditing.move(at: ref, by: offset, in: &$0.display) }
        selection = moved.id
    }
}
