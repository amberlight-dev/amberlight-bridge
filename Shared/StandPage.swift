import Foundation

struct GridRect: Codable, Hashable {
    var x: Int
    var y: Int
    var w: Int
    var h: Int

    init(x: Int, y: Int, w: Int, h: Int) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    init(x: Int, y: Int, span: GridSpan) {
        self.init(x: x, y: y, w: span.w, h: span.h)
    }

    var span: GridSpan { GridSpan(w: w, h: h) }
    var maxX: Int { x + w }
    var maxY: Int { y + h }

    func intersects(_ other: GridRect) -> Bool {
        x < other.maxX && other.x < maxX && y < other.maxY && other.y < maxY
    }
}

struct PlacedWidget: Codable, Hashable, Identifiable {
    var id = UUID()
    var widget: StandWidget
    var frame: GridRect
    var settings: WidgetSettings?
}

extension BackgroundStyle: Codable {}

struct PageStyle: Codable, Hashable {
    var background: BackgroundStyle?
    var dimmed = false
    var tint: BackgroundTint?
}

struct StandPage: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var style = PageStyle()
    var items: [PlacedWidget]
    var icon: String?

    static func desk() -> StandPage {
        StandPage(name: "Schreibtisch", items: [
            PlacedWidget(widget: .clock, frame: GridRect(x: 0, y: 0, w: 2, h: 2)),
            PlacedWidget(widget: .usage, frame: GridRect(x: 0, y: 2, w: 2, h: 2)),
            PlacedWidget(widget: .claude, frame: GridRect(x: 2, y: 0, w: 4, h: 4)),
        ], icon: "desktopcomputer")
    }

    static func nightstand() -> StandPage {
        StandPage(name: "Nachttisch", style: PageStyle(dimmed: true), items: [
            PlacedWidget(widget: .clock, frame: GridRect(x: 0, y: 0, w: StandGrid.columns, h: StandGrid.rows)),
        ], icon: "moon")
    }

    static func turntable() -> StandPage {
        StandPage(name: "Plattenspieler", items: [
            PlacedWidget(widget: .nowPlaying, frame: GridRect(x: 0, y: 0, w: StandGrid.columns, h: StandGrid.rows)),
        ], icon: "opticaldisc")
    }
}

struct StandPages: RawRepresentable, Equatable {
    var pages: [StandPage]

    init(pages: [StandPage]) {
        self.pages = pages
    }

    init?(rawValue: String) {
        guard let pages = try? JSONDecoder().decode([StandPage].self, from: Data(rawValue.utf8)) else { return nil }
        self.pages = pages
    }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(pages) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    static func initial(legacyDesk: String?) -> StandPages {
        StandPages(pages: [migratedDesk(from: legacyDesk) ?? .desk(), .nightstand(), .turntable()])
    }

    static func migratedDesk(from legacyDesk: String?) -> StandPage? {
        guard let data = legacyDesk?.data(using: .utf8),
              let legacy = try? JSONDecoder().decode([LegacyItem].self, from: data),
              !legacy.isEmpty else { return nil }
        let widths = columnWidths(weights: legacy.map { $0.isLarge ? 2 : 1 }, minimums: legacy.map { $0.widget.minSpan.w })
        var items: [PlacedWidget] = []
        var x = 0
        for (item, width) in zip(legacy, widths) {
            let span = GridSpan(w: width, h: StandGrid.rows)
            if x + width <= StandGrid.columns {
                items.append(PlacedWidget(widget: item.widget, frame: GridRect(x: x, y: 0, span: span)))
                x += width
            } else if let slot = StandGrid.firstFreeSlot(for: item.widget.minSpan, in: items) {
                items.append(PlacedWidget(widget: item.widget, frame: slot))
            }
        }
        return StandPage(name: "Schreibtisch", items: items)
    }

    private struct LegacyItem: Decodable {
        let widget: StandWidget
        let isLarge: Bool
    }

