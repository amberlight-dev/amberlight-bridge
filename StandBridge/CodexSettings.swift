import Foundation

enum CodexSettings {
    enum HookState { case missing, outdated, installed }

    static let codexDir = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex")
    static let hooksFile = codexDir.appending(path: "hooks.json")
    static let sessionsDir = codexDir.appending(path: "sessions")

    static let agentMarker = "agent=codex"
    private static let hookURL = #""\#(ClaudeSettings.hookURL)?\#(agentMarker)&pid=$PPID""#
    static let blockingCommand = "curl -s -m 140 -H 'Expect:' \(ClaudeSettings.hookHeader) --data-binary @- \(hookURL) || true"
    static let asyncCommand = "curl -s -m 5 -H 'Expect:' \(ClaudeSettings.hookHeader) --data-binary @- \(hookURL) >/dev/null || true"
    static let endCommand = "curl -s -m 2 -H 'Expect:' \(ClaudeSettings.hookHeader) --data-binary @- \(hookURL) >/dev/null || true"

    private static let asyncHook: JSON = ["type": "command", "command": asyncCommand, "async": true]
    private static let shortHook: JSON = ["type": "command", "command": endCommand, "timeout": 3]
    private static let entries: [(event: String, hook: JSON)] = [
        ("SessionStart", asyncHook),
        ("UserPromptSubmit", asyncHook),
        ("PermissionRequest", ["type": "command", "command": blockingCommand, "timeout": 150]),
        ("PostToolUse", asyncHook),
        ("Stop", asyncHook),
        ("Interrupt", shortHook),
        ("SessionEnd", shortHook),
    ]

    static func hookState(_ settings: JSON) -> HookState {
        let ours = ourHooks(settings)
        if ours.isEmpty { return .missing }
        return ours == Set(entries.map { "\($0.event) \($0.hook["command"] ?? "")" }) ? .installed : .outdated
    }

    static func installingHooks(_ settings: JSON) -> JSON {
        var result = ClaudeSettings.removingHooks(settings)
        var hooks = result["hooks"] as? JSON ?? [:]
        for entry in entries {
            hooks[entry.event] = (hooks[entry.event] as? [JSON] ?? []) + [["hooks": [entry.hook]]]
        }
        result["hooks"] = hooks
        return result
    }

    private static func ourHooks(_ settings: JSON) -> Set<String> {
        Set((settings["hooks"] as? JSON ?? [:]).flatMap { event, groups in
            (groups as? [JSON] ?? [])
                .flatMap { $0["hooks"] as? [JSON] ?? [] }
                .compactMap { $0["command"] as? String }
                .filter { $0.contains(agentMarker) }
                .map { "\(event) \($0)" }
        })
    }
}
