import SwiftUI

struct LayoutTile: View {
    let item: PlacedWidget
    let step: CGSize
    let gap: CGFloat
    let corner: CGFloat
    let isSelected: Bool
    let onSelect: () -> Void
    let onMove: (GridRect) -> Void
    let onResize: (GridSpan) -> Void
    let onRemove: () -> Void
    let onArranging: (Bool) -> Void

    @State private var drag = CGSize.zero
    @State private var stretch = CGSize.zero
    @State private var hovers = false
    @State private var isArranging = false

    private var grid: GridRect { item.frame }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: corner, style: .continuous) }

    var body: some View {
        label
            .background(Color(white: hovers || drag != .zero ? 0.21 : 0.16), in: shape)
            .overlay { shape.strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.14)), lineWidth: isSelected ? 2.5 : 1) }
            .overlay(alignment: .topLeading) { ghost(offset: snappedOffset, span: grid.span).opacity(drag == .zero ? 0 : 1) }
            .overlay(alignment: .topLeading) { ghost(offset: .zero, span: stretchedSpan).opacity(stretch == .zero ? 0 : 1) }
            .contentShape(shape)
            .offset(drag)
            .overlay(alignment: .topLeading) { removeButton.offset(drag).opacity(hovers && drag == .zero && stretch == .zero ? 1 : 0) }
            .overlay(alignment: .bottomTrailing) { resizeHandle }
            .gesture(moveGesture)
            .onTapGesture(perform: onSelect)
            .onHover { hovers = $0 }
            .contextMenu {
                Button("Einstellungen", systemImage: "slider.horizontal.3", action: onSelect)
                Button("Entfernen", systemImage: "trash", role: .destructive, action: onRemove)
            }
            .zIndex(drag == .zero && stretch == .zero ? 0 : 1)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(item.title), \(grid.w) mal \(grid.h)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction(named: "Einstellungen", onSelect)
    }

    private var label: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 4) {
                icon(size: 26)
                title
                spanText
            }
            HStack(spacing: 8) {
                icon(size: 18)
                VStack(alignment: .leading, spacing: 0) {
                    title
                    spanText
                }
            }
            HStack(spacing: 6) {
                icon(size: 14)
                title
            }
            icon(size: 14)
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func icon(size: CGFloat) -> some View {
        Image(systemName: item.widget.symbol)
            .font(.system(size: size))
    }

    private var title: some View {
        Text(item.title)
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var spanText: some View {
        Text("\(displaySpan.w)×\(displaySpan.h)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
    }

    private func arrange(_ active: Bool) {
        guard active != isArranging else { return }
        isArranging = active
        onArranging(active)
    }

    private var displaySpan: GridSpan { stretch == .zero ? grid.span : stretchedSpan }

    private var snappedCells: (dx: Int, dy: Int) {
        let dx = Self.cells(drag.width, per: step.width)
        let dy = Self.cells(drag.height, per: step.height)
        return (
            min(max(dx, -grid.x), StandGrid.columns - grid.maxX),
            min(max(dy, -grid.y), StandGrid.rows - grid.maxY)
        )
    }

    private var snappedOffset: CGSize {
        CGSize(width: CGFloat(snappedCells.dx) * step.width - drag.width, height: CGFloat(snappedCells.dy) * step.height - drag.height)
    }

    private var stretchedSpan: GridSpan {
        let wanted = GridSpan(
            w: grid.w + Self.cells(stretch.width, per: step.width),
            h: grid.h + Self.cells(stretch.height, per: step.height)
        )
        let room = GridSpan(
            w: min(item.widget.maxSpan.w, StandGrid.columns - grid.x),
            h: min(item.widget.maxSpan.h, StandGrid.rows - grid.y)
        )
        return wanted.clamped(min: item.widget.minSpan, max: room)
    }

    static func cells(_ distance: CGFloat, per step: CGFloat) -> Int {
        let cells = (distance / step).rounded()
        guard step > 0, cells.isFinite else { return 0 }
        return Int(max(min(cells, 100), -100))
    }

    private func ghost(offset: CGSize, span: GridSpan) -> some View {
        shape
            .fill(.white.opacity(0.12))
            .overlay { shape.strokeBorder(.white.opacity(0.7), lineWidth: 2) }
            .frame(width: max(CGFloat(span.w) * step.width - gap, 0), height: max(CGFloat(span.h) * step.height - gap, 0))
            .offset(offset)
            .allowsHitTesting(false)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged {
                drag = $0.translation
                arrange(true)
            }
            .onEnded { _ in
                let cells = snappedCells
                drag = .zero
                arrange(false)
                guard cells.dx != 0 || cells.dy != 0 else { return }
                onMove(GridRect(x: grid.x + cells.dx, y: grid.y + cells.dy, w: grid.w, h: grid.h))
            }
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(.red, in: .circle)
        }
        .buttonStyle(.plain)
        .padding(6)
        .help("Widget entfernen")
        .accessibilityLabel("Widget entfernen")
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(.white.opacity(0.25), in: .circle)
            .padding(6)
            .contentShape(.rect)
            .opacity(drag == .zero && (hovers || stretch != .zero) ? 1 : 0)
            .pointerStyle(.frameResize(position: .bottomTrailing))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged {
                        stretch = $0.translation
                        arrange(true)
                    }
                    .onEnded { _ in
                        let span = stretchedSpan
                        stretch = .zero
                        arrange(false)
                        guard span != grid.span else { return }
                        onResize(span)
                    }
            )
            .help("Größe ändern")
            .accessibilityLabel("Größe ändern")
    }
}
