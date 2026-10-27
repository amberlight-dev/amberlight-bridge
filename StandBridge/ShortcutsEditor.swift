import AppKit
import SwiftUI

struct ShortcutsEditor: View {
    let store: LayoutStore

    @Environment(\.dismiss) private var dismiss
    @State private var apps: [InstalledApp] = []
    @State private var search = ""
    @State private var link = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                current
                    .frame(width: 340)
                Divider()
                additions
            }
            Divider()
            HStack {
                Text("Erscheint im Open-Window-Widget auf dem iPhone, in dieser Reihenfolge.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 760, height: 560)
        .task { apps = MacLauncher.apps().compactMap(InstalledApp.init) }
    }

    private var current: some View {
        List {
            Section("Schnellstart") {
                if store.shortcuts.isEmpty {
                    Text("Noch nichts hinzugefügt.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.shortcuts) { shortcut in
                    HStack(spacing: 10) {
                        Self.icon(for: shortcut)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(shortcut.title)
                            Text(Self.detail(of: shortcut))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button("Entfernen", systemImage: "minus.circle.fill") { remove(shortcut) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                    }
                }
                .onMove { from, to in store.updateShortcuts { $0.move(fromOffsets: from, toOffset: to) } }
            }
        }
    }

    private var additions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hinzufügen")
                .font(.headline)
            HStack {
                TextField("Link, z. B. github.com", text: $link)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addLink)
                Button("Link", systemImage: "link", action: addLink)
                    .disabled(Self.shortcut(forLink: link) == nil)
            }
            Button("Ordner wählen …", systemImage: "folder.badge.plus", action: chooseFolders)
            TextField("Apps durchsuchen", text: $search)
                .textFieldStyle(.roundedBorder)
            List(filteredApps) { app in
                HStack(spacing: 10) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 22, height: 22)
                    Text(app.name)
                    Spacer()
                    if store.shortcuts.contains(where: { $0.id == app.shortcut.id }) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("\(app.name) hinzufügen", systemImage: "plus.circle.fill") { add(app.shortcut) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                }
            }
            .listStyle(.bordered)
        }
        .padding(16)
    }

    private var filteredApps: [InstalledApp] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? apps : apps.filter { $0.name.localizedStandardContains(query) }
    }

    private func add(_ shortcut: StandShortcut) {
        store.updateShortcuts { shortcuts in
            if !shortcuts.contains(where: { $0.id == shortcut.id }) { shortcuts.append(shortcut) }
        }
    }

    private func remove(_ shortcut: StandShortcut) {
        store.updateShortcuts { $0.removeAll { $0 == shortcut } }
    }

    private func addLink() {
        guard let shortcut = Self.shortcut(forLink: link) else { return }
        add(shortcut)
        link = ""
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Hinzufügen"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            add(StandShortcut(kind: .url, value: url.absoluteString, title: FileManager.default.displayName(atPath: url.path)))
        }
    }

    static func shortcut(forLink text: String) -> StandShortcut? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard !trimmed.isEmpty, let url = URL(string: value), MacLauncher.openableURL(value) != nil,
              url.host() != nil || url.scheme != "https" else { return nil }
        return StandShortcut(kind: .url, value: value, title: url.host() ?? value)
    }

    private static func detail(of shortcut: StandShortcut) -> String {
        guard let url = URL(string: shortcut.value), url.isFileURL else { return shortcut.value }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }

    private static func icon(for shortcut: StandShortcut) -> Image {
        if shortcut.kind == .app, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: shortcut.value) {
            return Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        }
        if shortcut.kind == .url, let url = URL(string: shortcut.value), url.isFileURL {
            return Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        }
        return Image(systemName: shortcut.symbol)
    }
}

private struct InstalledApp: Identifiable {
    let name: String
    let bundleId: String

    init?(_ json: JSON) {
        guard let name = json["name"] as? String, let bundleId = json["bundleId"] as? String else { return nil }
        self.name = name
        self.bundleId = bundleId
    }

    var id: String { bundleId }
    var shortcut: StandShortcut { StandShortcut(kind: .app, value: bundleId, title: name) }

    var icon: NSImage {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId).map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage()
    }
}
