import XCTest
@testable import StandBridge

@MainActor
final class BoardTests: XCTestCase {
    private static let questionHook: JSON = [
        "hook_event_name": "PreToolUse",
        "tool_name": "AskUserQuestion",
        "session_id": "s1",
        "tool_input": ["questions": [["question": "Welches Framework?", "header": "Stack",
                                      "options": [["label": "React"], ["label": "Vue"]]]]],
    ]

    private var dir: URL!
    private var board: Board!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appending(path: "sessions"), withIntermediateDirectories: true)
        try write(["pid": Int(getpid()), "sessionId": "s1", "cwd": "/x/orbit", "name": "Fix", "status": "busy", "statusUpdatedAt": 1000], to: "sessions/1.json")
        try write(["five_hour": ["used_percentage": 42, "resets_at": 99], "seven_day": ["used_percentage": 18]], to: "stand-usage.json")
        board = Board(claudeDir: dir, standWaitSeconds: 2)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testSnapshotMapsRegistry() {
        let session = sessions(board.snapshot(standAnswers: false))[0]
        XCTAssertEqual(session["state"] as? String, "working")
        XCTAssertEqual(session["repo"] as? String, "orbit")
    }

    func testStatuslineUsageBecomesClaudeProvider() {
        let usage = board.statuslineUsage()
        let windows = usage?["windows"] as? [JSON]
        XCTAssertEqual(usage?["id"] as? String, "claude")
        XCTAssertEqual(windows?.map { $0["minutes"] as? Int }, [300, 10080])
        XCTAssertEqual(windows?.map { $0["used"] as? Double }, [0.42, 0.18])
        XCTAssertEqual(windows?.first?["resetsAt"] as? Double, 99)
    }

    func testUsageReadsRawStatuslineInput() throws {
        try write(["rate_limits": ["five_hour": ["used_percentage": 10, "resets_at": 5]]], to: "stand-usage.json")
        let windows = board.statuslineUsage()?["windows"] as? [JSON]
        XCTAssertEqual(windows?.map { $0["used"] as? Double }, [0.1])
    }

    func testQuestionGoesToMacWhenStandOffline() async {
        let result = await board.handleHook(Self.questionHook)
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(question()?["atMac"] as? Bool, true)
        _ = await board.handleHook(["hook_event_name": "PostToolUse", "session_id": "s1"])
        XCTAssertNil(question())
    }

    func testStandAnswersQuestion() async throws {
        _ = board.snapshot(standAnswers: true)
        let hook = startHook(Self.questionHook)
        let pending = try await waitForQuestion()
        XCTAssertTrue(board.answer(["questionId": pending["id"]!, "answers": ["Welches Framework?": "Vue"]]))
        let output = try await value(of: hook)["hookSpecificOutput"] as? JSON
        XCTAssertEqual(output?["permissionDecision"] as? String, "allow")
        XCTAssertEqual((output?["updatedInput"] as? JSON)?["answers"] as? [String: String], ["Welches Framework?": "Vue"])
    }

    func testPermissionDenyAndRelease() async throws {
        _ = board.snapshot(standAnswers: true)
        let permission: JSON = ["hook_event_name": "PermissionRequest", "session_id": "s1", "tool_name": "Bash",
                                "tool_input": ["command": "rm -rf build"]]
        let denied = startHook(permission)
        let pending = try await waitForQuestion()
        XCTAssertEqual(pending["detail"] as? String, "rm -rf build")
        board.answer(["questionId": pending["id"]!, "decision": "deny"])
        let decision = (try await value(of: denied)["hookSpecificOutput"] as? JSON)?["decision"] as? JSON
        XCTAssertEqual(decision?["behavior"] as? String, "deny")

        let released = startHook(permission)
        board.answer(["questionId": try await waitForQuestion()["id"]!, "release": true])
        let releasedResult = try await value(of: released)
        XCTAssertTrue(releasedResult.isEmpty)
        XCTAssertEqual(question(standAnswers: true)?["atMac"] as? Bool, true)
    }

    func testEndedSessionsLeaveNoWaitingNoteBehind() async throws {
        _ = await board.handleHook(["hook_event_name": "PostToolUse", "session_id": "s1", "tool_name": Board.nextStepTool,
                                    "tool_input": ["ask": "Committen?", "actions": [["label": "Ja"]]]])
        XCTAssertTrue(sessions(board.snapshot(standAnswers: false))[0]["waiting"] is JSON)
        let file = dir.appending(path: "sessions/1.json")
        let entry = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        XCTAssertTrue(sessions(board.snapshot(standAnswers: false)).isEmpty)
        try entry.write(to: file)
        XCTAssertTrue(sessions(board.snapshot(standAnswers: false))[0]["waiting"] is NSNull)
    }

    func testNewQuestionSupersedesOpenOneOfSameSession() async throws {
        _ = board.snapshot(standAnswers: true)
        let first = startHook(Self.questionHook)
        let firstId = try await waitForQuestion()["id"] as? String
        let second = startHook(["hook_event_name": "PermissionRequest", "session_id": "s1", "tool_name": "Bash",
                                "tool_input": ["command": "ls"]])
        let firstResult = try await value(of: first)
        XCTAssertTrue(firstResult.isEmpty)
        let pending = try await waitForQuestion()
        XCTAssertNotEqual(pending["id"] as? String, firstId)
        XCTAssertEqual(pending["kind"] as? String, "permission")
        XCTAssertFalse(board.answer(["questionId": firstId ?? "", "decision": "allow"]))
        board.answer(["questionId": pending["id"]!, "decision": "deny"])
        _ = try await value(of: second)
    }

    func testQuestionTimesOutToMac() async throws {
        board = Board(claudeDir: dir, standWaitSeconds: 0.2)
        _ = board.snapshot(standAnswers: true)
        let result = await board.handleHook(Self.questionHook)
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(question(standAnswers: true)?["atMac"] as? Bool, true)
    }

    func testQuestionPermissionPromptIsNotASecondQuestion() async {
        _ = board.snapshot(standAnswers: true)
        let prompt: JSON = ["hook_event_name": "PermissionRequest", "session_id": "s1", "tool_name": "AskUserQuestion",
                            "tool_input": Self.questionHook["tool_input"]!]
        let result = await board.handleHook(prompt)
        XCTAssertTrue(result.isEmpty)
        XCTAssertNil(question(standAnswers: true))
    }

    private func lastEvent(_ board: Board) -> JSON? {
        (board.snapshot(standAnswers: false)["events"] as? [JSON])?.last
    }

    private func idleBoard() throws -> Board {
        try write(["pid": Int(getpid()), "sessionId": "s1", "cwd": "/x/orbit", "name": "Fix", "status": "idle"], to: "sessions/1.json")
        return Board(claudeDir: dir, doneDelay: 0.2)
    }

    func testStopEmitsDoneAfterQuietPeriod() async throws {
        let board = try idleBoard()
        _ = await board.handleHook(["hook_event_name": "Stop", "session_id": "s1", "last_assistant_message": "Alles grün.\nDetails"])
        XCTAssertNil(lastEvent(board))
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(lastEvent(board)?["kind"] as? String, "done")
        XCTAssertEqual(lastEvent(board)?["text"] as? String, "Alles grün.\nDetails")
    }

    func testActivityAfterStopCancelsDone() async throws {
        let board = try idleBoard()
        _ = await board.handleHook(["hook_event_name": "Stop", "session_id": "s1", "last_assistant_message": "Zwischenstand"])
        _ = await board.handleHook(["hook_event_name": "UserPromptSubmit", "session_id": "s1"])
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertNil(lastEvent(board))
    }

    func testBusySessionGetsNoDone() async throws {
        let board = Board(claudeDir: dir, doneDelay: 0.2)
        _ = await board.handleHook(["hook_event_name": "Stop", "session_id": "s1", "last_assistant_message": "Zwischenstand"])
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertNil(lastEvent(board))
    }

    func testOtherSessionsActivityKeepsDone() async throws {
        let board = try idleBoard()
        _ = await board.handleHook(["hook_event_name": "Stop", "session_id": "s1", "last_assistant_message": "Fertig"])
        _ = await board.handleHook(["hook_event_name": "UserPromptSubmit", "session_id": "s2"])
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(lastEvent(board)?["kind"] as? String, "done")
    }

    func testTextQuestionWaitsUntilNextPrompt() async {
        _ = await board.handleHook(["hook_event_name": "Stop", "session_id": "s1",
                                    "last_assistant_message": "Build ist grün.\n\n**Soll ich committen?**"])
        let session = sessions(board.snapshot(standAnswers: false))[0]
        XCTAssertEqual(session["state"] as? String, "waitingForYou")
        XCTAssertEqual(session["waiting"] as? NSDictionary, ["text": "Soll ich committen?", "options": [String]()])
        XCTAssertEqual((board.snapshot(standAnswers: false)["events"] as? [JSON])?.last?["kind"] as? String, "waiting")
        _ = await board.handleHook(["hook_event_name": "UserPromptSubmit", "session_id": "s1"])
        XCTAssertTrue(sessions(board.snapshot(standAnswers: false))[0]["waiting"] is NSNull)
    }

    func testNextStepBoxBecomesWaitingNote() async {
        _ = await board.handleHook(["hook_event_name": "PostToolUse", "session_id": "s1", "tool_name": "mcp__ccd_turn__wrap_up",
                                    "tool_input": ["recap": "x", "ask": "Jetzt committen?",
                                                   "actions": [["label": "Ja"], ["action": "commit"]]]])
        _ = await board.handleHook(["hook_event_name": "Stop", "session_id": "s1", "last_assistant_message": ""])
        let session = sessions(board.snapshot(standAnswers: false))[0]
        let waiting = session["waiting"] as? JSON
        XCTAssertEqual(waiting?["text"] as? String, "Jetzt committen?")
        XCTAssertEqual(waiting?["options"] as? [String], ["Ja"])
        XCTAssertEqual(waiting?["replies"] as? [String], ["Ja"])
        XCTAssertNotNil(waiting?["id"] as? String)
        XCTAssertEqual((board.snapshot(standAnswers: false)["events"] as? [JSON])?.last?["kind"] as? String, "waiting")
    }

    func testNextStepKeepsReplyMessagesAndOnlyOffersThose() async {
        _ = await board.handleHook(["hook_event_name": "PostToolUse", "session_id": "s1", "tool_name": "mcp__ccd_turn__wrap_up",
                                    "tool_input": ["recap": "x", "ask": "Welcher Fix zuerst?",
                                                   "actions": [["label": "Fix 1", "message": "Bitte zuerst Fix 1"],
                                                               ["label": "Fix 2", "message": ""]]]])
        let waiting = sessions(board.snapshot(standAnswers: false))[0]["waiting"] as? JSON
        let id = waiting?["id"] as? String ?? ""
        XCTAssertEqual(waiting?["options"] as? [String], ["Fix 1", "Fix 2"])
        XCTAssertEqual(waiting?["replies"] as? [String], ["Bitte zuerst Fix 1", "Fix 2"])
        XCTAssertNil(board.redeemReply(of: "s1", noteId: id, option: 2))
        XCTAssertNil(board.redeemReply(of: "other", noteId: id, option: 0))
        XCTAssertNil(board.redeemReply(of: "s1", noteId: "stale", option: 0))
        XCTAssertEqual(board.redeemReply(of: "s1", noteId: id, option: 0), "Bitte zuerst Fix 1")
        XCTAssertNil(board.redeemReply(of: "s1", noteId: id, option: 0))
        XCTAssertTrue(sessions(board.snapshot(standAnswers: false))[0]["waiting"] is NSNull)
    }

    func testReplyIsGoneAfterPromptOrExpiry() async {
        let nextStep: JSON = ["hook_event_name": "PostToolUse", "session_id": "s1", "tool_name": "mcp__ccd_turn__wrap_up",
                              "tool_input": ["ask": "Committen?", "actions": [["label": "Ja"]]]]
        _ = await board.handleHook(nextStep)
        let id = (sessions(board.snapshot(standAnswers: false))[0]["waiting"] as? JSON)?["id"] as? String ?? ""
        _ = await board.handleHook(["hook_event_name": "UserPromptSubmit", "session_id": "s1"])
        XCTAssertNil(board.redeemReply(of: "s1", noteId: id, option: 0))

        let expiring = Board(claudeDir: dir, replyLifetime: 0)
        _ = await expiring.handleHook(nextStep)
        let waiting = sessions(expiring.snapshot(standAnswers: false))[0]["waiting"] as? JSON
        XCTAssertEqual(waiting?["options"] as? [String], [])
        XCTAssertNil(expiring.redeemReply(of: "s1", noteId: waiting?["id"] as? String ?? "", option: 0))
    }

    private final class HookResult {
        var value: JSON?
    }

    private func startHook(_ payload: JSON) -> HookResult {
        let result = HookResult()
        Task { result.value = await board.handleHook(payload) }
        return result
    }

    private func value(of result: HookResult) async throws -> JSON {
        for _ in 0..<150 {
            if let value = result.value { return value }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("hook never returned")
        return [:]
    }

    private func sessions(_ snapshot: JSON) -> [JSON] {
        snapshot["sessions"] as? [JSON] ?? []
    }

    private func question(standAnswers: Bool = false) -> JSON? {
        sessions(board.snapshot(standAnswers: standAnswers)).first?["question"] as? JSON
    }

    private func waitForQuestion() async throws -> JSON {
        for _ in 0..<50 {
            if let pending = question(standAnswers: true), pending["atMac"] as? Bool == false { return pending }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("question never appeared")
        return [:]
    }

    private func write(_ json: JSON, to path: String) throws {
        try JSONSerialization.data(withJSONObject: json).write(to: dir.appending(path: path))
    }
}
