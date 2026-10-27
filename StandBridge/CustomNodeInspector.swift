import SwiftUI

struct CustomNodeInspector: View {
    let node: CustomNode
    let names: [String]
    let values: [CustomWidgetDefinition.NamedValue]
    let onChange: (String, @escaping (inout CustomNode) -> Void) -> Void
    let onFormat: (String, CustomWidgetDefinition.NumberFormat?) -> Void
    var timerPreview: String?
    var onSetupRunning: () -> Void = {}
    let onMove: (Int) -> Void
    let onDelete: () -> Void

    private enum ColorChoice: Hashable {
        case standard, accent, status, custom
        case tone(CustomWidgetDisplay.Tone)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
            appearance
            visibility
        }
        .textFieldStyle(.roundedBorder)
    }

    private var header: some View {
        HStack {
            Label(CustomLayoutOutline.summary(node), systemImage: CustomLayoutOutline.symbol(node.type))
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Group {
                Button("Nach oben", systemImage: "arrow.up") { onMove(-1) }
                Button("Nach unten", systemImage: "arrow.down") { onMove(1) }
                Button("Löschen", systemImage: "trash", role: .destructive, action: onDelete)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch node.type {
        case .text, .pill:
            group("Inhalt") {
                HStack(spacing: 6) {
                    TextField("Text", text: text(\.text), prompt: Text("{wert} oder freier Text"))
                    Menu {
                        ForEach(names, id: \.self) { name in
                            Button("{\(name)}") { change("text") { $0.text = ($0.text ?? "") + "{\(name)}" } }
                        }
                    } label: { Image(systemName: "plus.circle") }
                        .menuIndicator(.hidden)
                        .fixedSize()
                }
                if let name = boundName {
                    Picker("Format", selection: Binding(
                        get: { values.first { $0.name == name }?.format },
                        set: { onFormat(name, $0) }
                    )) {
                        Text("Wie das Widget").tag(CustomWidgetDefinition.NumberFormat?.none)
                        ForEach(CustomWidgetDefinition.NumberFormat.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                }
                if node.type == .text {
                    Stepper("Zeilen: \(node.lines ?? 1)", value: Binding(get: { node.lines ?? 1 }, set: { new in change("lines") { $0.lines = new == 1 ? nil : new } }), in: 1...4)
                }
            }
            if node.type == .pill { pillRules }
        case .ring, .bar:
            group("Wert") {
                namePicker("Wert", key: \.value)
                LabeledContent("Maximum") { TextField("Maximum", text: text(\.max), prompt: Text("100 oder {wert}")).labelsHidden() }
            }
        case .timer:
            group("Zeit") {
                namePicker("Startzeit", key: \.since, extra: ["now"])
                namePicker("Bereits erfasst", key: \.plus)
                Picker("Einheit", selection: Binding(get: { node.plusUnit ?? "hours" }, set: { new in change("plusUnit") { $0.plusUnit = new == "hours" ? nil : new } })) {
                    Text("h").tag("hours")
                    Text("min").tag("minutes")
                    Text("s").tag("seconds")
                }
                .pickerStyle(.segmented)
                .disabled(node.plus == nil)
                if let timerPreview {
                    LabeledContent("Zeigt jetzt") {
                        Text(timerPreview).monospacedDigit().font(.body.weight(.semibold))
                    }
                }
                Text("Angezeigt wird „Bereits erfasst“ plus die Zeit seit der Startzeit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("MOCO-Timer einrichten", systemImage: "wand.and.stars", action: onSetupRunning)
                    .help("Legt running, runningStart und runningSeconds an und verbindet diesen Timer damit")
            }
        case .symbol:
            group("Icon") {
                HStack {
                    TextField("SF Symbol", text: text(\.text), prompt: Text("star.fill"))
                    Image(systemName: node.text ?? "questionmark").frame(width: 24)
                }
                Toggle("Pulsieren", isOn: flag(\.pulse))
            }
        case .dot:
            group("Punkt") { Toggle("Pulsieren", isOn: flag(\.pulse)) }
        case .vstack, .hstack:
            group(node.type == .vstack ? "Spalte" : "Zeile") {
                if node.type == .vstack {
                    Picker("Ausrichtung", selection: Binding(get: { node.align ?? .leading }, set: { new in change("align") { $0.align = new } })) {
                        Text("Links").tag(CustomNode.Align.leading)
                        Text("Mitte").tag(CustomNode.Align.center)
                        Text("Rechts").tag(CustomNode.Align.trailing)
                    }
                    .pickerStyle(.segmented)
                }
                LabeledContent("Abstand") {
                    Slider(value: Binding(get: { node.spacing ?? 4 }, set: { new in change("spacing") { $0.spacing = new.rounded() } }), in: 0...24)
                }
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var appearance: some View {
        let sized: Set<CustomNode.Kind> = [.text, .pill, .timer, .symbol]
        let colored: Set<CustomNode.Kind> = [.text, .pill, .timer, .symbol, .ring, .bar, .dot]
        if sized.contains(node.type) || colored.contains(node.type) {
            group("Darstellung") {
                if sized.contains(node.type) {
                    Picker("Größe", selection: Binding(get: { node.size ?? .m }, set: { new in change("size") { $0.size = new } })) {
                        Text("Label").tag(CustomNode.Size.xs)
                        Text("Klein").tag(CustomNode.Size.s)
                        Text("Normal").tag(CustomNode.Size.m)
                        Text("Groß").tag(CustomNode.Size.l)
                        Text("Riesig").tag(CustomNode.Size.xl)
                    }
                    Toggle("Fett", isOn: flag(\.bold))
                }
                if colored.contains(node.type) { colorPicker }
            }
        }
    }

    private var known: Set<String> { Set(names + ["now"]) }

    @ViewBuilder
    private func missing(_ referenced: [String?]) -> some View {
        let absent = referenced.compactMap { $0 }.filter { !$0.isEmpty && !known.contains($0) }
        ForEach(Array(Set(absent)).sorted(), id: \.self) { name in
            Label("Wert „\(name)“ fehlt", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var visibility: some View {
        group("Sichtbarkeit") {
            TextField("Nur zeigen, wenn", text: text(\.when), prompt: Text("z. B. running >= 1"))
            missing(CustomLayout.referencedNames(in: node.when) + (node.toneWhen ?? []).flatMap { CustomLayout.referencedNames(in: $0.when) } + [node.since, node.plus, node.value])
            Picker("Für kleine Größen", selection: Binding(get: { node.priority ?? 0 }, set: { new in change("priority") { $0.priority = new == 0 ? nil : new } })) {
                Text("Normal").tag(0)
                Text("Wichtig").tag(1)
                Text("Am wichtigsten").tag(2)
            }
        }
    }

    private var pillRules: some View {
        group("Schwellwerte") {
            ForEach(Array((node.toneWhen ?? []).enumerated()), id: \.offset) { index, rule in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        TextField("Bedingung", text: Binding(get: { rule.when }, set: { new in change("rule\(index)") { $0.toneWhen?[index].when = new } }), prompt: Text("value >= 1"))
                        Button("Entfernen", systemImage: "minus.circle") { change("rules") { $0.toneWhen?.remove(at: index) } }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                    HStack(spacing: 6) {
                        Picker("Farbe", selection: Binding(get: { rule.tone }, set: { new in change("rules") { $0.toneWhen?[index].tone = new } })) {
                            ForEach(CustomWidgetDisplay.Tone.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        TextField("Text", text: Binding(get: { rule.label ?? "" }, set: { new in change("label\(index)") { $0.toneWhen?[index].label = new.isEmpty ? nil : new } }), prompt: Text("Text"))
                    }
                }
                .padding(8)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))
            }
            Button("Schwellwert hinzufügen", systemImage: "plus") {
                change("rules") { $0.toneWhen = ($0.toneWhen ?? []) + [.init(when: "value >= 1", tone: .green, label: nil)] }
            }
            .buttonStyle(.borderless)
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Farbe", selection: Binding(get: { colorChoice }, set: { setColor($0) })) {
                Text("Standard").tag(ColorChoice.standard)
                Text("Akzent").tag(ColorChoice.accent)
                Text("Status-Ton").tag(ColorChoice.status)
                Divider()
                ForEach(CustomWidgetDisplay.Tone.allCases) { Text($0.title).tag(ColorChoice.tone($0)) }
                Divider()
                Text("Eigene").tag(ColorChoice.custom)
            }
            if colorChoice == .custom {
                ColorPicker("Eigene Farbe", selection: Binding(
                    get: { node.color.flatMap(StandAccent.color(hex:)) ?? .white },
                    set: { new in change("color") { $0.color = StandAccent.hex(of: new) } }
                ), supportsOpacity: false)
            }
        }
    }

    private var colorChoice: ColorChoice {
        switch node.color {
        case "accent": .accent
        case "status": .status
        case .some: .custom
        case nil: node.tone.map(ColorChoice.tone) ?? .standard
        }
    }

    private func setColor(_ choice: ColorChoice) {
        change("color") { node in
            switch choice {
            case .standard: node.color = nil; node.tone = nil
            case .accent: node.color = "accent"; node.tone = nil
            case .status: node.color = "status"; node.tone = nil
            case .custom: node.color = node.color.flatMap { StandAccent.color(hex: $0) == nil ? nil : $0 } ?? StandAccent.amberHex
            case .tone(let tone): node.color = nil; node.tone = tone
            }
        }
    }

    private var boundName: String? {
        guard let text = node.text, let match = text.wholeMatch(of: /\{(\w+)\}/) else { return nil }
        let name = String(match.1)
        return values.contains { $0.name == name } ? name : nil
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func change(_ key: String, _ update: @escaping (inout CustomNode) -> Void) {
        onChange(key, update)
    }

    private func text(_ key: WritableKeyPath<CustomNode, String?>) -> Binding<String> {
        Binding(get: { node[keyPath: key] ?? "" }, set: { new in change("\(key)") { $0[keyPath: key] = new.isEmpty ? nil : new } })
    }

    private func flag(_ key: WritableKeyPath<CustomNode, Bool?>) -> Binding<Bool> {
        Binding(get: { node[keyPath: key] ?? false }, set: { new in change("\(key)") { $0[keyPath: key] = new ? true : nil } })
    }

    private func namePicker(_ title: String, key: WritableKeyPath<CustomNode, String?>, extra: [String] = []) -> some View {
        Picker(title, selection: Binding(get: { node[keyPath: key] ?? "" }, set: { new in change("\(key)") { $0[keyPath: key] = new.isEmpty ? nil : new } })) {
            Text("–").tag("")
            ForEach(extra + names, id: \.self) { Text("{\($0)}").tag($0) }
        }
    }
}
