import XCTest
@testable import StandBridge

@MainActor
final class CodexSettingsTests: XCTestCase {
    private static let foreign: JSON = ["hooks": ["PostToolUse": [[
        "matcher": "apply_patch",
        "hooks": [["type": "command", "command": "/usr/local/bin/lint hook", "statusMessage": "Linting"]],
    ]]]]

    private func groups(_ settings: JSON, _ event: String) -> [JSON] {
        (settings["hooks"] as? JSON)?[event] as? [JSON] ?? []
    }

    private func hook(_ group: JSON) -> JSON {
        (group["hooks"] as? [JSON])?.first ?? [:]
    }

    func testInstallKeepsForeignHooksAndUsesSafeTimeouts() {
        XCTAssertEqual(CodexSettings.hookState(Self.foreign), .missing)
        let installed = CodexSettings.installingHooks(Self.foreign)
        XCTAssertEqual(CodexSettings.hookState(installed), .installed)

        let postToolUse = groups(installed, "PostToolUse")
        XCTAssertEqual(postToolUse.count, 2)
        XCTAssertEqual(postToolUse[0] as NSDictionary, groups(Self.foreign, "PostToolUse")[0] as NSDictionary)
        XCTAssertEqual(hook(postToolUse[1])["async"] as? Bool, true)

        let permission = hook(groups(installed, "PermissionRequest")[0])
        XCTAssertEqual(permission["command"] as? String, CodexSettings.blockingCommand)
        XCTAssertGreaterThanOrEqual(permission["timeout"] as? Int ?? 0, 130)
        XCTAssertNil(permission["async"])

        for event in ["SessionEnd", "Interrupt"] {
            XCTAssertLessThanOrEqual(hook(groups(installed, event)[0])["timeout"] as? Int ?? 99, 3, event)
        }
        XCTAssertEqual(Set((installed["hooks"] as? JSON)?.keys.map { $0 } ?? []),
                       ["SessionStart", "UserPromptSubmit", "PermissionRequest", "PostToolUse", "Stop", "Interrupt", "SessionEnd"])
    }

    func testCommandsTagAgentAndPassParentPid() {
        for command in [CodexSettings.blockingCommand, CodexSettings.asyncCommand, CodexSettings.endCommand] {
            XCTAssertTrue(command.contains(#""http://127.0.0.1:7420/hook?agent=codex&pid=$PPID""#), command)
            XCTAssertTrue(command.contains(#"$(cat "$HOME/.config/duo-stand/token")"#))
        }
        XCTAssertTrue(CodexSettings.asyncCommand.contains(">/dev/null"))
    }

    func testRemoveLeavesOnlyForeignHooks() {
        let removed = ClaudeSettings.removingHooks(CodexSettings.installingHooks(Self.foreign))
        XCTAssertEqual(CodexSettings.hookState(removed), .missing)
        XCTAssertEqual(removed as NSDictionary, Self.foreign as NSDictionary)
    }

    func testChangedCommandIsOutdatedAndReinstallReplacesIt() {
        var settings = CodexSettings.installingHooks([:])
        var hooks = settings["hooks"] as! JSON
        hooks["Stop"] = [["hooks": [["type": "command", "command": "curl -s http://127.0.0.1:7420/hook?agent=codex"]]]]
        settings["hooks"] = hooks
        XCTAssertEqual(CodexSettings.hookState(settings), .outdated)
        let reinstalled = CodexSettings.installingHooks(settings)
        XCTAssertEqual(CodexSettings.hookState(reinstalled), .installed)
        XCTAssertEqual(groups(reinstalled, "Stop").count, 1)
    }

    func testInstallIntoFileBacksUpOriginal() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "hooks.json")
        try JSONSerialization.data(withJSONObject: Self.foreign).write(to: file)

        let backup = try XCTUnwrap(ClaudeSettings.update(file, CodexSettings.installingHooks))
        XCTAssertEqual(try ClaudeSettings.read(backup) as NSDictionary, Self.foreign as NSDictionary)
        XCTAssertEqual(CodexSettings.hookState(try ClaudeSettings.read(file)), .installed)

        let fresh = dir.appending(path: "fresh.json")
        XCTAssertNil(try ClaudeSettings.update(fresh, CodexSettings.installingHooks))
        XCTAssertEqual(CodexSettings.hookState(try ClaudeSettings.read(fresh)), .installed)
    }
}
