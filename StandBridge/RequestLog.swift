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
        case ("POST", "/hook"): "Hook von Claude Code"
        case ("POST", "/answer"): "Antwort vom iPhone"
        case ("POST", "/reply"): "Antwort ans Mac-Fenster"
        case ("POST", "/focus"): "Fenster nach vorn"
        case ("POST", "/open"): "Shortcut geöffnet"
        case ("PUT", "/layout"): "Anordnung empfangen"
        case ("GET", "/layout"): "Anordnung abgeholt"
        case ("GET", "/apps"): "App-Liste abgefragt"
        case ("GET", "/icon"): "App-Icon abgefragt"
        case ("GET", "/system"): "Mac-Werte abgefragt"
        default: "\(method) \(path)"
        }
    }

    var succeeded: Bool { (200..<300).contains(status) }
}
