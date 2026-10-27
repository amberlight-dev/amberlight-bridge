import Foundation

struct StandShortcut: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case app, url, shortcut
    }

    let kind: Kind
    let value: String
    let title: String

    var id: String { "\(kind.rawValue):\(value)" }

    var openPayload: [String: String] {
        [kind == .app ? "bundleId" : kind.rawValue: value]
    }

    var symbol: String {
        switch kind {
        case .app: "app.dashed"
        case .url: value.hasPrefix("file://") ? "folder" : "link"
        case .shortcut: "square.stack.3d.up"
        }
    }
}

struct ShortcutList: RawRepresentable, Equatable {
    var items: [StandShortcut]

    init(items: [StandShortcut]) {
        self.items = items
    }

    init?(rawValue: String) {
        guard let items = try? JSONDecoder().decode([StandShortcut].self, from: Data(rawValue.utf8)) else { return nil }
        self.items = items
    }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(items) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}
