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
        XCTAssertEqual(postToolUse.map { $0["matcher"] as? String }, ["Write|Edit", nil])
        XCTAssertEqual(command(postToolUse[1]), ClaudeSettings.asyncCommand)
        XCTAssertEqual((hooks["SessionStart"] as! [JSON]).count, 1)
        XCTAssertNil(hooks["PreToolUse"])
        let permission = hooks["PermissionRequest"] as! [JSON]
        XCTAssertEqual(permission.count, 1)
        XCTAssertNil(permission[0]["matcher"])
        XCTAssertEqual(command(permission[0]), ClaudeSettings.permissionCommand)
        XCTAssertEqual((permission[0]["hooks"] as? [JSON])?.first?["timeout"] as? Int, 3600)
        let stop = (hooks["Stop"] as! [JSON])
        XCTAssertEqual(stop.count, 1)
        let stopHook = (stop[0]["hooks"] as? [JSON])?.first
        XCTAssertEqual(stopHook?["command"] as? String, ClaudeSettings.awaitCommand)
        XCTAssertEqual(stopHook?["asyncRewake"] as? Bool, true)
        XCTAssertEqual(stopHook?["timeout"] as? Int, 28800)
        XCTAssertNotNil(stopHook?["rewakeSummary"] as? String)
    }

    func testPreviousInstallsAreOutdatedAndReinstallCleanly() {
        let blockingStop = "curl -s -m 140 -H 'Expect:' \(ClaudeSettings.hookHeader) --data-binary @- \(ClaudeSettings.hookURL) || true"
        var oldInstall = ClaudeSettings.installingHooks([:])
        var hooks = oldInstall["hooks"] as! JSON
        hooks["Stop"] = [["hooks": [["type": "command", "command": blockingStop, "timeout": 150]]]]
        oldInstall["hooks"] = hooks
        XCTAssertEqual(ClaudeSettings.hookState(oldInstall), .outdated)

        var withPreToolUse = ClaudeSettings.installingHooks([:])
        hooks = withPreToolUse["hooks"] as! JSON
        hooks["PreToolUse"] = [["matcher": "AskUserQuestion", "hooks": [["type": "command", "command": blockingStop, "timeout": 150]]]]
        withPreToolUse["hooks"] = hooks
        XCTAssertEqual(ClaudeSettings.hookState(withPreToolUse), .outdated)

        var asyncStop = ClaudeSettings.installingHooks([:])
        hooks = asyncStop["hooks"] as! JSON
        hooks["Stop"] = [["hooks": [["type": "command", "command": ClaudeSettings.awaitCommand, "timeout": 28800]]]]
        asyncStop["hooks"] = hooks
        XCTAssertEqual(ClaudeSettings.hookState(asyncStop), .outdated)

        var matchedPostToolUse = ClaudeSettings.installingHooks([:])
        hooks = matchedPostToolUse["hooks"] as! JSON
        hooks["PostToolUse"] = [["matcher": "AskUserQuestion|mcp__ccd_turn__wrap_up", "hooks": [["type": "command", "command": ClaudeSettings.asyncCommand, "async": true]]]]
        matchedPostToolUse["hooks"] = hooks
        XCTAssertEqual(ClaudeSettings.hookState(matchedPostToolUse), .outdated)

        for old in [oldInstall, withPreToolUse, asyncStop, matchedPostToolUse] {
            let reinstalled = ClaudeSettings.installingHooks(old)
            XCTAssertEqual(ClaudeSettings.hookState(reinstalled), .installed)
            XCTAssertNil((reinstalled["hooks"] as! JSON)["PreToolUse"])
        }
    }

    func testAwaitCommandWakesOnlyWithText() throws {
        func run(_ reply: String) throws -> (Int32, String) {
            let command = ClaudeSettings.awaitCommand.replacingOccurrences(of: "curl -sf -m 28790 -H 'Expect:' \(ClaudeSettings.hookHeader) --data-binary @- \(ClaudeSettings.awaitURL)", with: "printf '%s' '\(reply)'")
            guard !command.contains("curl") else {
                XCTFail("await command changed")
                return (-1, "")
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            let stderr = Pipe()
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }
        let woken = try run("Ja")
        let quiet = try run("")
        XCTAssertEqual(woken.0, 2)
        XCTAssertEqual(woken.1, "Ja\n")
        XCTAssertEqual(quiet.0, 0)
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
