import Sparkle
import SwiftUI

struct BridgeWindow: View {
    static let id = "main"

    @Bindable var model: BridgeModel
    let updater: SPUUpdater
    @State private var selectedItem: PlacedWidget.ID?
    @State private var notice: String?
    @State private var editsShortcuts = false

    private var store: LayoutStore { model.layout }

    var body: some View {
        NavigationSplitView {
            BridgeSidebar(store: store, selection: $model.sidebar)
        } detail: {
            detail
        }
        .frame(minWidth: 980, minHeight: 620)
        .tint(StandAccent.bridgeTint)
        .overlay(alignment: .bottom) { noticeBanner }
        .sheet(isPresented: $editsShortcuts) { ShortcutsEditor(store: store) }
        .task(id: notice) {
            guard notice != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.smooth) { notice = nil }
        }
        .onAppear {
            keepSelection()
            editsShortcuts = UserDefaults.standard.bool(forKey: "editShortcuts")
            inspectFromLaunchArgument()
            WindowSnapshot.writeIfRequested()
        }
        .onChange(of: model.sidebar) { selectedItem = nil }
        .onChange(of: store.revision) { keepSelection() }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.sidebar {
        case .page(let id):
            if let page = store.pages.first(where: { $0.id == id }) {
                PageEditor(
                    page: page,
                    selectedItem: $selectedItem,
                    shortcutCount: store.shortcuts.count,
                    edges: store.edges,
                    onEdges: { store.updateEdges($0) },
                    onChange: replace,
                    customWidgets: model.customWidgets.definitions,
                    onAddWidget: { add($0, span: $1, settings: $2, onto: page) },
                    onDuplicate: { duplicate($0, onto: page) },
                    onConfigureShortcuts: { editsShortcuts = true },
                    onOpenLibrary: { id in
                        model.librarySelection = id
                        model.sidebar = .library
                    }
                )
                .id(page.id)
            } else {
                ContentUnavailableView("Seite nicht mehr da", systemImage: "rectangle.on.rectangle.slash")
            }
        case .devices:
            DevicesView(model: model)
        case .replies:
            RepliesView(model: model)
        case .diagnostics:
            DiagnosticsView(model: model, updater: updater)
        case .accounts:
            AccountsView()
        case .library:
            WidgetLibraryView(
                store: model.customWidgets,
                onSaved: renamePlaced,
                onDeleted: removePlaced,
                selection: $model.librarySelection
            )
        case .preferences:
            PreferencesView(store: store) { model.sidebar = .devices }
        case nil:
            ContentUnavailableView(
                "Warte auf das iPhone",
                systemImage: "iphone.gen3.radiowaves.left.and.right",
                description: Text("Sobald sich die Amberlight-App verbindet, übernimmt die Bridge ihre Seiten. Unter „Geräte“ koppelst du ein iPhone.")
            )
        }
    }

    @ViewBuilder
    private var noticeBanner: some View {
        if let notice {
            Label(notice, systemImage: "rectangle.badge.plus")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: .capsule)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func replace(_ changed: StandPage) {
        store.update { pages in
            guard let index = pages.firstIndex(where: { $0.id == changed.id }) else { return }
            pages[index] = changed
        }
    }

    private func add(_ widget: StandWidget, span: GridSpan?, settings: WidgetSettings?, onto page: StandPage) {
        var landed = page.id
        withAnimation(.smooth) {
            store.update { landed = $0.add(widget, onto: page.id, preferring: span, settings: settings) }
        }
        guard landed != page.id else { return }
        model.sidebar = .page(landed)
        withAnimation(.smooth) { notice = String(localized: "Auf „\(page.name)“ war kein Platz – \(settings?.customName ?? widget.title) liegt jetzt auf einer neuen Seite.") }
    }

    private func renamePlaced(_ definition: CustomWidgetDefinition) {
        store.update { pages in
            for page in pages.indices {
                for item in pages[page].items.indices where pages[page].items[item].settings?.customID == definition.id {
                    pages[page].items[item].settings?.customName = definition.name
                }
            }
        }
    }

    private func removePlaced(_ id: UUID) {
        store.update { pages in
            for page in pages.indices {
                pages[page].items.removeAll { $0.settings?.customID == id }
            }
        }
    }

    private func duplicate(_ item: PlacedWidget, onto page: StandPage) {
        var landed = page.id
        withAnimation(.smooth) {
            store.update { landed = $0.duplicate(item, onto: page.id) }
        }
        guard landed != page.id else {
            selectedItem = store.pages.first { $0.id == page.id }?.items.last?.id
            return
        }
        model.sidebar = .page(landed)
        withAnimation(.smooth) { notice = String(localized: "Auf „\(page.name)“ war kein Platz – die Kopie liegt jetzt auf einer neuen Seite.") }
    }

    private func inspectFromLaunchArgument() {
        guard let raw = UserDefaults.standard.string(forKey: "inspect"), let widget = StandWidget(rawValue: raw),
              let page = store.pages.first(where: { $0.items.contains { $0.widget == widget } }) else { return }
        model.sidebar = .page(page.id)
        Task { selectedItem = page.items.first { $0.widget == widget }?.id }
    }

    private func keepSelection() {
        switch model.sidebar {
        case .page(let id) where store.pages.contains(where: { $0.id == id }): return
        case .devices, .replies, .diagnostics, .accounts, .library, .preferences: return
        default: model.sidebar = store.pages.first.map { .page($0.id) }
        }
    }
}
