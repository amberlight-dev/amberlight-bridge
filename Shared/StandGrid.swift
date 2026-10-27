import CoreGraphics
import Foundation

enum StandGrid {
    static let columns = 6
    static let rows = 4

    private struct Cell: Hashable {
        let x: Int
        let y: Int
    }

    static func cellFrames(in bounds: CGRect, columns: Int = columns, rows: Int = rows, gap: CGFloat) -> (GridRect) -> CGRect {
        let cellWidth = (bounds.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let cellHeight = (bounds.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        return { rect in
            CGRect(
                x: bounds.minX + CGFloat(rect.x) * (cellWidth + gap),
                y: bounds.minY + CGFloat(rect.y) * (cellHeight + gap),
                width: CGFloat(rect.w) * cellWidth + CGFloat(rect.w - 1) * gap,
                height: CGFloat(rect.h) * cellHeight + CGFloat(rect.h - 1) * gap
            )
        }
    }

    static func move(_ id: UUID, to target: GridRect, in items: [PlacedWidget], columns: Int = columns, rows: Int = rows) -> [PlacedWidget]? {
        guard let index = items.firstIndex(where: { $0.id == id }), fits(target, columns: columns, rows: rows) else { return nil }
        var moved = items[index]
        moved.frame = target
        let others = items.filter { $0.id != id }
        var placed = others.filter { !$0.frame.intersects(target) } + [moved]
        let displaced = others.filter { $0.frame.intersects(target) }.sorted { ($0.frame.y, $0.frame.x) < ($1.frame.y, $1.frame.x) }
        for var item in displaced {
            guard let slot = firstFreeSlot(for: item.frame.span, in: placed, columns: columns, rows: rows, startingAt: item.frame) else { return nil }
            item.frame = slot
            placed.append(item)
        }
        return items.compactMap { item in placed.first { $0.id == item.id } }
    }

    static func resize(_ id: UUID, to span: GridSpan, in items: [PlacedWidget], columns: Int = columns, rows: Int = rows) -> [PlacedWidget]? {
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        let room = GridSpan(w: columns - item.frame.x, h: rows - item.frame.y)
        let upper = GridSpan(w: min(item.widget.maxSpan.w, room.w), h: min(item.widget.maxSpan.h, room.h))
        let clamped = span.clamped(min: item.widget.minSpan, max: upper)
        return move(id, to: GridRect(x: item.frame.x, y: item.frame.y, span: clamped), in: items, columns: columns, rows: rows)
    }

    static func firstFreeSlot(for span: GridSpan, in items: [PlacedWidget], columns: Int = columns, rows: Int = rows) -> GridRect? {
        firstFreeSlot(for: span, in: items, columns: columns, rows: rows, startingAt: nil)
    }

    static func reflow(_ items: [PlacedWidget], columns: Int) -> [PlacedWidget] {
        var placed: [PlacedWidget] = []
        for var item in items.sorted(by: { ($0.frame.y, $0.frame.x) < ($1.frame.y, $1.frame.x) }) {
            let span = GridSpan(w: min(item.frame.w, columns), h: item.frame.h)
            let occupied = cells(of: placed)
            var y = 0
            while true {
                if let x = (0...(columns - span.w)).first(where: { isFree(GridRect(x: $0, y: y, span: span), occupied) }) {
                    item.frame = GridRect(x: x, y: y, span: span)
                    break
                }
                y += 1
            }
            placed.append(item)
        }
        return items.compactMap { item in placed.first { $0.id == item.id } }
    }

    private static func firstFreeSlot(for span: GridSpan, in items: [PlacedWidget], columns: Int, rows: Int, startingAt origin: GridRect?) -> GridRect? {
        guard span.w <= columns, span.h <= rows else { return nil }
        let occupied = cells(of: items)
        let candidates = (0...(rows - span.h)).flatMap { y in (0...(columns - span.w)).map { x in GridRect(x: x, y: y, span: span) } }
        let start = origin.flatMap { origin in candidates.firstIndex { ($0.y, $0.x) >= (origin.y, origin.x) } } ?? 0
        let ordered = candidates[start...] + candidates[..<start]
        return ordered.first { isFree($0, occupied) }
    }

    private static func fits(_ rect: GridRect, columns: Int, rows: Int) -> Bool {
        rect.x >= 0 && rect.y >= 0 && rect.w >= 1 && rect.h >= 1 && rect.maxX <= columns && rect.maxY <= rows
    }

    private static func cells(of items: [PlacedWidget]) -> Set<Cell> {
        Set(items.flatMap { item in
            (item.frame.x..<item.frame.maxX).flatMap { x in (item.frame.y..<item.frame.maxY).map { y in Cell(x: x, y: y) } }
        })
    }

    private static func isFree(_ rect: GridRect, _ occupied: Set<Cell>) -> Bool {
        (rect.x..<rect.maxX).allSatisfy { x in (rect.y..<rect.maxY).allSatisfy { y in !occupied.contains(Cell(x: x, y: y)) } }
    }
}