    private static func columnWidths(weights: [Int], minimums: [Int]) -> [Int] {
        let total = weights.reduce(0, +)
        var widths = zip(weights, minimums).map { weight, minimum in
            max(minimum, StandGrid.columns * weight / max(total, 1))
        }
        var spare = StandGrid.columns - widths.reduce(0, +)
        var index = 0
        while spare > 0, !widths.isEmpty {
            widths[index % widths.count] += 1
            spare -= 1
            index += 1
        }
        return widths
    }
}

extension StandPage {
    mutating func move(_ id: UUID, to frame: GridRect) -> Bool {
        guard let moved = StandGrid.move(id, to: frame, in: items) else { return false }
        items = moved
        return true
    }

    mutating func resize(_ id: UUID, to span: GridSpan) -> Bool {
        guard let resized = StandGrid.resize(id, to: span, in: items) else { return false }
        items = resized
        return true
    }

    mutating func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    mutating func add(_ widget: StandWidget, span: GridSpan) -> Bool {
        guard let slot = StandGrid.firstFreeSlot(for: span, in: items) else { return false }
        items.append(PlacedWidget(widget: widget, frame: slot))
        return true
    }

    func reflowed(columns: Int) -> StandPage {
        var page = self
        let capped = items.map { item in
            var item = item
            item.frame.h = min(item.frame.h, item.widget.reflowMaxRows)
            return item
        }
        page.items = StandGrid.reflow(capped, columns: columns)
        return page
    }

    func canPlace(_ span: GridSpan) -> Bool {
        StandGrid.firstFreeSlot(for: span, in: items) != nil
    }
}

extension StandWidget {
    var reflowMaxRows: Int {
        switch self {
        case .claude, .calendar, .orbit, .gitlab, .custom: StandGrid.rows
        case .mascot: 1
        case .clock, .usage, .nowPlaying, .shortcuts, .mac, .weather, .focus: 2
        }
    }

    var galleryPresets: [GridSpan] {
        switch self {
        case .clock: [GridSpan(w: 1, h: 1), GridSpan(w: 2, h: 1), GridSpan(w: 2, h: 2), GridSpan(w: 4, h: 2), GridSpan(w: 6, h: 4)]
        case .claude: [GridSpan(w: 2, h: 2), GridSpan(w: 3, h: 4), GridSpan(w: 4, h: 4)]
        case .usage: [GridSpan(w: 1, h: 1), GridSpan(w: 2, h: 2), GridSpan(w: 2, h: 4)]
        case .mascot: [GridSpan(w: 1, h: 1), GridSpan(w: 2, h: 1)]
        case .nowPlaying: [GridSpan(w: 1, h: 1), GridSpan(w: 2, h: 1), GridSpan(w: 3, h: 2), GridSpan(w: 6, h: 4)]
        case .shortcuts: [GridSpan(w: 6, h: 1), GridSpan(w: 2, h: 2), GridSpan(w: 3, h: 2)]
        case .mac: [GridSpan(w: 1, h: 1), GridSpan(w: 2, h: 1), GridSpan(w: 2, h: 2), GridSpan(w: 4, h: 2)]
        case .calendar: [GridSpan(w: 1, h: 1), GridSpan(w: 2, h: 1), GridSpan(w: 2, h: 2), GridSpan(w: 3, h: 4)]
        case .weather: [GridSpan(w: 1, h: 1), GridSpan(w: 2, h: 1), GridSpan(w: 3, h: 2), GridSpan(w: 6, h: 2)]
        case .focus: [GridSpan(w: 1, h: 1), GridSpan(w: 2, h: 1), GridSpan(w: 3, h: 2)]
        case .orbit: [GridSpan(w: 1, h: 1), GridSpan(w: 2, h: 1), GridSpan(w: 3, h: 2), GridSpan(w: 3, h: 4)]
        case .gitlab: [GridSpan(w: 1, h: 1), GridSpan(w: 2, h: 1), GridSpan(w: 3, h: 2), GridSpan(w: 3, h: 4)]
        case .custom: [GridSpan(w: 1, h: 1), GridSpan(w: 2, h: 1), GridSpan(w: 2, h: 2), GridSpan(w: 3, h: 2), GridSpan(w: 4, h: 3)]
        }
    }
}
