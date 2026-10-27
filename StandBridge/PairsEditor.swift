import SwiftUI

struct PairsEditor: View {
    let title: String
    let namePrompt: String
    @Binding var pairs: [CustomWidgetDefinition.Pair]

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach($pairs) { $pair in
                    HStack(spacing: 6) {
                        TextField("Name", text: $pair.name, prompt: Text(namePrompt))
                            .frame(maxWidth: 140)
                        TextField("Wert", text: $pair.value, prompt: Text("Wert"))
                        Button("Entfernen", systemImage: "minus.circle") { pairs.removeAll { $0.id == pair.id } }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                    .labelsHidden()
                    if CustomRequest.isSensitive(pair.name) {
                        Label("Sieht nach Zugangsdaten aus – die gehören unter „Authentifizierung“.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Button("Hinzufügen", systemImage: "plus") { pairs.append(.init(name: "", value: "")) }
                    .buttonStyle(.borderless)
            }
        }
    }
}
