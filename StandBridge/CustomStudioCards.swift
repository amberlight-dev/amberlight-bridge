import SwiftUI

struct StudioCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12, style: .continuous))
    }
}

enum ConnectionStatus: Equatable {
    case idle, testing, connected(bytes: Int), failed(String)
}

struct CustomSetupCard: View {
    @Binding var draft: CustomWidgetDefinition
    @Binding var secret: CustomSecret
    let status: ConnectionStatus
    let onTest: () -> Void

    private var template: CustomTemplate? { draft.template.flatMap(CustomTemplate.named) }

    var body: some View {
        StudioCard(title: "Verbinden", subtitle: subtitle) {
            if let template, !template.inputs.isEmpty {
                ForEach(Array(template.inputs.enumerated()), id: \.offset) { _, input in
                    field(for: input)
                }
            } else {
                genericFields
            }
            HStack(spacing: 12) {
                Button(action: onTest) {
                    Label(status == .idle ? "Verbinden & testen" : "Erneut testen", systemImage: "bolt.horizontal.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("r")
                .disabled(!canTest || status == .testing)
                statusLabel
            }
            if let hint = blockingHint {
                Label(hint, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        draft.needsSecret ? "Nur das Nötigste – Zugangsdaten bleiben im Schlüsselbund dieses Macs." : "Dieses Widget braucht kein Konto."
    }

    private var canTest: Bool { blockingHint == nil }

    private var blockingHint: String? {
        if let error = validationError { return error }
        if draft.needsSecret, secret.value.isEmpty { return "Trag oben den Zugang ein, dann kannst du testen." }
        return nil
    }

    private var validationError: String? {
        do {
            try CustomRequest.validate(draft)
            return draft.origin == nil ? "Basis-URL fehlt" : nil
        } catch {
            return error.message
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .idle: EmptyView()
        case .testing: ProgressView().controlSize(.small)
        case .connected(let bytes):
            Label("Verbunden · \(bytes.formatted(.byteCount(style: .file)))", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var genericFields: some View {
        labeled("Basis-URL") {
            TextField("Basis-URL", text: baseURL, prompt: Text("https://api.example.com/v1"))
                .font(.system(.body, design: .monospaced))
        }
        if draft.needsSecret {
            labeled("Zugang (Token bzw. Key)") { SecureField("Zugang", text: $secret.value) }
        }
    }

    @ViewBuilder
    private func field(for input: CustomTemplate.Input) -> some View {
        switch input {
        case .subdomain(let label, let pattern, let prompt):
            labeled(label) { TextField(label, text: subdomain(pattern), prompt: Text(prompt)) }
        case .secret(let label, let prompt):
            labeled(label) { SecureField(label, text: $secret.value, prompt: Text(prompt)) }
        case .query(let name, let label, let prompt):
            labeled(label) { TextField(label, text: query(name), prompt: Text(prompt)) }
        }
    }

    private func labeled(_ label: String, @ViewBuilder _ field: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.callout.weight(.medium)).foregroundStyle(.secondary)
            field().labelsHidden()
        }
    }

    private var baseURL: Binding<String> {
        Binding(get: { draft.baseURL }, set: { url in
            draft.baseURL = url
            draft.confirmedOrigin = CustomRequest.origin(of: url)
        })
    }

    private func subdomain(_ pattern: String) -> Binding<String> {
        let parts = pattern.components(separatedBy: "{}")
        let prefix = parts.first ?? ""
        let suffix = parts.last ?? ""
        return Binding(
            get: {
                guard draft.baseURL.hasPrefix(prefix), draft.baseURL.hasSuffix(suffix) else { return "" }
                let middle = String(draft.baseURL.dropFirst(prefix.count).dropLast(suffix.count))
                return middle.caseInsensitiveCompare(CustomTemplate.mocoPlaceholder) == .orderedSame ? "" : middle
            },
            set: { value in
                let cleaned = value.trimmingCharacters(in: .whitespaces)
                baseURL.wrappedValue = prefix + (cleaned.isEmpty ? CustomTemplate.mocoPlaceholder : cleaned) + suffix
            }
        )
    }

    private func query(_ name: String) -> Binding<String> {
        Binding(
            get: { draft.endpoint.query.first { $0.name == name }?.value ?? "" },
            set: { value in
                if let index = draft.endpoint.query.firstIndex(where: { $0.name == name }) {
                    draft.endpoint.query[index].value = value
                } else {
                    draft.endpoint.query.append(.init(name: name, value: value))
                }
            }
        )
    }
}

struct CustomValuesCard: View {
    @Binding var draft: CustomWidgetDefinition
    let texts: [String: String]

    var body: some View {
        StudioCard(title: "Daten", subtitle: "Klick rechts in der Antwort auf ＋ – das Feld erscheint sofort im Widget.") {
            if (draft.values ?? []).isEmpty {
                Text("Noch kein eigenes Feld. Der Hauptwert kommt aus dem Abschnitt „Erweitert“.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(draft.values ?? []) { value in
                row(value)
            }
        }
    }

    private func row(_ value: CustomWidgetDefinition.NamedValue) -> some View {
        HStack(spacing: 8) {
            Text("{\(value.name)}")
                .font(.system(.body, design: .monospaced))
                .frame(width: 130, alignment: .leading)
                .lineLimit(1)
            Text(texts[value.name] ?? "–")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Spacer()
            if value.selection.arrayPath != nil {
                Picker("Berechnung", selection: aggregation(value.id)) {
                    ForEach(CustomWidgetDefinition.Aggregation.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            Button("Entfernen", systemImage: "trash") { draft.values?.removeAll { $0.id == value.id } }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
    }

    private func aggregation(_ id: UUID) -> Binding<CustomWidgetDefinition.Aggregation> {
        Binding(
            get: { draft.values?.first { $0.id == id }?.selection.aggregation ?? .sum },
            set: { new in
                guard let index = draft.values?.firstIndex(where: { $0.id == id }) else { return }
                draft.values?[index].selection.aggregation = new
            }
        )
    }
}

struct CustomLayoutCard: View {
    @Binding var draft: CustomWidgetDefinition
    let json: Any?

    let onCustomize: () -> Void

    private struct Option: Identifiable {
        let id: String
        let title: String
        let preset: CustomLayoutPresets.Preset?
    }

    private var options: [Option] {
        let names = Set((draft.values ?? []).map(\.name))
        let presets = CustomLayoutPresets.all.filter { Set($0.requires).isSubset(of: names) }
        return [Option(id: "standard", title: "Standard", preset: nil)] + presets.map { Option(id: $0.id, title: $0.title, preset: $0) }
    }

    var body: some View {
        StudioCard(title: "Aussehen", subtitle: "Die Vorschauen zeigen deine Daten.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12, alignment: .top)], alignment: .leading, spacing: 14) {
                ForEach(options) { option in
                    Button { apply(option) } label: { card(option) }
                        .buttonStyle(.plain)
                }
            }
            Button("Im Baukasten anordnen", systemImage: "square.grid.3x3.middle.filled", action: onCustomize)
                .buttonStyle(.borderedProminent)
            HStack(spacing: 12) {
                TextField("Beschriftung", text: $draft.display.caption, prompt: Text("wie der Name"))
                Picker("Zahlen", selection: $draft.display.format) {
                    ForEach(CustomWidgetDefinition.NumberFormat.allCases) { Text($0.title).tag($0) }
                }
                .fixedSize()
            }
        }
    }

    private func apply(_ option: Option) {
        if let preset = option.preset {
            preset.apply(to: &draft.display)
        } else {
            draft.display.layout = nil
            draft.display.compact = nil
            draft.display.wide = nil
        }
    }

    private func isSelected(_ option: Option) -> Bool {
        option.preset?.isApplied(in: draft.display) ?? (draft.display.layout == nil)
    }

    private func card(_ option: Option) -> some View {
        let selected = isSelected(option)
        return VStack(spacing: 6) {
            CustomTile(display: display(for: option), span: GridSpan(w: 2, h: 2), notice: json == nil ? "Erst verbinden" : "Keine Daten")
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2.5)
                }
            Text(option.title)
                .font(.caption.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 114)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func display(for option: Option) -> CustomWidgetDisplay? {
        guard let json else { return nil }
        var candidate = draft
        if let preset = option.preset {
            preset.apply(to: &candidate.display)
        } else {
            candidate.display.layout = nil
        }
        return CustomEvaluator.display(for: candidate, json: json)
    }
}
