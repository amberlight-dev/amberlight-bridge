import XCTest
@testable import StandBridge

@MainActor
final class ClaudeSettingsTests: XCTestCase {
    private static let legacy = "/usr/bin/python3 /Users/x/duo-stand/bridge/stand_hook.py"
    private static let settings: JSON = [
        "model": "opus",
        "statusLine": ["type": "command", "command": "~/.claude/statusline-command.sh"],
        "hooks": [
            "PostToolUse": [
                ["matcher": "Write|Edit", "hooks": [["type": "command", "command": "silence hook"]]],
                ["matcher": "AskUserQuestion", "hooks": [["type": "command", "command": legacy, "async": true]]],
            ],
            "SessionStart": [["matcher": "startup", "hooks": [["type": "command", "command": "rules", "timeout": 30]]]],
            "PreToolUse": [["matcher": "AskUserQuestion", "hooks": [["type": "command", "command": legacy + " 140", "timeout": 150]]]],
            "Stop": [["hooks": [["type": "command", "command": legacy, "async": true]]]],
        ],
    ]

    func testInstallReplacesLegacyHooksAndKeepsTheRest() {
        XCTAssertEqual(ClaudeSettings.hookState(Self.settings), .legacy)
        let installed = ClaudeSettings.installingHooks(Self.settings)
        XCTAssertEqual(ClaudeSettings.hookState(installed), .installed)
        XCTAssertEqual(installed["model"] as? String, "opus")

        let hooks = installed["hooks"] as! JSON
        let postToolUse = hooks["PostToolUse"] as! [JSON]
        XCTAssertEqual(postToolUse.map { $0["matcher"] as? String }, ["Write|Edit", "AskUserQuestion|mcp__ccd_turn__wrap_up"])
        XCTAssertEqual(command(postToolUse[1]), ClaudeSettings.asyncCommand)
        XCTAssertEqual((hooks["SessionStart"] as! [JSON]).count, 1)
        let preToolUse = hooks["PreToolUse"] as! [JSON]
        XCTAssertEqual(preToolUse.count, 1)
        XCTAssertEqual(command(preToolUse[0]), ClaudeSettings.blockingCommand)
        XCTAssertEqual((hooks["PermissionRequest"] as! [JSON]).count, 1)
        XCTAssertNil((hooks["PermissionRequest"] as! [JSON])[0]["matcher"])
    }

    func testRemoveLeavesOnlyForeignHooks() {
        let removed = ClaudeSettings.removingHooks(ClaudeSettings.installingHooks(Self.settings))
        XCTAssertEqual(ClaudeSettings.hookState(removed), .missing)
        let hooks = removed["hooks"] as! JSON
        XCTAssertEqual(Set(hooks.keys), ["PostToolUse", "SessionStart"])
        XCTAssertEqual(command((hooks["PostToolUse"] as! [JSON])[0]), "silence hook")
    }

    func testUpdateWritesBackupAndRoundTrips() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "settings.json")
        try JSONSerialization.data(withJSONObject: Self.settings).write(to: file)

        let backup = try XCTUnwrap(ClaudeSettings.update(file, ClaudeSettings.installingHooks))
        XCTAssertEqual(ClaudeSettings.hookState(try ClaudeSettings.read(backup)), .legacy)
        XCTAssertEqual(ClaudeSettings.hookState(try ClaudeSettings.read(file)), .installed)
    }

    func testUpdateRefusesCorruptSettings() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        try Data("{ kaputt".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertThrowsError(try ClaudeSettings.update(file, ClaudeSettings.installingHooks))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "{ kaputt")
    }

    func testHooksWithoutStandHeaderAreOutdatedAndGetReplaced() {
        let old = "curl -s -m 140 -H 'Expect:' --data-binary @- \(ClaudeSettings.hookURL) || true"
        let settings: JSON = ["hooks": ["PermissionRequest": [["hooks": [["type": "command", "command": old, "timeout": 150]]]]]]
        XCTAssertEqual(ClaudeSettings.hookState(settings), .outdated)
        let installed = ClaudeSettings.installingHooks(settings)
        XCTAssertEqual(ClaudeSettings.hookState(installed), .installed)
        XCTAssertEqual(((installed["hooks"] as! JSON)["PermissionRequest"] as! [JSON]).count, 1)
    }

    func testStatuslineScriptGetsUsageLineAfterInput() throws {
        let script = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).sh")
        try "#!/bin/sh\ninput=$(cat)\necho hi\n".write(to: script, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: script) }
        let settings: JSON = ["statusLine": ["type": "command", "command": script.path]]
        guard case .insertable = ClaudeSettings.statuslineState(settings) else { return XCTFail("expected insertable") }
        try ClaudeSettings.insertUsageLine(into: script)
        let lines = try String(contentsOf: script, encoding: .utf8).components(separatedBy: "\n")
        XCTAssertEqual(lines[2], ClaudeSettings.usageLine)
        guard case .installed = ClaudeSettings.statuslineState(settings) else { return XCTFail("expected installed") }
    }

    private func command(_ group: JSON) -> String? {
        (group["hooks"] as? [JSON])?.first?["command"] as? String
    }
}
