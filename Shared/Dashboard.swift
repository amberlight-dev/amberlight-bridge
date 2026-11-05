import Foundation

enum StandWidget: String, Codable, CaseIterable, Identifiable {
    case clock
    case agents = "claude"
    case usage
    case mascot
    case nowPlaying = "spotify"
    case radio = "nts"
    case shortcuts
    case mac
    case calendar
    case weather
    case focus
    case gitlab
    case googleChat
    case custom

    var id: Self { self }

    static let builtIn = allCases.filter { $0 != .custom }

    var title: String {
        switch self {
        case .clock: String(localized: "Uhr")
        case .agents: String(localized: "Agents")
        case .usage: "Usage"
        case .mascot: String(localized: "Maskottchen")
        case .nowPlaying: String(localized: "Läuft gerade")
        case .radio: String(localized: "Internetradio")
        case .shortcuts: String(localized: "Schnellstart")
        case .mac: "Mac"
        case .calendar: String(localized: "Kalender")
        case .weather: String(localized: "Wetter")
        case .focus: String(localized: "Fokus-Timer")
        case .gitlab: "GitLab"
        case .googleChat: "Google Chat"
        case .custom: String(localized: "Eigenes Widget")
        }
    }

    var symbol: String {
        switch self {
        case .clock: "clock"
        case .agents: "sparkle"
        case .usage: "gauge.with.dots.needle.33percent"
        case .mascot: "leaf"
        case .nowPlaying: "music.note"
        case .radio: "radio"
        case .shortcuts: "macwindow.on.rectangle"
        case .mac: "desktopcomputer"
        case .calendar: "calendar"
        case .weather: "cloud.sun"
        case .focus: "timer"
        case .gitlab: "arrow.triangle.branch"
        case .googleChat: "bubble.left.and.text.bubble.right"
        case .custom: "square.stack.3d.up"
        }
    }
}

extension StandWidget {
    static let legacyMascotRawValue = "clawd"
    static let legacyOrchestraRawValue = "orchestra"

    static func migrated(_ raw: String) -> String {
        switch raw {
        case legacyMascotRawValue: mascot.rawValue
        case legacyOrchestraRawValue: agents.rawValue
        default: raw
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let widget = StandWidget(rawValue: Self.migrated(raw)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unbekanntes Widget \(raw)"))
        }
        self = widget
    }
}
