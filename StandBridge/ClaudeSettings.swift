import Foundation

enum ClaudeSettings {
    enum HookState { case missing, legacy, outdated, installed }
    enum StatuslineState { case missing, installed, insertable(URL), manual }

    static let hookURL = "http://127.0.0.1:7420/hook"
    static let awaitURL = "\(hookURL)/await"
    static let hookHeaderName = "x-stand-hook"
    static let hookHeader = #"-H "x-stand-hook: $(cat "$HOME/.config/duo-stand/token")""#
    static let permissionCommand = "curl -s -m 3590 -H 'Expect:' \(hookHeader) --data-binary @- \(hookURL) || true"
    static let asyncCommand = "curl -s -m 5 -H 'Expect:' \(hookHeader) --data-binary @- \(hookURL) >/dev/null || true"
    static let awaitCommand = #"r=$(curl -sf -m 28790 -H 'Expect:' \#(hookHeader) --data-binary @- \#(awaitURL)) || exit 0; [ -n "$r" ] || exit 0; printf '%s\n' "$r" >&2; exit 2"#
    static let usageLine = #"printf '%s' "$input" > "$HOME/.claude/stand-usage.json.$$" && mv "$HOME/.claude/stand-usage.json.$$" "$HOME/.claude/stand-usage.json""#

    private static let asyncHook: JSON = ["type": "command", "command": asyncCommand, "async": true]
    private static var entries: [(event: String, matcher: String?, hook: JSON)] { [
        ("PermissionRequest", nil, ["type": "command", "command": permissionCommand, "timeout": 3600]),
        ("PostToolUse", nil, asyncHook),
        ("UserPromptSubmit", nil, asyncHook),
        ("Stop", nil, ["type": "command", "command": awaitCommand, "asyncRewake": true, "timeout": 28800,
                       "rewakeSummary": String(localized: "Antwort von Amberlight")]),
        ("Notification", nil, asyncHook),
    ] }

    static func hookState(_ settings: JSON) -> HookState {
        if allCommands(settings).contains(where: { $0.contains("stand_hook.py") }) { return .legacy }
        let ours = ourSignatures(settings)
        if ours.isEmpty { return .missing }
        return ours.sorted() == entries.map { signature($0.event, $0.matcher, $0.hook) }.sorted() ? .installed : .outdated
    }

    static func installingHooks(_ settings: JSON) -> JSON {
        var result = removingHooks(settings)
        var hooks = result["hooks"] as? JSON ?? [:]
        for entry in entries {
            var group: JSON = ["hooks": [entry.hook]]
            if let matcher = entry.matcher { group["matcher"] = matcher }
            hooks[entry.event] = (hooks[entry.event] as? [JSON] ?? []) + [group]
        }
        result["hooks"] = hooks
        return result
    }

    static func removingHooks(_ settings: JSON) -> JSON {
        guard let hooks = settings["hooks"] as? JSON else { return settings }
        var result = settings
        result["hooks"] = hooks.compactMapValues { value -> Any? in
            guard let groups = value as? [JSON] else { return value }
            let kept = groups.compactMap { group -> JSON? in
                let commands = (group["hooks"] as? [JSON] ?? []).filter { !isOurs($0["command"] as? String ?? "") }
                return commands.isEmpty ? nil : group.merging(["hooks": commands]) { $1 }
            }
            return kept.isEmpty ? nil : kept
        }
        return result
    }

    static func statuslineState(_ settings: JSON) -> StatuslineState {
        guard let command = (settings["statusLine"] as? JSON)?["command"] as? String else { return .missing }
        if command.contains("stand-usage.json") { return .installed }
        let path = String(command.split(separator: " ").first ?? "")
        let script = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard let text = try? String(contentsOf: script, encoding: .utf8) else { return .manual }
        if text.contains("stand-usage.json") { return .installed }
        return text.components(separatedBy: "\n").contains { $0.hasPrefix("input=$(cat)") } ? .insertable(script) : .manual
    }

    static func installingStatusline(_ settings: JSON) -> JSON {
        settings.merging(["statusLine": ["type": "command", "command": "input=$(cat); \(usageLine)"]]) { $1 }
    }

    static func insertUsageLine(into script: URL) throws {
        var lines = try String(contentsOf: script, encoding: .utf8).components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { $0.hasPrefix("input=$(cat)") }) else { return }
        try backUp(script)
        lines.insert(usageLine, at: index + 1)
        try lines.joined(separator: "\n").write(to: script, atomically: true, encoding: .utf8)
    }

    static func read(_ file: URL) throws -> JSON {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        guard let settings = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? JSON else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return settings
    }

    @discardableResult
    static func update(_ file: URL, backup makeBackup: Bool = true, _ transform: (JSON) -> JSON) throws -> URL? {
        let settings = try read(file)
        let backup = makeBackup && FileManager.default.fileExists(atPath: file.path) ? try backUp(file) : nil
        let data = try JSONSerialization.data(withJSONObject: transform(settings), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: file, options: .atomic)
        return backup
    }

    @discardableResult
    private static func backUp(_ file: URL) throws -> URL {
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted).dateSeparator(.omitted))
        let backup = file.appendingPathExtension("duostand-backup-\(stamp)")
        try FileManager.default.copyItem(at: file, to: backup)
        return backup
    }

    private static func isOurs(_ command: String) -> Bool {
        command.contains("stand_hook.py") || command.contains(hookURL)
    }

    private static func signature(_ event: String, _ matcher: String?, _ hook: JSON) -> String {
        let flags = [hook["async"] as? Bool ?? false, hook["asyncRewake"] as? Bool ?? false]
        return "\(event)|\(matcher ?? "")|\(hook["command"] as? String ?? "")|\(flags)|\(hook["timeout"] as? Int ?? 0)|\(hook["rewakeSummary"] as? String ?? "")"
    }

    private static func ourSignatures(_ settings: JSON) -> [String] {
        (settings["hooks"] as? JSON ?? [:]).flatMap { event, groups in
            (groups as? [JSON] ?? []).flatMap { group in
                (group["hooks"] as? [JSON] ?? [])
                    .filter { isOurs($0["command"] as? String ?? "") }
                    .map { signature(event, group["matcher"] as? String, $0) }
            }
        }
    }

    private static func allCommands(_ settings: JSON) -> [String] {
        (settings["hooks"] as? JSON ?? [:]).values
            .compactMap { $0 as? [JSON] }
            .flatMap { $0 }
            .flatMap { $0["hooks"] as? [JSON] ?? [] }
            .compactMap { $0["command"] as? String }
    }
}
