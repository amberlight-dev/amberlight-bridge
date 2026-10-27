import SwiftUI

struct PageEditor: View {
    let page: StandPage
    @Binding var selectedItem: PlacedWidget.ID?
    let shortcutCount: Int
    let edges: EdgeConfig
    let onEdges: (EdgeConfig) -> Void
    let onChange: (StandPage) -> Void
    let customWidgets: [CustomWidgetDefinition]
    let onAddWidget: (StandWidget, GridSpan?, WidgetSettings?) -> Void
    let onDuplicate: (PlacedWidget) -> Void
    let onConfigureShortcuts: () -> Void
    let onOpenLibrary: (UUID) -> Void

    @State private var name = ""
    @State private var showsInspector = true
    @State private var editsEdges = UserDefaults.standard.bool(forKey: "editEdges")
    @FocusState private var editsName: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if editsEdges {
                EdgeEditor(page: page, edges: edges, onChange: onEdges)
            } else {
                PageCanvas(
                    page: page,
                    selectedItem: selectedItem,
                    onSelect: { id in withAnimation(.smooth(duration: 0.2)) { selectedItem = id } },
                    onMove: { id, frame in edit { $0.move(id, to: frame) } },
                    onResize: { id, span in edit { $0.resize(id, to: span) } },
                    onRemove: remove
                )
                Text("Klicken wählt ein Widget und zeigt rechts seine Einstellungen. Ziehen verschiebt, der Griff unten rechts ändert die Größe.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .inspector(isPresented: $showsInspector) {
            inspector
                .inspectorColumnWidth(min: 260, ideal: 290, max: 360)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Bearbeiten", selection: $editsEdges) {
                    Label("Widgets", systemImage: "square.grid.2x2").tag(false)
                    Label("Rand", systemImage: "rectangle.dashed").tag(true)
                }
                .pickerStyle(.segmented)
                .labelStyle(.titleAndIcon)
                .help("Zwischen Widgets und Rand-Plätzen wechseln")
            }
            ToolbarItem {
                Button("Inspector", systemImage: "sidebar.right") { showsInspector.toggle() }
                    .help(showsInspector ? "Inspector ausblenden" : "Inspector einblenden")
            }
        }
        .navigationTitle(page.name)
        .onAppear { name = page.name }
        .onChange(of: page.name) { _, new in if !editsName { name = new } }
        .onChange(of: editsName) { _, editing in if !editing { commitName() } }
        .onChange(of: page.items.map(\.id)) { _, ids in
            if let selectedItem, !ids.contains(selectedItem) { self.selectedItem = nil }
        }
        .onExitCommand { selectedItem = nil }
        .onDeleteCommand { selectedItem.map(remove) }
    }

    @ViewBuilder
    private var inspector: some View {
        if let item = page.items.first(where: { $0.id == selectedItem }) {
            WidgetInspector(
                item: item,
                sizes: page.sizeOptions(for: item),
                shortcutCount: shortcutCount,
                onSettings: { settings in edit { page in update(item.id, in: &page) { $0.settings = settings } } },
                onResize: { span in edit { $0.resize(item.id, to: span) } },
                onDuplicate: { onDuplicate(item) },
                onRemove: { remove(item.id) },
                onConfigureShortcuts: onConfigureShortcuts,
                onOpenLibrary: onOpenLibrary,
                onClose: { selectedItem = nil }
            )
            .id(item.id)
        } else {
            WidgetPalette(custom: customWidgets, onAdd: onAddWidget)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            PageIconPicker(symbol: page.symbol) { symbol in edit { $0.icon = symbol; return true } }
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .frame(maxWidth: 280)
                .focused($editsName)
                .onSubmit(commitName)
            Picker("Hintergrund", selection: Binding(
                get: { page.style.background },
                set: { background in edit { $0.style.background = background; return true } }
            )) {
                Text("Wie in den Einstellungen").tag(BackgroundStyle?.none)
                Divider()
                ForEach(BackgroundStyle.allCases, id: \.self) { style in
                    Label(style.title, systemImage: style.symbol).tag(BackgroundStyle?.some(style))
                }
            }
            .frame(maxWidth: 300)
            if let style = page.style.background, style.usesTint {
                PageTintButton(style: style, tint: page.style.tint) { tint in edit { $0.style.tint = tint; return true } }
            }
            Toggle("Gedimmt", isOn: Binding(
                get: { page.style.dimmed },
                set: { dimmed in edit { $0.style.dimmed = dimmed; return true } }
            ))
            .toggleStyle(.switch)
        }
    }

    private func remove(_ id: PlacedWidget.ID) {
        if selectedItem == id { selectedItem = nil }
        edit { $0.remove(id); return true }
    }

    private func update(_ id: PlacedWidget.ID, in page: inout StandPage, _ change: (inout PlacedWidget) -> Void) -> Bool {
        guard let index = page.items.firstIndex(where: { $0.id == id }) else { return false }
        change(&page.items[index])
        return true
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            name = page.name
            return
        }
        edit { $0.name = trimmed; return true }
    }

    private func edit(_ change: (inout StandPage) -> Bool) {
        var next = page
        guard change(&next), next != page else { return }
        withAnimation(.smooth) { onChange(next) }
    }
}
