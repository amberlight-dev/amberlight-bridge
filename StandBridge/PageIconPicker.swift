import AppKit
import SwiftUI

struct PageIconPicker: View {
    let symbol: String
    let onPick: (String) -> Void

    @State private var showsPicker = UserDefaults.standard.bool(forKey: "pickIcon")
    @State private var search = ""

    var body: some View {
        Button { showsPicker.toggle() } label: {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 34, height: 28)
        }
        .help("Icon der Seite ändern")
        .accessibilityLabel("Icon der Seite: \(symbol)")
        .popover(isPresented: $showsPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Symbol suchen oder Namen eingeben", text: $search)
                    .textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 6), count: 7), spacing: 6) {
                        ForEach(choices, id: \.self) { choice in
                            cell(choice)
                        }
                    }
                }
                .frame(height: 280)
                if choices.isEmpty {
                    Text("Kein passendes Symbol.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(width: 340)
        }
    }

    private var choices: [String] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return StandPage.iconChoices }
        let matches = StandPage.iconChoices.filter { $0.contains(query) }
        let typed = NSImage(systemSymbolName: query, accessibilityDescription: nil) != nil && !matches.contains(query) ? [query] : []
        return typed + matches
    }

    private func cell(_ choice: String) -> some View {
        let isCurrent = choice == symbol
        return Button {
            onPick(choice)
            showsPicker = false
        } label: {
            Image(systemName: choice)
                .font(.title3)
                .frame(width: 40, height: 36)
                .foregroundStyle(isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary.opacity(0.5)), in: .rect(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(choice)
        .accessibilityLabel(choice)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
