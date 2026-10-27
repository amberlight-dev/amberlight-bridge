import SwiftUI

struct CustomWidgetEditor: View {
    let saved: CustomWidgetDefinition
    let store: CustomWidgetStore
    let autoTest: Bool
    let onSaved: (CustomWidgetDefinition) -> Void
    let onExport: (CustomWidgetDefinition) -> Void
    let onDelete: () -> Void

    @State private var draft: CustomWidgetDefinition
    @State private var secret: CustomSecret
    @State private var savedSecret: CustomSecret
    @State private var response: CustomFetcher.Response?
    @State private var testError: String?
    @State private var testing = false
    @State private var mode: Mode
    @State private var connection = ConnectionStatus.idle
    @State private var history = LayoutHistory()
    @State private var code = ""
    @State private var codeError: String?

    enum Mode: String, CaseIterable, Identifiable {
        case simple = "Einfach", builder = "Gestalten", advanced = "Erweitert", code = "Code"

        var id: Self { self }
    }

    private static let intervals = [30, 60, 300, 900, 1800, 3600, 21_600, 86_400]

    init(saved: CustomWidgetDefinition, store: CustomWidgetStore, autoTest: Bool = false,
         onSaved: @escaping (CustomWidgetDefinition) -> Void, onExport: @escaping (CustomWidgetDefinition) -> Void, onDelete: @escaping () -> Void) {
        self.saved = saved
        self.store = store
        self.autoTest = autoTest
        self.onSaved = onSaved
        self.onExport = onExport
        self.onDelete = onDelete
        let stored = store.secret(for: saved) ?? CustomSecret()
        _mode = State(initialValue: saved.template != nil || saved.values != nil ? .simple : .advanced)
        _draft = State(initialValue: saved)
        _secret = State(initialValue: stored)
        _savedSecret = State(initialValue: stored)
    }

