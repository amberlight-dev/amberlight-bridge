import Foundation
import Observation

@Observable
final class LayoutStore {
    static let defaultPort: UInt16 = 7420
    static let keptBackups = 5

    static func file(forPort port: UInt16) -> URL {
        URL.applicationSupportDirectory.appending(path: port == defaultPort ? "Stand Bridge/layout.json" : "Stand Bridge/layout-\(port).json")
    }

    private(set) var revision = 0
    private(set) var pages: [StandPage] = []
    private(set) var shortcuts: [StandShortcut] = []
    private(set) var edgesRaw: String?
    private(set) var preferences = StandPreferences()
    private(set) var device: StandDeviceStatus?
    @ObservationIgnored private let file: URL?

    init(file: URL?) {
        self.file = file
        guard let file, let data = try? Data(contentsOf: file),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        revision = saved.revision
        pages = saved.pages
        shortcuts = saved.shortcuts ?? []
        edgesRaw = saved.edges
        preferences = saved.preferences ?? StandPreferences()
        device = saved.device
    }

    @discardableResult
    func replace(_ pages: [StandPage], shortcuts: [StandShortcut]? = nil, edges: String? = nil,
                 preferences: StandPreferences? = nil, device: StandDeviceStatus? = nil) throws -> Int {
        let next = Saved(
            revision: revision + 1, pages: pages, shortcuts: shortcuts ?? self.shortcuts, edges: edges ?? edgesRaw,
            preferences: preferences ?? self.preferences, device: device ?? self.device
        )
        if let file {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            Self.backUp(file, revision: revision)
            try JSONEncoder().encode(next).write(to: file, options: .atomic)
        }
        revision = next.revision
        self.pages = pages
        self.shortcuts = next.shortcuts ?? []
        edgesRaw = next.edges
        self.preferences = next.preferences ?? StandPreferences()
        self.device = next.device
        return revision
    }

    func update(_ transform: (inout [StandPage]) -> Void) {
        var next = pages
        transform(&next)
        guard next != pages else { return }
        try? replace(next)
    }

    func updateShortcuts(_ transform: (inout [StandShortcut]) -> Void) {
        var next = shortcuts
        transform(&next)
        guard next != shortcuts else { return }
        try? replace(pages, shortcuts: next)
    }

    var folderLinks: Set<String> {
        Set(shortcuts.filter(Self.isFolderLink).map(\.value))
    }

    private static func isFolderLink(_ shortcut: StandShortcut) -> Bool {
        shortcut.kind == .url && shortcut.value.lowercased().hasPrefix("file:")
    }

    var edges: EdgeConfig {
        edgesRaw.flatMap(EdgeConfig.init(rawValue:)) ?? .standard
    }

    func updateEdges(_ edges: EdgeConfig) {
        guard edges != self.edges || edgesRaw == nil else { return }
        try? replace(pages, edges: edges.rawValue)
    }

    func updatePreferences(_ transform: (inout StandPreferences) -> Void) {
        var next = preferences
        transform(&next)
        guard next != preferences else { return }
        try? replace(pages, preferences: next)
    }

    var json: JSON {
        var json: JSON = ["revision": revision, "pages": Self.jsonObject(pages) ?? [], "shortcuts": Self.jsonObject(shortcuts) ?? []]
        if let edgesRaw { json["edges"] = edgesRaw }
        if let preferences = Self.jsonObject(preferences) { json["preferences"] = preferences }
        if let device, let status = Self.jsonObject(device) { json["device"] = status }
        return json
    }

    func replace(json: JSON) -> Int? {
        guard let pages: [StandPage] = Self.decode(json["pages"]) else { return nil }
        let shortcuts: [StandShortcut]?
        if json["shortcuts"] == nil {
            shortcuts = nil
        } else {
            guard let decoded: [StandShortcut] = Self.decode(json["shortcuts"]) else { return nil }
            shortcuts = decoded.filter { !Self.isFolderLink($0) || self.shortcuts.contains($0) }
        }
        if json["edges"] != nil, !(json["edges"] is String) { return nil }
        let incoming: StandPreferences? = json["preferences"] == nil ? nil : Self.decode(json["preferences"])
        let device: StandDeviceStatus? = json["device"] == nil ? nil : Self.decode(json["device"])
        if json["preferences"] != nil && incoming == nil || json["device"] != nil && device == nil { return nil }
        return try? replace(pages, shortcuts: shortcuts, edges: json["edges"] as? String,
                            preferences: incoming?.merged(over: preferences), device: device)
    }

    func storeDeviceBackup(json: JSON, at date: Date = .now) -> Bool {
        guard let file, let _: [StandPage] = Self.decode(json["pages"]),
              let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) else { return false }
        let stamp = Int(date.timeIntervalSince1970 * 1000)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? data.write(to: Self.rotated(file, kind: .device, number: stamp), options: .atomic)) != nil else { return false }
        Self.prune(file, kind: .device)
        return true
    }

    enum BackupKind: String {
        case revision = "backup-r"
        case device = "device-backup-"
    }

    static func backups(of file: URL, kind: BackupKind = .revision) -> [(revision: Int, url: URL)] {
        let prefix = file.deletingPathExtension().lastPathComponent + "." + kind.rawValue
        let folder = file.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names
            .compactMap { name in
                guard name.hasPrefix(prefix), name.hasSuffix(".json"),
                      let revision = Int(name.dropFirst(prefix.count).dropLast(".json".count)) else { return nil }
                return (revision, folder.appending(path: name))
            }
            .sorted { $0.revision > $1.revision }
    }

    private static func rotated(_ file: URL, kind: BackupKind, number: Int) -> URL {
        file.deletingLastPathComponent().appending(path: "\(file.deletingPathExtension().lastPathComponent).\(kind.rawValue)\(number).json")
    }

    private static func prune(_ file: URL, kind: BackupKind) {
        for old in backups(of: file, kind: kind).dropFirst(keptBackups) { try? FileManager.default.removeItem(at: old.url) }
    }

    private static func backUp(_ file: URL, revision: Int) {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let backup = rotated(file, kind: .revision, number: revision)
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: file, to: backup)
        prune(file, kind: .revision)
    }

    private static func jsonObject(_ value: some Encodable) -> Any? {
        (try? JSONEncoder().encode(value)).flatMap { try? JSONSerialization.jsonObject(with: $0) }
    }

    private static func decode<Value: Decodable>(_ raw: Any?) -> Value? {
        guard let raw, JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private struct Saved: Codable {
        let revision: Int
        let pages: [StandPage]
        let shortcuts: [StandShortcut]?
        let edges: String?
        let preferences: StandPreferences?
        let device: StandDeviceStatus?
    }
}
