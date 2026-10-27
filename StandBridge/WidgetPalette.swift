import SwiftUI

struct WidgetPalette: View {
    let custom: [CustomWidgetDefinition]
    let onAdd: (StandWidget, GridSpan?, WidgetSettings?) -> Void

    var body: some View {
        List {
            ForEach(StandWidget.offered(orbitConfigured: Accounts.orbit != nil)) { widget in
                Button { onAdd(widget, nil, nil) } label: { row(widget.symbol, widget.title, widget.blurb, widget.defaultSpan) }
                    .buttonStyle(.plain)
                    .help("\(widget.title) hinzufügen")
                    .accessibilityLabel("\(widget.title) hinzufügen")
                    .accessibilityHint(widget.blurb)
            }
            Section("Eigene Widgets") {
                ForEach(custom) { definition in
                    Button { onAdd(.custom, definition.display.style.preferredSpan, settings(for: definition)) } label: {
                        row(definition.symbol, definition.name, definition.display.style.title, definition.display.style.preferredSpan)
                    }
                    .buttonStyle(.plain)
                    .help("\(definition.name) hinzufügen")
                }
                if custom.isEmpty {
                    Text("Eigene Widgets legst du in der Widget-Bibliothek an.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Widget hinzufügen")
                    .font(.headline)
                Text("Klicken setzt es auf den ersten freien Platz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top], 16)
        }
    }

    private func settings(for definition: CustomWidgetDefinition) -> WidgetSettings {
        var settings = WidgetSettings()
        settings.customID = definition.id
        settings.customName = definition.name
        return settings
    }

    private func row(_ symbol: String, _ title: String, _ blurb: String, _ span: GridSpan) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(.quaternary, in: .rect(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                WidgetSpanPreview(span: span, cell: 6, gap: 2)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
    }
}