    var body: some View {
        Group {
            if mode == .builder {
                CustomLayoutBuilder(draft: $draft, json: previewJSON, history: store.history[draft.id] ?? [], undo: history)
            } else {
                workspace
            }
        }
        .navigationTitle(draft.name)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Ansicht", selection: modeBinding) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 330)
            }
            ToolbarItemGroup {
                Button("Löschen", systemImage: "trash", role: .destructive, action: onDelete)
                    .help("Widget aus der Bibliothek löschen")
                Button("Exportieren", systemImage: "square.and.arrow.up") { onExport(saved) }
                    .help("Konfiguration ohne Zugangsdaten in die Zwischenablage kopieren")
                Button("Sichern", systemImage: "checkmark", action: save)
                    .keyboardShortcut("s")
                    .disabled(!isDirty || validation != nil)
            }
        }
        .onChange(of: draft.origin) { _, origin in
            secret = origin == saved.origin ? savedSecret : CustomSecret()
            response = nil
            connection = .idle
        }
        .task {
            if let raw = UserDefaults.standard.string(forKey: "editorMode"), let initial = Mode(rawValue: raw) { mode = initial }
            if autoTest, draft.isConfirmed { await run() }
        }
    }

    private var workspace: some View {
        HStack(spacing: 0) {
            Group {
                switch mode {
                case .simple, .builder: simplePane
                case .advanced: form
                case .code: codeEditor
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity)
            Divider()
            CustomTestPanel(
                preview: preview, response: response, sample: sampleJSON, error: testError, testing: testing,
                canTest: draft.isConfirmed && validation == nil,
                selected: selectedPaths,
                onTest: test,
                onBind: bind,
                selection: $draft.selection
            )
            .frame(width: 360)
        }
    }

    private var simplePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: draft.symbol)
                        .font(.title2)
                        .frame(width: 28)
                    TextField("Name", text: $draft.name)
                        .textFieldStyle(.plain)
                        .font(.title.weight(.semibold))
                }
                CustomSetupCard(draft: $draft, secret: $secret, status: connection, onTest: test)
                CustomValuesCard(draft: $draft, texts: CustomLayout.scope(for: draft, json: previewJSON ?? [:], at: .now).text)
                CustomLayoutCard(draft: $draft, json: previewJSON, onCustomize: { mode = .builder })
            }
            .padding(20)
        }
    }

    private var modeBinding: Binding<Mode> {
        Binding(get: { mode }, set: { new in
            if new == .code { code = Self.json(of: draft); codeError = nil }
            mode = new
        })
    }

    private var sampleJSON: Any? {
        draft.template.flatMap(CustomTemplate.named)?.sampleJSON()
    }

    private var previewJSON: Any? { response?.json ?? sampleJSON }

    private func bind(_ path: String) {
        guard let json = previewJSON else { return }
        CustomBindings.add(path: path, json: json, to: &draft)
    }

    private var form: some View {
        Form {
            apiSection
            authSection
            endpointSection
            intervalSection
            CustomSelectionSection(selection: $draft.selection)
            CustomDisplaySection(display: $draft.display)
        }
        .formStyle(.grouped)
    }

    private var codeEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu("Layout-Vorlage", systemImage: "square.on.square.dashed") {
                    ForEach(CustomLayoutPresets.all) { preset in
                        Button(preset.title) { apply(preset) }
                    }
                    Divider()
                    Button("Layout entfernen") { apply(nil) }
                }
                .fixedSize()
                Spacer()
            }
            .padding([.horizontal, .top], 12)
            TextEditor(text: $code)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .onChange(of: code) { _, text in applyCode(text) }
            Group {
                if let codeError {
                    Label(codeError, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                } else {
                    Label("Gültig – Änderungen gelten sofort im Entwurf. Zugangsdaten stehen nie im JSON; ändert sich der Host, muss er neu freigegeben werden.", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .padding([.horizontal, .bottom], 12)
        }
    }

    private func apply(_ preset: CustomLayoutPresets.Preset?) {
        if let preset {
            preset.apply(to: &draft.display)
        } else {
            draft.display.layout = nil
            draft.display.compact = nil
            draft.display.wide = nil
        }
        code = Self.json(of: draft)
        codeError = nil
    }

    private func applyCode(_ text: String) {
        do {
            var decoded = try JSONDecoder().decode(CustomWidgetDefinition.self, from: Data(text.utf8))
            decoded.id = draft.id
            decoded.confirmedOrigin = decoded.origin == draft.origin ? draft.confirmedOrigin : nil
            codeError = nil
            if decoded != draft { draft = decoded }
        } catch {
            codeError = Self.describe(error)
        }
    }

    private static func json(of definition: CustomWidgetDefinition) -> String {
        var shared = definition
        shared.confirmedOrigin = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(shared)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let key, _): "Feld „\(key.stringValue)“ fehlt"
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context), DecodingError.dataCorrupted(let context):
            "Ungültig bei „\(context.codingPath.map(\.stringValue).joined(separator: "."))“: \(context.debugDescription)"
        default: "Kein gültiges JSON"
        }
    }

    private var apiSection: some View {
        Section {
            HStack(spacing: 10) {
                TextField("Name", text: $draft.name)
                TextField("Symbol", text: $draft.symbol, prompt: Text("SF Symbol"))
                    .frame(maxWidth: 160)
                Image(systemName: draft.symbol)
                    .frame(width: 22)
            }
            TextField("Basis-URL", text: baseURL, prompt: Text("https://api.example.com/v1"))
                .font(.system(.body, design: .monospaced))
            hostStatus
        } header: {
            Text("API")
        }
    }

    @ViewBuilder
    private var hostStatus: some View {
        if let validation {
            Label(validation, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        } else if let origin = draft.origin {
            LabeledContent("Kontaktiert", value: origin)
            if CustomRequest.usesPlainHTTP(draft.baseURL) {
                Label("Unverschlüsselt (http) – nur im lokalen Netz verwenden.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if !draft.isConfirmed {
                HStack {
                    Label("Host noch nicht freigegeben – die Bridge ruft ihn erst nach deiner Bestätigung ab.", systemImage: "hand.raised.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Freigeben") { draft.confirmedOrigin = draft.origin }
                }
            }
        }
    }

    private var authSection: some View {
        Section {
            Picker("Art", selection: $draft.auth.kind) {
                ForEach(CustomWidgetDefinition.AuthKind.allCases) { Text($0.title).tag($0) }
            }
            switch draft.auth.kind {
            case .none:
                EmptyView()
            case .bearer:
                SecureField("Token", text: $secret.value)
            case .headerKey:
                TextField("Header", text: $draft.auth.name, prompt: Text("X-API-Key"))
                SecureField("API-Key", text: $secret.value)
            case .queryKey:
                TextField("Query-Parameter", text: $draft.auth.name, prompt: Text("api_key"))
                SecureField("API-Key", text: $secret.value)
            case .basic:
                TextField("Benutzer", text: $secret.username)
                SecureField("Passwort", text: $secret.value)
            case .customHeader:
                TextField("Header", text: $draft.auth.name, prompt: Text("Authorization"))
                TextField("Präfix", text: $draft.auth.prefix, prompt: Text("Token token="))
                SecureField("Wert", text: $secret.value)
            }
            if draft.needsSecret {
                secretStatus
            }
        } header: {
            Text("Authentifizierung")
        } footer: {
            Text("Zugangsdaten liegen im macOS-Schlüsselbund, gebunden an dieses Widget und \(draft.origin ?? "den Host"). Sie gehen nur an diesen Host, nie ans iPhone und nie in einen Export.")
        }
    }

    @ViewBuilder
    private var secretStatus: some View {
        if draft.origin != saved.origin, !savedSecret.value.isEmpty {
            Label("Host geändert – die gespeicherten Zugangsdaten werden beim Sichern verworfen. Bitte neu eintragen.", systemImage: "key.slash")
                .foregroundStyle(.orange)
        } else if secret.value.isEmpty {
            Label("Zugangsdaten fehlen", systemImage: "key.slash")
                .foregroundStyle(.orange)
        } else {
            Label(secret == savedSecret ? "Im Schlüsselbund" : "Wird beim Sichern im Schlüsselbund abgelegt", systemImage: "key.fill")
                .foregroundStyle(.secondary)
        }
    }

    private var endpointSection: some View {
        Section {
            Picker("Methode", selection: $draft.endpoint.method) {
                ForEach(CustomWidgetDefinition.Method.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            TextField("Pfad", text: $draft.endpoint.path, prompt: Text("activities"))
                .font(.system(.body, design: .monospaced))
            PairsEditor(title: "Query", namePrompt: "from", pairs: $draft.endpoint.query)
            PairsEditor(title: "Header", namePrompt: "Accept-Language", pairs: $draft.endpoint.headers)
            if draft.endpoint.method == .post {
                TextEditor(text: $draft.endpoint.body)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 70)
                Text("Der Body wird mit exportiert – trag dort keine Zugangsdaten ein.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Endpunkt")
        } footer: {
            Text("Platzhalter in Pfad, Query und Body: {today}, {yesterday}, {weekStart}, {weekEnd}, {monthStart}, {monthEnd} (jeweils JJJJ-MM-TT). Leere Query-Werte werden weggelassen.")
        }
    }

    private var intervalSection: some View {
        Section("Abfrage-Intervall") {
            Picker("Alle", selection: $draft.interval) {
                ForEach(Self.intervals, id: \.self) { seconds in
                    Text(Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))).tag(seconds)
                }
                if !Self.intervals.contains(draft.interval) {
                    Text("\(draft.interval) s").tag(draft.interval)
                }
            }
        }
    }

    private var baseURL: Binding<String> {
        Binding(get: { draft.baseURL }, set: { url in
            draft.baseURL = url
            draft.confirmedOrigin = CustomRequest.origin(of: url)
        })
    }

    private var validation: String? {
        do {
            try CustomRequest.validate(draft)
            return nil
        } catch {
            return error.message
        }
    }

    private var isDirty: Bool { draft != saved || secret != savedSecret }

    private var selectedPaths: Set<String> {
        let selection = draft.selection
        func element(_ array: String?, _ field: String) -> String? {
            array.map { JSONPath.appending(.index(0), to: $0) + (field.isEmpty || field.hasPrefix("[") ? field : "." + field) }
        }
        let value = selection.arrayPath == nil ? selection.valuePath : element(selection.arrayPath, selection.valueField)
        return Set([value, element(selection.seriesPath, selection.labelField), element(selection.seriesPath, selection.seriesField)].compactMap(\.self))
    }

    private var preview: CustomWidgetDisplay? {
        guard let json = previewJSON else { return store.displays[draft.id] }
        return CustomEvaluator.display(for: draft, json: json, history: store.history[draft.id] ?? [])
    }

    private func test() {
        Task { await run() }
    }

    private func run() async {
        testing = true
        connection = .testing
        defer { testing = false }
        switch await store.test(draft, typed: secret) {
        case .success(let result):
            response = result
            testError = nil
            connection = .connected(bytes: result.data.count)
        case .failure(let error):
            response = nil
            testError = error.message
            connection = .failed(error.message)
        }
    }

    private func save() {
        store.save(draft)
        store.setSecret(draft.needsSecret ? secret : nil, for: draft)
        savedSecret = draft.needsSecret ? secret : CustomSecret()
        onSaved(draft)
        Task { await store.refresh(draft.id) }
    }
}
