import Foundation

enum StandWidget: String, Codable, CaseIterable, Identifiable {
    case clock
    case claude
    case usage
    case mascot
    case nowPlaying = "spotify"
    case shortcuts
    case mac
    case calendar
    case weather
    case focus
    case orbit
    case gitlab
    case custom

    var id: Self { self }

    static let builtIn = allCases.filter { $0 != .custom }

    static func offered(orbitConfigured: Bool) -> [StandWidget] {
        builtIn.filter { $0 != .orbit || orbitConfigured }
    }

    var title: String {
        switch self {
        case .clock: String(localized: "Uhr")
        case .claude: String(localized: "Claude-Sessions")
        case .usage: "Usage"
        case .mascot: String(localized: "Maskottchen")
        case .nowPlaying: String(localized: "Läuft gerade")
        case .shortcuts: String(localized: "Schnellstart")
        case .mac: "Mac"
        case .calendar: String(localized: "Kalender")
        case .weather: String(localized: "Wetter")
        case .focus: String(localized: "Fokus-Timer")
        case .orbit: String(localized: "Orbit-Tickets")
        case .gitlab: "GitLab"
        case .custom: String(localized: "Eigenes Widget")
        }
    }

    var symbol: String {
        switch self {
        case .clock: "clock"
        case .claude: "sparkle"
        case .usage: "gauge.with.dots.needle.33percent"
        case .mascot: "leaf"
        case .nowPlaying: "music.note"
        case .shortcuts: "macwindow.on.rectangle"
        case .mac: "desktopcomputer"
        case .calendar: "calendar"
        case .weather: "cloud.sun"
        case .focus: "timer"
        case .orbit: "checklist"
        case .gitlab: "arrow.triangle.branch"
        case .custom: "square.stack.3d.up"
        }
    }
}

extension StandWidget {
    static let legacyMascotRawValue = "clawd"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let widget = StandWidget(rawValue: raw == Self.legacyMascotRawValue ? StandWidget.mascot.rawValue : raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unbekanntes Widget \(raw)"))
        }
        self = widget
    }
}
