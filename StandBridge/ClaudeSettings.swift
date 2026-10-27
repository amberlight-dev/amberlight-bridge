import Foundation

enum ClaudeSettings {
    enum HookState { case missing, legacy, outdated, installed }
    enum StatuslineState { case missing, installed, insertable(URL), manual }

    static let hookURL = "http://127.0.0.1:7420/hook"
    static let hookHeaderName = "x-stand-hook"
    static let hookHeader = #"-H "x-stand-hook: $(cat "$HOME/.config/duo-stand/token")""#
    static let blockingCommand = "curl -s -m 140 -H 'Expect:' \(hookHeader) --data-binary @- \(hookURL) || true"
    static let asyncCommand = "curl -s -m 5 -H 'Expect:' \(hookHeader) --data-binary @- \(hookURL) >/dev/null || true"
    static let usageLine = #"printf '%s' "$input" > "$HOME/.claude/stand-usage.json.$$" && mv "$HOME/.claude/stand-usage.json.$$" "$HOME/.claude/stand-usage.json""#

    private static let entries: [(event: String, matcher: String?, blocking: Bool)] = [
        ("PreToolUse", "AskUserQuestion", true),
        ("PermissionRequest", nil, true),
        ("PostToolUse", "AskUserQuestion|\(Board.nextStepTool)", false),
        ("UserPromptSubmit", nil, false),
        ("Stop", nil, false),
        ("Notification", nil, false),
    ]

    static func hookState(_ settings: JSON) -> HookState {
        let commands = allCommands(settings)
        if commands.contains(where: { $0.contains("stand_hook.py") }) { return .legacy }
        let ours = commands.filter { $0.contains(hookURL) }
        if ours.isEmpty { return .missing }
        return ours.allSatisfy { $0.contains(hookHeader) } ? .installed : .outdated
    }

    static func installingHooks(_ settings: JSON) -> JSON {
        var result = removingHooks(settings)
        var hooks = result["hooks"] as? JSON ?? [:]
        for entry in entries {
            var hook: JSON = ["type": "command", "command": entry.blocking ? blockingCommand : asyncCommand]
            if entry.blocking { hook["timeout"] = 150 } else { hook["async"] = true }
            var group: JSON = ["hooks": [hook]]
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
    static func update(_ file: URL, _ transform: (JSON) -> JSON) throws -> URL? {
        let settings = try read(file)
        let backup = FileManager.default.fileExists(atPath: file.path) ? try backUp(file) : nil
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

    private static func allCommands(_ settings: JSON) -> [String] {
        (settings["hooks"] as? JSON ?? [:]).values
            .compactMap { $0 as? [JSON] }
            .flatMap { $0 }
            .flatMap { $0["hooks"] as? [JSON] ?? [] }
            .compactMap { $0["command"] as? String }
    }
}
