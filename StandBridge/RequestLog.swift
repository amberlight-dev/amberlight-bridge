import Foundation

struct ClientContact: Equatable {
    static let onlineWindow: TimeInterval = 10

    let at: Date
    let host: String

    func isOnline(now: Date = .now) -> Bool {
        now.timeIntervalSince(at) < Self.onlineWindow
    }
}

struct RequestLogEntry: Identifiable, Equatable {
    static let limit = 40
    static let quietPaths: Set<String> = ["/system", "/icon", "/custom"]

    let id = UUID()
    let at: Date
    let method: String
    let path: String
    let status: Int
    let host: String

    var title: String {
        switch (method, path) {
        case ("POST", "/hook"): String(localized: "Hook von Claude Code")
        case ("POST", "/answer"): String(localized: "Antwort vom iPhone")
        case ("POST", "/reply"): String(localized: "Antwort ans Mac-Fenster")
        case ("POST", "/focus"): String(localized: "Fenster nach vorn")
        case ("POST", "/open"): String(localized: "Shortcut geöffnet")
        case ("PUT", "/layout"): String(localized: "Anordnung empfangen")
        case ("GET", "/layout"): String(localized: "Anordnung abgeholt")
        case ("GET", "/apps"): String(localized: "App-Liste abgefragt")
        case ("GET", "/icon"): String(localized: "App-Icon abgefragt")
        case ("GET", "/system"): String(localized: "Mac-Werte abgefragt")
        default: "\(method) \(path)"
        }
    }

    var succeeded: Bool { (200..<300).contains(status) }
}
