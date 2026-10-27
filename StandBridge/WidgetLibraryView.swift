import AppKit
import SwiftUI

struct WidgetLibraryView: View {
    let store: CustomWidgetStore
    let onSaved: (CustomWidgetDefinition) -> Void
    let onDeleted: (UUID) -> Void
    @Binding var selection: UUID?

    @State private var importText: String?
    @State private var showsGallery = false
    @State private var exported: CustomWidgetDefinition?
    @State private var confirmsDelete: CustomWidgetDefinition?
    @State private var autoTests = UserDefaults.standard.bool(forKey: "libraryAutoTest")

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(width: 190)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Widget-Bibliothek")
        .sheet(isPresented: Binding(get: { importText != nil }, set: { if !$0 { importText = nil } })) {
            CustomImportSheet(text: importText ?? "") { definition, confirmed in
                var definition = definition
                if confirmed { definition.confirmedOrigin = definition.origin }
                store.save(definition)
                selection = definition.id
            }
        }
        .sheet(isPresented: $showsGallery) {
            CustomWidgetGallery(onPick: add, onPaste: { importText = NSPasteboard.general.string(forType: .string) ?? "" })
        }
        .sheet(item: $exported) { definition in
            CustomExportSheet(definition: definition)
        }
        .confirmationDialog("„\(confirmsDelete?.name ?? "")“ löschen?", isPresented: Binding(get: { confirmsDelete != nil }, set: { if !$0 { confirmsDelete = nil } }), titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                guard let definition = confirmsDelete else { return }
                store.delete(definition.id)
                onDeleted(definition.id)
                selection = store.definitions.first?.id
            }
        } message: {
            Text("Entfernt auch die Zugangsdaten im Schlüsselbund und das Widget von allen Seiten.")
        }
        .onAppear(perform: applyLaunchArguments)
    }

    private var list: some View {
        List(selection: $selection) {
            Section("Eigene Widgets") {
                ForEach(store.definitions) { definition in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(definition.name)
                            Text(subtitle(definition))
                                .font(.caption)
                                .foregroundStyle(definition.isConfirmed && store.hasSecret(definition) ? Color.secondary : Color.orange)
                        }
                    } icon: {
                        Image(systemName: definition.symbol)
                    }
                    .tag(definition.id)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 4) {
                Button("Widget anlegen", systemImage: "plus") { showsGallery = true }
                    .help("Widget aus einer Vorlage anlegen")
                Button("Einfügen", systemImage: "doc.on.clipboard") { importText = NSPasteboard.general.string(forType: .string) ?? "" }
                    .help("Widget-Konfiguration aus der Zwischenablage importieren")
                Spacer()
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .padding(10)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let definition = selection.flatMap(store.definition) {
            CustomWidgetEditor(
                saved: definition, store: store, autoTest: autoTests,
                onSaved: onSaved,
                onExport: export,
                onDelete: { confirmsDelete = definition }
            )
            .id(definition.id)
        } else {
            ContentUnavailableView {
                Label("Eigene Widgets", systemImage: "square.stack.3d.up")
            } description: {
                Text("Such dir eine Vorlage aus, trag deinen Zugang ein und wähl das Aussehen. Geteilte Konfigurationen fügst du mit „Einfügen“ ein.")
            } actions: {
                Button("Widget anlegen", systemImage: "plus") { showsGallery = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func subtitle(_ definition: CustomWidgetDefinition) -> String {
        if !definition.isConfirmed { return "Freigabe fehlt" }
        if !store.hasSecret(definition) { return "Zugangsdaten fehlen" }
        return store.displays[definition.id]?.error ?? definition.origin.flatMap { URL(string: $0)?.host() } ?? ""
    }

    private func add(_ definition: CustomWidgetDefinition) {
        store.save(definition)
        selection = definition.id
    }

    private func export(_ definition: CustomWidgetDefinition) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(CustomWidgetShare.export(definition), forType: .string)
        exported = definition
    }

    private func applyLaunchArguments() {
        let defaults = UserDefaults.standard
        if let template = defaults.string(forKey: "libraryTemplate").flatMap(CustomTemplate.named) {
            if let existing = store.definitions.first(where: { $0.name == template.definition.name }) {
                selection = existing.id
            } else {
                add(template.instantiate())
            }
        }
        if defaults.bool(forKey: "libraryGallery") { showsGallery = true }
        if defaults.bool(forKey: "libraryBlank") { add(CustomWidgetDefinition()) }
        if selection == nil { selection = store.definitions.first?.id }
        if defaults.bool(forKey: "libraryExport"), let definition = selection.flatMap(store.definition) {
            export(definition)
        }
        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        switch defaults.string(forKey: "libraryImport") {
        case "show": importText = clipboard
        case "accept":
            if let definition = try? CustomWidgetShare.decode(clipboard) {
                store.save(definition)
                selection = definition.id
            }
        default: break
        }
    }
}
