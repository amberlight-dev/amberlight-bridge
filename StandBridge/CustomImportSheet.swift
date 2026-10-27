import SwiftUI

struct CustomImportSheet: View {
    let text: String
    let onImport: (CustomWidgetDefinition, Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    private var result: Result<CustomWidgetDefinition, CustomWidgetShare.ImportError> {
        Result { () throws(CustomWidgetShare.ImportError) in try CustomWidgetShare.decode(text) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Widget importieren")
                .font(.title2.weight(.semibold))
            switch result {
            case .success(let definition):
                summary(definition)
            case .failure(let error):
                Label(error.message, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                buttons(nil)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func summary(_ definition: CustomWidgetDefinition) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(definition.name, systemImage: definition.symbol)
                .font(.headline)
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Kontaktiert", value: definition.origin ?? "–")
                    LabeledContent("Anfrage", value: "\(definition.endpoint.method.rawValue) \(definition.endpoint.path.isEmpty ? "/" : definition.endpoint.path)")
                    LabeledContent("Intervall", value: Duration.seconds(definition.clampedInterval).formatted(.units(width: .abbreviated)))
                    LabeledContent("Darstellung", value: definition.display.style.title)
                    LabeledContent("Zugangsdaten", value: definition.needsSecret ? "\(definition.auth.kind.title) – fehlen, trägst du danach ein" : "keine")
                }
                .padding(4)
            }
            if CustomRequest.usesPlainHTTP(definition.baseURL) {
                Label("Unverschlüsselte Verbindung (http) ins lokale Netz.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Text("Die Konfiguration enthält keine Zugangsdaten und führt keinen Code aus. Die Bridge fragt \(definition.origin ?? "den Host") erst ab, wenn du ihn freigibst.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            buttons(definition)
        }
    }

    private func buttons(_ definition: CustomWidgetDefinition?) -> some View {
        HStack {
            Spacer()
            Button("Abbrechen", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            if let definition {
                Button("Nur importieren") {
                    onImport(definition, false)
                    dismiss()
                }
                Button("Importieren und freigeben") {
                    onImport(definition, true)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
