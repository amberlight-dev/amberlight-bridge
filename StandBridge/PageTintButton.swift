import SwiftUI

struct PageTintButton: View {
    let style: BackgroundStyle
    let tint: BackgroundTint?
    let onChange: (BackgroundTint?) -> Void

    @State private var showsTint = false

    var body: some View {
        Button(style == .pulse ? "Puls …" : "Farbe …", systemImage: "paintpalette") { showsTint.toggle() }
            .help("Farbe dieses Hintergrunds nur für diese Seite einstellen")
            .popover(isPresented: $showsTint, arrowEdge: .bottom) {
                Form {
                    BackgroundTintSection(style: style, tint: Binding(
                        get: { tint ?? BackgroundTint() },
                        set: { onChange($0) }
                    ))
                    if tint != nil {
                        Section {
                            Button("Wie in den Einstellungen", systemImage: "arrow.uturn.backward") { onChange(nil) }
                        }
                    }
                }
                .formStyle(.grouped)
                .frame(width: 380)
                .fixedSize(horizontal: false, vertical: true)
            }
    }
}
