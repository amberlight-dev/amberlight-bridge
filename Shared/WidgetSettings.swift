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

    enum AgentsDisplay: String, Codable, CaseIterable, Identifiable {
        case list, cards

        var id: Self { self }

        var title: String {
            switch self {
            case .list: String(localized: "Liste")
            case .cards: String(localized: "Karten")
            }
        }
    }

    enum AgentsGrouping: String, Codable, CaseIterable, Identifiable {
        case none, repo, source

        var id: Self { self }

        var title: String {
            switch self {
            case .none: String(localized: "Keine")
            case .repo: String(localized: "Projekt")
            case .source: String(localized: "Quelle")
            }
        }
    }

    enum AgentsSource: String, Codable, CaseIterable, Identifiable {
        case all, claudeCode, codex

        var id: Self { self }

        var title: String {
            switch self {
            case .all: String(localized: "Alle")
            case .claudeCode: "Claude Code"
            case .codex: "Codex"
            }
        }

        func includes(agent: String?) -> Bool {
            switch self {
            case .all: true
            case .claudeCode: agent != "codex"
            case .codex: agent == "codex"
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
    var fullscreenAlerts: Bool?
    var showsOnlyActive: Bool?
    var showsSessionHeader: Bool?
    var showsOlderCount: Bool?
    var showsWeatherBelow: Bool?
    var prefersCompact: Bool?
    var radioStream: String?
    var radioName: String?
    var chatHidesPreview: Bool?
    var agentsDisplay: AgentsDisplay?
    var agentsGrouping: AgentsGrouping?
    var agentsSource: AgentsSource?
    var showsSubagents: Bool?
    var showsTodos: Bool?

    var seconds: Bool { showsSeconds ?? false }
    var date: Bool { showsDate ?? true }
    var usage: UsageWindow { usageWindow ?? .fiveHours }
    var controls: Bool { showsControls ?? true }
    var calendarTitles: [String] { calendarNames ?? [] }
    var focusLength: Int { focusMinutes ?? 25 }
    var breakLength: Int { breakMinutes ?? 5 }
    var fullscreen: Bool { fullscreenAlerts ?? false }
    var onlyActive: Bool { showsOnlyActive ?? false }
    var sessionHeader: Bool { !onlyActive && (showsSessionHeader ?? true) }
    var olderCount: Bool { !onlyActive && (showsOlderCount ?? true) }
    var weatherBelow: Bool { showsWeatherBelow ?? false }
    var compact: Bool { prefersCompact ?? false }
    var hidesChatPreview: Bool { chatHidesPreview ?? false }
    var display: AgentsDisplay { agentsDisplay ?? .list }
    var grouping: AgentsGrouping { agentsGrouping ?? .none }
    var source: AgentsSource { agentsSource ?? .all }
    var subagents: Bool { showsSubagents ?? true }
    var todos: Bool { showsTodos ?? true }

    func includes(repo: String) -> Bool {
        guard let filter = repoFilter?.trimmingCharacters(in: .whitespaces), !filter.isEmpty else { return true }
        return repo.localizedCaseInsensitiveContains(filter)
    }
}

extension StandWidget {
    var hasOwnSettings: Bool {
        switch self {
        case .clock, .agents, .usage, .mascot, .nowPlaying, .radio, .shortcuts, .calendar, .weather, .focus, .googleChat: true
        case .mac, .gitlab, .custom: false
        }
    }
}
