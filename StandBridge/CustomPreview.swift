import SwiftUI

struct CustomPreview: View {
    let display: CustomWidgetDisplay?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            tile(GridSpan(w: 1, h: 1))
            tile(GridSpan(w: 2, h: 1))
            tile(GridSpan(w: 2, h: 2))
        }
    }

    private func tile(_ span: GridSpan) -> some View {
        VStack(spacing: 4) {
            CustomTile(display: display, span: span, notice: "Noch nicht getestet")
            Text("\(span.w)×\(span.h)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

struct CustomTile: View {
    let display: CustomWidgetDisplay?
    let span: GridSpan
    var notice = "Keine Daten"

    private let cell: CGFloat = 54
    private let gap: CGFloat = 6

    var body: some View {
        CustomWidgetView(display: display, span: span, dimmed: false, notice: notice)
            .padding(10)
            .frame(width: CGFloat(span.w) * cell + CGFloat(span.w - 1) * gap, height: CGFloat(span.h) * cell + CGFloat(span.h - 1) * gap)
            .background(Color(white: 0.08), in: .rect(cornerRadius: 14, style: .continuous))
            .environment(\.colorScheme, .dark)
    }
}
