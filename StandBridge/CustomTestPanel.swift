import SwiftUI

struct CustomTestPanel: View {
    let preview: CustomWidgetDisplay?
    let response: CustomFetcher.Response?
    let sample: Any?
    let error: String?
    let testing: Bool
    let canTest: Bool
    let selected: Set<String>
    let onTest: () -> Void
    let onBind: (String) -> Void
    @Binding var selection: CustomWidgetDefinition.Selection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Live-Vorschau")
                .font(.headline)
            CustomPreview(display: preview)
            Divider()
            HStack {
                Text("Antwort")
                    .font(.headline)
                Spacer()
                if testing { ProgressView().controlSize(.small) }
                Button("Testen", systemImage: "play.fill", action: onTest)
                    .disabled(!canTest || testing)
                    .keyboardShortcut("r")
            }
            status
            if let json = response?.json ?? sample {
                JSONTreeView(
                    nodes: JSONNode.tree(json),
                    selected: selected,
                    onValue: { path in
                        selection.valuePath = path
                        selection.arrayPath = nil
                    },
                    onArray: { path in
                        selection.arrayPath = path
                        selection.seriesPath = path
                        if selection.valueField.isEmpty { selection.aggregation = .count }
                    },
                    onField: apply,
                    onBind: onBind
                )
            } else {
                ContentUnavailableView("Noch keine Antwort", systemImage: "network", description: Text("„Testen“ schickt eine echte Anfrage und zeigt die Antwort hier als Baum."))
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var status: some View {
        if let error {
            Label(error, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        } else if let response {
            Label("\(response.data.count.formatted(.byteCount(style: .file))) · Klick wählt den Wert", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if !canTest {
            Label("Erst eine gültige Basis-URL eintragen und den Host freigeben.", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func apply(_ path: String, role: CustomFieldRole) {
        guard let split = JSONPath.elementSplit(path) else { return }
        switch role {
        case .aggregated:
            selection.arrayPath = split.array
            selection.valueField = split.field
            if selection.aggregation == .count { selection.aggregation = .sum }
        case .label:
            selection.seriesPath = split.array
            selection.labelField = split.field
        case .series:
            selection.seriesPath = split.array
            selection.seriesField = split.field
        }
    }
}
