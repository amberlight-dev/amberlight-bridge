import SwiftUI

struct CustomDisplaySection: View {
    @Binding var display: CustomWidgetDefinition.Display

    var body: some View {
        Section {
            Picker("Darstellung", selection: $display.style) {
                ForEach(CustomWidgetDisplay.Style.allCases) { style in
                    Label(style.title, systemImage: style.symbol).tag(style)
                }
            }
            TextField("Beschriftung", text: $display.caption, prompt: Text("wie der Name"))
            Picker("Zahlenformat", selection: $display.format) {
                ForEach(CustomWidgetDefinition.NumberFormat.allCases) { Text($0.title).tag($0) }
            }
            if display.format != .hoursMinutes {
                Stepper("Nachkommastellen: \(display.decimals)", value: $display.decimals, in: 0...6)
            }
            HStack {
                TextField("Präfix", text: $display.prefix, prompt: Text("Präfix"))
                TextField("Einheit", text: $display.unit, prompt: Text("Einheit"))
                TextField("Suffix", text: $display.suffix, prompt: Text("Suffix"))
            }
            if display.style == .gauge {
                HStack {
                    TextField("Minimum", value: $display.gaugeMin, format: .number)
                    TextField("Maximum", value: $display.gaugeMax, format: .number)
                }
            }
            if display.style == .status { rules }
        } header: {
            Text("Darstellung")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        switch display.style {
        case .line: "Den Verlauf speichert die Bridge selbst – mit jedem Abruf ein Punkt, bis zu \(CustomWidgetStore.historyLimit)."
        case .status: "Die erste passende Regel bestimmt Farbe und Text. Passt keine, wird der Wert grau gezeigt."
        case .bar, .list: "Braucht eine Reihe aus Schritt 6. Klein zeigt das Widget den Kernwert."
        case .text, .gauge: "1×1 zeigt den Kernwert, 2×1 dazu die Beschriftung, ab 2×2 die volle Darstellung."
        }
    }

    private var rules: some View {
        LabeledContent("Regeln") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach($display.rules) { $rule in
                    HStack(spacing: 6) {
                        Picker("Vergleich", selection: $rule.comparison) {
                            ForEach(CustomWidgetDefinition.Comparison.allCases) { Text($0.title).tag($0) }
                        }
                        .frame(width: 120)
                        TextField("Wert", text: $rule.operand, prompt: Text("Wert"))
                            .frame(width: 80)
                        Picker("Farbe", selection: $rule.tone) {
                            ForEach(CustomWidgetDisplay.Tone.allCases) { Text($0.title).tag($0) }
                        }
                        .frame(width: 90)
                        TextField("Text", text: $rule.label, prompt: Text("Text (optional)"))
                        Button("Entfernen", systemImage: "minus.circle") { display.rules.removeAll { $0.id == rule.id } }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                    .labelsHidden()
                }
                Button("Regel hinzufügen", systemImage: "plus") { display.rules.append(.init()) }
                    .buttonStyle(.borderless)
            }
        }
    }
}
