import Foundation

enum IdleSessionWindow: String, CaseIterable, Identifiable {
    case none, thirtyMinutes, twoHours, today, all

    var id: Self { self }

    var title: String {
        switch self {
        case .none: String(localized: "Nur aktive")
        case .thirtyMinutes: String(localized: "Letzte 30 Minuten")
        case .twoHours: String(localized: "Letzte 2 Stunden")
        case .today: String(localized: "Heute")
        case .all: String(localized: "Alle")
        }
    }

    func includes(lastActive: Date?, now: Date = .now) -> Bool {
        guard let lastActive else { return self == .all }
        switch self {
        case .none: return false
        case .thirtyMinutes: return now.timeIntervalSince(lastActive) <= 30 * 60
        case .twoHours: return now.timeIntervalSince(lastActive) <= 2 * 60 * 60
        case .today: return Calendar.current.isDate(lastActive, inSameDayAs: now)
        case .all: return true
        }
    }
}
