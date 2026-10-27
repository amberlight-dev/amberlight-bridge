import SwiftUI

struct PageCanvas: View {
    static let screen = CGSize(width: 852, height: 393)
    static let screenGap: CGFloat = 20
    static let screenPadding: CGFloat = 28
    static let screenCorner: CGFloat = 22

    let page: StandPage
    let selectedItem: PlacedWidget.ID?
    let onSelect: (PlacedWidget.ID?) -> Void
    let onMove: (UUID, GridRect) -> Void
    let onResize: (UUID, GridSpan) -> Void
    let onRemove: (UUID) -> Void

    @State private var arranging = 0

    var body: some View {
        GeometryReader { proxy in
            let metrics = Metrics(size: proxy.size)
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { onSelect(nil) }
                ForEach(Self.allCells, id: \.self) { rect in
                    let frame = metrics.frame(for: rect)
                    RoundedRectangle(cornerRadius: metrics.corner, style: .continuous)
                        .fill(.white.opacity(0.05))
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
                .opacity(arranging > 0 || page.items.isEmpty ? 1 : 0)
                .allowsHitTesting(false)
                ForEach(page.items) { item in
                    let frame = metrics.frame(for: item.frame)
                    LayoutTile(
                        item: item,
                        step: metrics.step,
                        gap: metrics.gap,
                        corner: metrics.corner,
                        isSelected: item.id == selectedItem,
                        onSelect: { onSelect(item.id) },
                        onMove: { onMove(item.id, $0) },
                        onResize: { onResize(item.id, $0) },
                        onRemove: { onRemove(item.id) },
                        onArranging: { arranging += $0 ? 1 : -1 }
                    )
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                }
            }
            .animation(.smooth(duration: 0.2), value: arranging > 0)
        }
        .aspectRatio(Self.screen.width / Self.screen.height, contentMode: .fit)
        .background(.black.opacity(page.style.dimmed ? 0.95 : 0.85), in: .rect(cornerRadius: 36, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private static let allCells = (0..<StandGrid.rows).flatMap { y in
        (0..<StandGrid.columns).map { x in GridRect(x: x, y: y, w: 1, h: 1) }
    }

    struct Metrics {
        let gap: CGFloat
        let corner: CGFloat
        let step: CGSize
        private let cellFrame: (GridRect) -> CGRect

        init(size: CGSize) {
            let scale = size.width / PageCanvas.screen.width
            let padding = PageCanvas.screenPadding * scale
            gap = PageCanvas.screenGap * scale
            corner = PageCanvas.screenCorner * scale
            let cellFrame = StandGrid.cellFrames(in: CGRect(origin: .zero, size: size).insetBy(dx: padding, dy: padding), gap: gap)
            let unit = cellFrame(GridRect(x: 0, y: 0, w: 1, h: 1))
            self.cellFrame = cellFrame
            step = CGSize(width: unit.width + gap, height: unit.height + gap)
        }

        func frame(for rect: GridRect) -> CGRect {
            cellFrame(rect)
        }
    }
}
