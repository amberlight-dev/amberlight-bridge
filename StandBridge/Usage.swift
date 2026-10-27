import Foundation

enum Usage {
    static func providers(_ candidates: [JSON?], now: Date = .now) -> [JSON] {
        candidates.compactMap { $0 }.map { expiringWindows(of: $0, now: now) }
    }

    private static func expiringWindows(of provider: JSON, now: Date) -> JSON {
        var provider = provider
        provider["windows"] = (provider["windows"] as? [JSON] ?? []).map { window in
            guard let resetsAt = window["resetsAt"] as? Double, resetsAt > 0, resetsAt < now.timeIntervalSince1970 else { return window }
            return ["minutes": window["minutes"] ?? 0, "used": 0.0, "resetsAt": NSNull()]
        }
        return provider
    }
}
