import Foundation

enum CodexUsage {
    static let tailBytes: UInt64 = 256 * 1024
    static let candidateLimit = 5
    private static let marker = Data(#""token_count""#.utf8)
    private static var cache: (file: URL, modified: Date, provider: JSON?)?

    static func cachedProvider(in sessionsDir: URL) -> JSON? {
        let rollouts = newestRollouts(in: sessionsDir)
        guard let newest = rollouts.first else { return nil }
        if let cache, cache.file == newest.url, cache.modified == newest.modified { return cache.provider }
        let fresh = provider(in: rollouts)
        cache = (newest.url, newest.modified, fresh)
        return fresh
    }

    static func provider(in sessionsDir: URL) -> JSON? {
        provider(in: newestRollouts(in: sessionsDir))
    }

    private static func provider(in rollouts: [(url: URL, modified: Date)]) -> JSON? {
        rollouts.lazy.compactMap { provider(fromTailOf: $0.url, modified: $0.modified) }.first
    }

    static func provider(fromLines data: Data, modified: Date) -> JSON? {
        for line in data.split(separator: UInt8(ascii: "\n")).reversed() where line.firstRange(of: marker) != nil {
            guard let entry = try? JSONSerialization.jsonObject(with: line) as? JSON,
                  let provider = provider(from: entry, modified: modified) else { continue }
            return provider
        }
        return nil
    }

    private static func provider(fromTailOf file: URL, modified: Date) -> JSON? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > tailBytes ? size - tailBytes : 0)
        return (try? handle.readToEnd()).flatMap { provider(fromLines: $0, modified: modified) }
    }

    private static func provider(from entry: JSON, modified: Date) -> JSON? {
        guard entry["type"] as? String == "event_msg",
              let payload = entry["payload"] as? JSON, payload["type"] as? String == "token_count",
              let limits = payload["rate_limits"] as? JSON,
              limits["limit_id"] as? String ?? "codex" == "codex" else { return nil }
        let windows = ["primary", "secondary"].compactMap { (limits[$0] as? JSON).flatMap(window) }
        guard !windows.isEmpty else { return nil }
        return ["id": "codex", "name": "Codex", "windows": windows, "updatedAt": modified.timeIntervalSince1970]
    }

    private static func window(_ raw: JSON) -> JSON? {
        guard let minutes = raw["window_minutes"] as? Int, let used = raw["used_percent"] as? Double else { return nil }
        return ["minutes": minutes, "used": used / 100, "resetsAt": raw["resets_at"] as? Double ?? NSNull()]
    }

    private static func newestRollouts(in sessionsDir: URL) -> [(url: URL, modified: Date)] {
        var found: [URL] = []
        search: for year in children(of: sessionsDir) {
            for month in children(of: year) {
                for day in children(of: month) {
                    found += children(of: day).filter { $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl" }
                    if found.count >= candidateLimit { break search }
                }
            }
        }
        return found.prefix(candidateLimit)
            .map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
    }

    private static func children(of dir: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}
