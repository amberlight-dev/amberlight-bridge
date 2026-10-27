import Foundation

extension IdleSessionWindow: Codable {}

struct WidgetSettings: Codable, Hashable {
    enum UsageWindow: String, Codable, CaseIterable, Identifiable {
        case fiveHours, week

        var id: Self { self }

        var title: String {
            switch self {
            case .fiveHours: String(localized: "5h-Fenster")
            case .week: String(localized: "Woche")
            }
        }
    }

    var showsSeconds: Bool?
    var showsDate: Bool?
    var usageWindow: UsageWindow?
    var idleWindow: IdleSessionWindow?
    var repoFilter: String?
    var showsControls: Bool?
    var calendarNames: [String]?
    var weatherCity: String?
    var focusMinutes: Int?
    var breakMinutes: Int?
    var mascot: Mascot?
    var customID: UUID?
    var customName: String?

    var seconds: Bool { showsSeconds ?? false }
    var date: Bool { showsDate ?? true }
    var usage: UsageWindow { usageWindow ?? .fiveHours }
    var controls: Bool { showsControls ?? true }
    var calendarTitles: [String] { calendarNames ?? [] }
    var focusLength: Int { focusMinutes ?? 25 }
    var breakLength: Int { breakMinutes ?? 5 }

    func includes(repo: String) -> Bool {
        guard let filter = repoFilter?.trimmingCharacters(in: .whitespaces), !filter.isEmpty else { return true }
        return repo.localizedCaseInsensitiveContains(filter)
    }
}

extension StandWidget {
    var hasOwnSettings: Bool {
        switch self {
        case .clock, .claude, .usage, .mascot, .nowPlaying, .shortcuts, .calendar, .weather, .focus: true
        case .mac, .orbit, .gitlab, .custom: false
        }
    }
}
