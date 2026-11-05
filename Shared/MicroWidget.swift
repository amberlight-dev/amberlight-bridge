import Foundation

enum MicroWidget: String, Codable, CaseIterable, Identifiable {
    case usageLine, sessionPips, mascot, secondsOrbit, battery, nextEvent, macPulse, nowPlaying, custom

    var id: Self { self }

    var title: String {
        switch self {
        case .usageLine: String(localized: "Usage-Haarlinie")
        case .sessionPips: String(localized: "Session-Pips")
        case .mascot: String(localized: "Mini-Maskottchen")
        case .secondsOrbit: String(localized: "Sekunden-Umlauf")
        case .battery: String(localized: "Akku-Bogen")
        case .nextEvent: String(localized: "Nächster Termin")
        case .macPulse: String(localized: "Mac-Status")
        case .nowPlaying: "Now Playing"
        case .custom: String(localized: "Eigenes Widget")
        }
    }

    var symbol: String {
        switch self {
        case .usageLine: "gauge.with.dots.needle.33percent"
        case .sessionPips: "circle.grid.3x3"
        case .mascot: "leaf"
        case .secondsOrbit: "clock.arrow.circlepath"
        case .battery: "battery.75percent"
        case .nextEvent: "calendar"
        case .macPulse: "desktopcomputer"
        case .nowPlaying: "music.note"
        case .custom: "square.stack.3d.up"
        }
    }

    func fits(_ slot: MicroSlot) -> Bool {
        let edges: Set<MicroSlot> = [.top, .bottom, .leading, .trailing]
        let ears: Set<MicroSlot> = [.earBefore, .earAfter]
        switch self {
        case .secondsOrbit: return slot == .perimeter
        case .battery: return slot.isCorner
        case .mascot: return slot == .top || slot == .bottom
        case .usageLine: return edges.contains(slot)
        case .sessionPips, .macPulse: return edges.contains(slot) || ears.contains(slot)
        case .nextEvent, .nowPlaying: return slot == .top || slot == .bottom || ears.contains(slot)
        case .custom: return slot.isCorner || slot == .top || slot == .bottom || ears.contains(slot)
        }
    }
}

extension MicroWidget {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let widget = MicroWidget(rawValue: raw == StandWidget.legacyMascotRawValue ? MicroWidget.mascot.rawValue : raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unbekanntes Rand-Widget \(raw)"))
        }
        self = widget
    }
}

struct EdgeConfig: Equatable, RawRepresentable {
    var slots: [MicroSlot: MicroWidget]
    var customs: [MicroSlot: UUID]
    var hiddenPages: Set<UUID>

    static let standard = EdgeConfig(slots: [:], hiddenPages: [])
    private static let version = 2
    private static let formerDefaults: [MicroSlot: MicroWidget] = [.bottom: .usageLine, .top: .sessionPips]

    init(slots: [MicroSlot: MicroWidget], customs: [MicroSlot: UUID] = [:], hiddenPages: Set<UUID>) {
        self.slots = slots
        self.customs = customs.filter { slots[$0.key] == .custom }
        self.hiddenPages = hiddenPages
    }

    init?(rawValue: String) {
        guard let stored = try? JSONDecoder().decode(Stored.self, from: Data(rawValue.utf8)) else { return nil }
        let slots = stored.version == nil ? stored.slots.filter { Self.formerDefaults[$0.key] != $0.value } : stored.slots
        self.init(slots: slots, customs: stored.customs ?? [:], hiddenPages: stored.hiddenPages)
    }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(Stored(version: Self.version, slots: slots, customs: customs.isEmpty ? nil : customs, hiddenPages: hiddenPages)) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func == (lhs: EdgeConfig, rhs: EdgeConfig) -> Bool {
        lhs.slots == rhs.slots && lhs.customs == rhs.customs && lhs.hiddenPages == rhs.hiddenPages
    }

    private struct Stored: Codable {
        let version: Int?
        let slots: [MicroSlot: MicroWidget]
        var customs: [MicroSlot: UUID]?
        let hiddenPages: Set<UUID>
    }

    func uses(_ widget: MicroWidget) -> Bool {
        slots.values.contains(widget)
    }

    mutating func place(_ widget: MicroWidget?, custom: UUID? = nil, in slot: MicroSlot) {
        slots[slot] = widget
        customs[slot] = widget == .custom ? custom : nil
    }
}
