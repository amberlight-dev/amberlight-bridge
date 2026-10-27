import SwiftUI

struct CustomExportSheet: View {
    let definition: CustomWidgetDefinition

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("„\(definition.name)“ liegt in der Zwischenablage", systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
            Text("Einfügen in eine andere Amberlight Bridge unter Widget-Bibliothek → Einfügen. Zugangsdaten sind nicht enthalten, die trägt jeder selbst ein.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(CustomWidgetShare.export(definition))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(6)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: .rect(cornerRadius: 8))
            HStack {
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
