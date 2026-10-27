import XCTest
@testable import StandBridge

@MainActor
final class CodexBoardTests: XCTestCase {
    private var dir: URL!
    private var board: Board!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        board = Board(claudeDir: dir, standWaitSeconds: 2, doneDelay: 0.2)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func hook(_ event: String, session: String = "c1", pid: Int32? = getpid(), _ extra: JSON = [:]) -> JSON {
        var payload: JSON = ["hook_event_name": event, "session_id": session, "cwd": "/x/shop", "agent": "codex"]
        if let pid { payload["pid"] = pid }
        return payload.merging(extra) { $1 }
    }

    private func sessions() -> [JSON] {
        board.snapshot(standAnswers: false)["sessions"] as? [JSON] ?? []
    }

    func testSessionLifecycleFromEvents() async {
        _ = await board.handleHook(hook("SessionStart", ["source": "startup"]))
        XCTAssertEqual(sessions().first?["state"] as? String, "idle")
        XCTAssertEqual(sessions().first?["agent"] as? String, "codex")
        XCTAssertEqual(sessions().first?["title"] as? String, "shop")
        XCTAssertEqual(sessions().first?["repo"] as? String, "shop")

        _ = await board.handleHook(hook("UserPromptSubmit", ["prompt": "Tests fixen"]))
        XCTAssertEqual(sessions().first?["state"] as? String, "working")

        _ = await board.handleHook(hook("Stop", ["last_assistant_message": "Alle Tests grün.", "stop_hook_active": false]))
        XCTAssertEqual(sessions().first?["state"] as? String, "idle")
        try? await Task.sleep(for: .milliseconds(500))
        let done = (board.snapshot(standAnswers: false)["events"] as? [JSON])?.last
        XCTAssertEqual(done?["kind"] as? String, "done")
        XCTAssertEqual(done?["text"] as? String, "Alle Tests grün.")

        _ = await board.handleHook(hook("SessionEnd", ["reason": "other"]))
        XCTAssertTrue(sessions().isEmpty)
    }

    func testInterruptEndsTurnWithoutDone() async throws {
        _ = await board.handleHook(hook("UserPromptSubmit"))
        _ = await board.handleHook(hook("Interrupt"))
        XCTAssertEqual(sessions().first?["state"] as? String, "idle")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual((board.snapshot(standAnswers: false)["events"] as? [JSON])?.count, 0)
    }

    func testPromptWithoutSessionStartRegistersSession() async {
        _ = await board.handleHook(hook("UserPromptSubmit"))
        XCTAssertEqual(board.session("c1")?["pid"] as? Int32, getpid())
        XCTAssertEqual(sessions().count, 1)
    }

    func testDeadProcessDropsSession() async {
        _ = await board.handleHook(hook("SessionStart", pid: Int32.max - 1))
        XCTAssertTrue(sessions().isEmpty)
        XCTAssertNil(board.session("c1"))
    }

    func testSessionWithoutPidStaysUntilSessionEnd() async {
        _ = await board.handleHook(hook("SessionStart", pid: nil))
        XCTAssertEqual(sessions().count, 1)
        _ = await board.handleHook(hook("SessionEnd", pid: nil))
        XCTAssertTrue(sessions().isEmpty)
    }

    func testClaudeHooksDoNotCreateSessions() async {
        _ = await board.handleHook(["hook_event_name": "UserPromptSubmit", "session_id": "x", "agent": "claude", "pid": getpid()])
        XCTAssertTrue(sessions().isEmpty)
    }

    func testPermissionAllowedFromStand() async throws {
        _ = board.snapshot(standAnswers: true)
        let request = hook("PermissionRequest", ["tool_name": "Bash", "turn_id": "t1",
                                                 "tool_input": ["command": "npm test", "description": NSNull()]])
        let result = HookResult()
        Task { result.value = await board.handleHook(request) }
        let pending = try await waitForQuestion()
        XCTAssertEqual(pending["kind"] as? String, "permission")
        XCTAssertEqual(pending["detail"] as? String, "npm test")
        XCTAssertTrue(board.answer(["questionId": pending["id"]!, "decision": "allow"]))
        let output = try await value(of: result)
        XCTAssertEqual(output as NSDictionary, ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": ["behavior": "allow"]]])
    }

    func testPermissionAtMacClearsAfterToolRan() async {
        let request = hook("PermissionRequest", ["tool_name": "apply_patch", "tool_input": ["command": "*** Begin Patch"]])
        let result = await board.handleHook(request)
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(sessions().first?["state"] as? String, "waitingForYou")
        _ = await board.handleHook(hook("PostToolUse", ["tool_name": "apply_patch"]))
        XCTAssertEqual(sessions().first?["state"] as? String, "working")
    }

    private final class HookResult {
        var value: JSON?
    }

    private func value(of result: HookResult) async throws -> JSON {
        for _ in 0..<150 {
            if let value = result.value { return value }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("hook never returned")
        return [:]
    }

    private func waitForQuestion() async throws -> JSON {
        for _ in 0..<50 {
            let question = (board.snapshot(standAnswers: true)["sessions"] as? [JSON])?.first?["question"] as? JSON
            if let question, question["atMac"] as? Bool == false { return question }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("question never appeared")
        return [:]
    }
}
