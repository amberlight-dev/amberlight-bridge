import SwiftUI

struct CustomSelectionSection: View {
    @Binding var selection: CustomWidgetDefinition.Selection

    var body: some View {
        Section {
            Picker("Quelle", selection: aggregates) {
                Text("Einzelner Wert").tag(false)
                Text("Aus einer Liste berechnet").tag(true)
            }
            .pickerStyle(.segmented)
            if selection.arrayPath == nil {
                pathField(String(localized: "Pfad zum Wert"), text: $selection.valuePath, prompt: "data.items[0].hours")
            } else {
                pathField(String(localized: "Pfad zur Liste"), text: optional(\.arrayPath), prompt: String(localized: "data.items (leer = Wurzel)"))
                pathField(String(localized: "Feld im Element"), text: $selection.valueField, prompt: String(localized: "hours (leer = Element)"))
                Picker("Aggregation", selection: $selection.aggregation) {
                    ForEach(CustomWidgetDefinition.Aggregation.allCases) { Text($0.title).tag($0) }
                }
            }
            TextField("Filter", text: optional(\.filter), prompt: Text("Listenelemente: timer_started_at oder status == active"))
                .font(.system(.body, design: .monospaced))
            Toggle("Reihe für Balken bzw. Liste", isOn: hasSeries)
            if selection.seriesPath != nil {
                pathField(String(localized: "Pfad zur Reihe"), text: optional(\.seriesPath), prompt: String(localized: "data.items (leer = Wurzel)"))
                pathField(String(localized: "Feld für Label"), text: $selection.labelField, prompt: "date")
                pathField(String(localized: "Feld für Wert"), text: $selection.seriesField, prompt: "hours")
                Toggle("Gleiche Labels zusammenzählen", isOn: $selection.groupsLabels)
                Toggle("Labels sind Datumswerte (als Wochentag zeigen)", isOn: $selection.labelsAreDates)
            }
        } header: {
            Text("Hauptwert")
        } footer: {
            Text("Klick im Antwort-Baum rechts setzt den Pfad, das Menü ⋯ belegt Felder einer Liste. Pfade sind nur Schlüssel und Indizes wie data.items[0].hours – Der Filter kennt nur „Feld“, „Feld == Wert“ und „Feld != Wert“. Mehrere Werte und Zusatzzeilen definierst du im Code-Modus. Skripte gibt es bewusst nicht.")
        }
    }

    private func pathField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        TextField(title, text: text, prompt: Text(prompt))
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(JSONPath.parse(text.wrappedValue) == nil ? .red : .primary)
    }

    private var aggregates: Binding<Bool> {
        Binding(get: { selection.arrayPath != nil }, set: { selection.arrayPath = $0 ? (selection.seriesPath ?? "") : nil })
    }

    private var hasSeries: Binding<Bool> {
        Binding(get: { selection.seriesPath != nil }, set: { selection.seriesPath = $0 ? (selection.arrayPath ?? "") : nil })
    }

    private func optional(_ key: WritableKeyPath<CustomWidgetDefinition.Selection, String?>) -> Binding<String> {
        Binding(get: { selection[keyPath: key] ?? "" }, set: { selection[keyPath: key] = $0 })
    }
}
