import Foundation

struct GridSpan: Codable, Hashable {
    var w: Int
    var h: Int

    func clamped(min lower: GridSpan, max upper: GridSpan) -> GridSpan {
        GridSpan(w: Swift.min(Swift.max(w, lower.w), upper.w), h: Swift.min(Swift.max(h, lower.h), upper.h))
    }
}

extension StandWidget {
    var minSpan: GridSpan {
        switch self {
        case .claude: GridSpan(w: 2, h: 2)
        case .clock, .usage, .mascot, .nowPlaying, .shortcuts, .mac, .calendar, .weather, .focus, .orbit, .gitlab, .custom: GridSpan(w: 1, h: 1)
        }
    }

    var maxSpan: GridSpan { GridSpan(w: 6, h: 4) }
}
