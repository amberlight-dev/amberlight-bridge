import SwiftUI

struct WidgetSpanPreview: View {
    let span: GridSpan
    var cell: CGFloat = 7
    var gap: CGFloat = 2

    var body: some View {
        Grid(horizontalSpacing: gap, verticalSpacing: gap) {
            ForEach(0..<StandGrid.rows, id: \.self) { y in
                GridRow {
                    ForEach(0..<StandGrid.columns, id: \.self) { x in
                        RoundedRectangle(cornerRadius: cell / 4, style: .continuous)
                            .fill(.primary.opacity(x < span.w && y < span.h ? 0.85 : 0.14))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
