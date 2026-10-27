import SwiftUI

struct CustomWidgetGallery: View {
    let onPick: (CustomWidgetDefinition) -> Void
    let onPaste: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 18, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Neues Widget").font(.title2.weight(.semibold))
                    Text("Such dir ein Vorbild aus – du trägst danach nur noch deinen Zugang ein.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.title).font(.headline)
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                ForEach(group.templates) { template in
                                    Button { pick(template.instantiate()) } label: { card(template) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    HStack(spacing: 12) {
                        Button("Leeres Widget", systemImage: "square.dashed") { pick(CustomWidgetDefinition()) }
                        Button("Aus Zwischenablage", systemImage: "doc.on.clipboard") {
                            dismiss()
                            onPaste()
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 720, height: 600)
    }

    private var groups: [(title: String, templates: [CustomTemplate])] {
        Dictionary(grouping: CustomTemplate.all, by: \.group)
            .map { (title: $0.key, templates: $0.value) }
            .sorted { $0.title > $1.title }
    }

    private func pick(_ definition: CustomWidgetDefinition) {
        dismiss()
        onPick(definition)
    }

    private func card(_ template: CustomTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CustomTile(display: display(template), span: template.definition.display.style.preferredSpan.atLeastSquare)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.title).font(.body.weight(.semibold))
                Text(template.blurb)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if template.needsAccount {
                    Label("Braucht ein Konto", systemImage: "key.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    private func display(_ template: CustomTemplate) -> CustomWidgetDisplay? {
        guard let json = template.sampleJSON() else { return nil }
        let history = (0..<12).map { index in
            CustomWidgetDisplay.Sample(at: .now.addingTimeInterval(Double(index - 12) * 900), value: 17.4 + sin(Double(index) / 2) * 1.2)
        }
        return CustomEvaluator.display(for: template.definition, json: json, history: template.definition.display.style == .line ? history : [])
    }
}

private extension GridSpan {
    var atLeastSquare: GridSpan { GridSpan(w: 2, h: max(h, 2)) }
}
