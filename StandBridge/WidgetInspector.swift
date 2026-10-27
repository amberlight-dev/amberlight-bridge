import SwiftUI

struct WidgetInspector: View {
    let item: PlacedWidget
    let sizes: [GridSpan]
    let shortcutCount: Int
    let onSettings: (WidgetSettings) -> Void
    let onResize: (GridSpan) -> Void
    let onDuplicate: () -> Void
    let onRemove: () -> Void
    let onConfigureShortcuts: () -> Void
    let onOpenLibrary: (UUID) -> Void
    let onClose: () -> Void

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.widget.symbol)
                        .font(.title2)
                        .frame(width: 40, height: 40)
                        .background(.quaternary, in: .rect(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.headline)
                        Text(item.widget.blurb)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Größe") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(sizes, id: \.self) { span in
                        sizeChip(span)
                    }
                }
                .padding(.vertical, 2)
            }

            WidgetSettingsForm(widget: item.widget, settings: Binding(
                get: { item.settings ?? WidgetSettings() },
                set: { onSettings($0) }
            ))

            if item.widget == .shortcuts {
                Section("Schnellstart") {
                    LabeledContent("Einträge", value: "\(shortcutCount)")
                    Button("Shortcuts einstellen …", systemImage: "slider.horizontal.3", action: onConfigureShortcuts)
                }
            }

            if item.widget == .custom, let id = item.settings?.customID {
                Section("Eigenes Widget") {
                    Text("API, Wert und Darstellung richtest du in der Widget-Bibliothek ein.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("In der Widget-Bibliothek öffnen", systemImage: "square.stack.3d.up") { onOpenLibrary(id) }
                }
            } else if !item.widget.hasOwnSettings {
                Section {
                    Text("Für dieses Widget gibt es keine eigenen Einstellungen. Es passt sich seiner Größe an.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Duplizieren", systemImage: "plus.square.on.square", action: onDuplicate)
                Button("Entfernen", systemImage: "trash", role: .destructive, action: onRemove)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem {
                Button("Auswahl aufheben", systemImage: "xmark.circle", action: onClose)
                    .help("Zurück zu „Widget hinzufügen“")
            }
        }
    }

    private func sizeChip(_ span: GridSpan) -> some View {
        let isCurrent = span == item.frame.span
        return Button { onResize(span) } label: {
            Text("\(span.w)×\(span.h)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: 26)
                .foregroundStyle(isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Größe \(span.w) mal \(span.h)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
