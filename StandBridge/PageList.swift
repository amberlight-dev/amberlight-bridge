import SwiftUI

enum BridgeSidebarItem: Hashable {
    case page(StandPage.ID)
    case devices
    case replies
    case diagnostics
    case accounts
    case library
    case preferences
}

struct BridgeSidebar: View {
    let store: LayoutStore
    @Binding var selection: BridgeSidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Anordnung") {
                if store.revision == 0 {
                    Label("Wartet auf das iPhone", systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
                ForEach(store.pages) { page in
                    Label(page.name, systemImage: page.symbol)
                        .tag(BridgeSidebarItem.page(page.id))
                        .contextMenu {
                            Button("Seite löschen", systemImage: "trash", role: .destructive) { delete(page.id) }
                                .disabled(store.pages.count < 2)
                        }
                }
                .onMove { from, to in store.update { $0.move(fromOffsets: from, toOffset: to) } }
            }
            Section("Amberlight") {
                Label("Einstellungen", systemImage: "slider.horizontal.3").tag(BridgeSidebarItem.preferences)
                Label("Widget-Bibliothek", systemImage: "square.stack.3d.up").tag(BridgeSidebarItem.library)
            }
            Section("Bridge") {
                Label("Geräte", systemImage: "iphone.gen3").tag(BridgeSidebarItem.devices)
                Label("Antworten", systemImage: "text.bubble").tag(BridgeSidebarItem.replies)
                Label("Diagnose", systemImage: "stethoscope").tag(BridgeSidebarItem.diagnostics)
                Label("Konten", systemImage: "person.badge.key").tag(BridgeSidebarItem.accounts)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 4) {
                Menu {
                    Button("Leere Seite", systemImage: "square.dashed") { add(StandPage(name: String(localized: "Neue Seite"), items: [], icon: StandPage.newPageIcon)) }
                    Divider()
                    Button("Schreibtisch", systemImage: "desktopcomputer") { add(.desk()) }
                    Button("Nachttisch", systemImage: "moon.zzz") { add(.nightstand()) }
                    Button("Plattenspieler", systemImage: "opticaldisc") { add(.turntable()) }
                } label: {
                    Image(systemName: "plus")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Seite hinzufügen")
                Button("Seite löschen", systemImage: "minus") { selectedPage.map(delete) }
                    .labelStyle(.iconOnly)
                    .help("Ausgewählte Seite löschen")
                    .disabled(selectedPage == nil || store.pages.count < 2)
                Spacer()
            }
            .buttonStyle(.borderless)
            .disabled(store.revision == 0)
            .padding(10)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 230)
    }

    private var selectedPage: StandPage.ID? {
        guard case .page(let id) = selection else { return nil }
        return id
    }

    private func add(_ page: StandPage) {
        store.update { $0.append(page) }
        selection = .page(page.id)
    }

    private func delete(_ id: StandPage.ID) {
        guard store.pages.count > 1 else { return }
        store.update { $0.removeAll { $0.id == id } }
    }
}
