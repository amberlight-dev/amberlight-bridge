import Foundation

enum WindowPrimer {
    static let enabledKey = "primeWindow"
    static let minuteKey = "primeWindowMinute"
    static let lastRunKey = "primeWindowLastRun"
    static let lastResultKey = "primeWindowLastResult"
    static let defaultMinute = 7 * 60
    static let latestStart: TimeInterval = 3 * 3600
    private static let claudePaths = [".local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]

    static var claude: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return claudePaths
            .map { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : home.appending(path: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func sessionWindow(of board: Board) -> JSON? {
        (Usage.providers([board.statuslineUsage()]).first?["windows"] as? [JSON])?.first
    }

    static func isDue(now: Date, minute: Int, lastRun: Date?, sessionWindow: JSON?, calendar: Calendar = .current) -> Bool {
        isInSlot(now: now, minute: minute, lastRun: lastRun, calendar: calendar) && !isActive(sessionWindow, now: now)
    }

    static func isInSlot(now: Date, minute: Int, lastRun: Date?, calendar: Calendar = .current) -> Bool {
        guard let start = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: now),
              now >= start, now.timeIntervalSince(start) < latestStart else { return false }
        return lastRun.map { $0 < start } ?? true
    }

    private static func isActive(_ window: JSON?, now: Date) -> Bool {
        guard let resetsAt = window?["resetsAt"] as? Double, window?["used"] as? Double ?? 0 > 0 else { return false }
        return resetsAt > now.timeIntervalSince1970
    }

    static func run(sessionWindow: @escaping @MainActor () -> JSON?) async {
        let defaults = UserDefaults.standard
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard defaults.bool(forKey: enabledKey) else { continue }
            let minute = defaults.object(forKey: minuteKey) as? Int ?? defaultMinute
            let lastRun = (defaults.object(forKey: lastRunKey) as? Double).map(Date.init(timeIntervalSince1970:))
            guard isInSlot(now: .now, minute: minute, lastRun: lastRun), !isActive(sessionWindow(), now: .now) else { continue }
            defaults.set(Date.now.timeIntervalSince1970, forKey: lastRunKey)
            defaults.set(await prime() ? "Gestartet" : "Fehlgeschlagen", forKey: lastResultKey)
        }
    }

    private static func prime() async -> Bool {
        guard let claude else { return false }
        return await ProcessRunner.output(
            of: claude,
            arguments: ["-p", "Antworte nur mit ok.", "--model", "haiku", "--setting-sources", "project", "--no-session-persistence"],
            in: FileManager.default.temporaryDirectory
        ) != nil
    }
}
