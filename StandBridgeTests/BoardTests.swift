import XCTest
@testable import StandBridge

@MainActor
final class BoardTests: XCTestCase {
    private static let questionHook: JSON = [
        "hook_event_name": "PermissionRequest",
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
        try write(["pid": Int(getpid()), "sessionId": "s1", "cwd": "/x/app", "name": "Fix", "status": "busy", "statusUpdatedAt": 1000], to: "sessions/1.json")
        try write(["five_hour": ["used_percentage": 42, "resets_at": 99], "seven_day": ["used_percentage": 18]], to: "stand-usage.json")
        board = Board(claudeDir: dir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testSnapshotMapsRegistry() {
        let session = sessions(board.snapshot(standAnswers: false))[0]
        XCTAssertEqual(session["state"] as? String, "working")
        XCTAssertEqual(session["repo"] as? String, "app")
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

    func testStandAnswersQuestionWithUpdatedInput() async throws {
        let hook = startHook(Self.questionHook)
        let pending = try await waitForQuestion()
        XCTAssertEqual(pending["kind"] as? String, "question")
        XCTAssertEqual(pending["atMac"] as? Bool, false)
        XCTAssertNotNil(pending["expiresAt"] as? Double)
        XCTAssertFalse(board.answer(["questionId": pending["id"]!, "answers": ["Welches Framework?": "  "]]))
        XCTAssertTrue(board.answer(["questionId": pending["id"]!, "answers": ["Welches Framework?": "Svelte, weil klein"]]))
        let output = try await value(of: hook)["hookSpecificOutput"] as? JSON
        let decision = output?["decision"] as? JSON
        let updatedInput = decision?["updatedInput"] as? JSON
        XCTAssertEqual(output?["hookEventName"] as? String, "PermissionRequest")
        XCTAssertEqual(decision?["behavior"] as? String, "allow")
        XCTAssertEqual(updatedInput?["answers"] as? [String: String], ["Welches Framework?": "Svelte, weil klein"])
        XCTAssertEqual((updatedInput?["questions"] as? [JSON])?.count, 1)
        XCTAssertNil(question())
        XCTAssertFalse(board.answer(["questionId": pending["id"]!, "answers": ["Welches Framework?": "Vue"]]))
    }

    func testPermissionAllowAndDeny() async throws {
        let permission: JSON = ["hook_event_name": "PermissionRequest", "session_id": "s1", "tool_name": "Bash",
                                "tool_input": ["command": "rm -rf build"]]
        let denied = startHook(permission)
        let pending = try await waitForQuestion()
        XCTAssertEqual(pending["kind"] as? String, "permission")
        XCTAssertEqual(pending["detail"] as? String, "rm -rf build")
        XCTAssertTrue(board.answer(["questionId": pending["id"]!, "decision": "deny"]))
        let denial = (try await value(of: denied)["hookSpecificOutput"] as? JSON)?["decision"] as? JSON
        XCTAssertEqual(denial?["behavior"] as? String, "deny")

        let allowed = startHook(permission)
        let allowId = try await waitForQuestion()["id"]!
        XCTAssertTrue(board.answer(["questionId": allowId, "decision": "allow"]))
        let output = try await value(of: allowed)
        XCTAssertEqual(output as NSDictionary, ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": ["behavior": "allow"]]])
    }

    func testAskWaitsRegardlessOfStandPresence() async throws {
        let hook = startHook(Self.questionHook)
        _ = try await waitForQuestion()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(hook.value)
        var answered = Self.questionHook["tool_input"] as? JSON ?? [:]
        answered["answers"] = ["Welches Framework?": "Vue"]
        _ = await board.handleHook(["hook_event_name": "PostToolUse", "session_id": "s1", "tool_name": "AskUserQuestion", "tool_input": answered])
        _ = try await value(of: hook)
    }

    func testLaterHookEventSupersedesAsk() async throws {
        for event in ["PreToolUse", "UserPromptSubmit", "Stop"] {
            let hook = startHook(Self.questionHook)
            let id = try await waitForQuestion()["id"] as? String ?? ""
            _ = await board.handleHook(["hook_event_name": event, "session_id": "s1", "tool_name": "Bash"])
            let result = try await value(of: hook)
            XCTAssertTrue(result.isEmpty, event)
            XCTAssertNil(question(), event)
            XCTAssertFalse(board.answer(["questionId": id, "answers": ["Welches Framework?": "Vue"]]), event)
        }
    }

    func testNotificationAndOtherSessionsKeepAsk() async throws {
        let hook = startHook(Self.questionHook)
        _ = try await waitForQuestion()
        _ = await board.handleHook(["hook_event_name": "Notification", "session_id": "s1"])
        _ = await board.handleHook(["hook_event_name": "PostToolUse", "session_id": "s2"])
        XCTAssertNotNil(question())
        XCTAssertNil(hook.value)
        _ = await board.handleHook(["hook_event_name": "UserPromptSubmit", "session_id": "s1"])
        _ = try await value(of: hook)
    }

    func testParallelAsksOfSameSessionStayAnswerable() async throws {
        let bash: JSON = ["hook_event_name": "PermissionRequest", "session_id": "s1", "tool_name": "Bash", "tool_input": ["command": "ls"]]
        let first = startHook(Self.questionHook)
        let firstId = try await waitForQuestion()["id"] as? String
        let second = startHook(bash)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(first.value)
        XCTAssertEqual(question()?["id"] as? String, firstId)
        XCTAssertTrue(board.answer(["questionId": firstId ?? "", "answers": ["Welches Framework?": "Vue"]]))
        _ = try await value(of: first)
        let pending = try await waitForQuestion()
        XCTAssertEqual(pending["kind"] as? String, "permission")
        _ = await board.handleHook(["hook_event_name": "PostToolUse", "session_id": "s1", "tool_name": "Read", "tool_input": ["file_path": "/x"]])
        XCTAssertNil(second.value)
        _ = await board.handleHook(["hook_event_name": "PostToolUse", "session_id": "s1", "tool_name": "Bash", "tool_input": ["command": "pwd"]])
        XCTAssertNil(second.value)
        _ = await board.handleHook(["hook_event_name": "PostToolUse", "session_id": "s1", "tool_name": "Bash", "tool_input": ["command": "ls"]])
        let ran = try await value(of: second)
        XCTAssertTrue(ran.isEmpty)
        XCTAssertNil(question())
    }

    func testRepeatedPermissionReplacesSameRequestOnly() async throws {
        let bash: JSON = ["hook_event_name": "PermissionRequest", "session_id": "s1", "tool_name": "Bash", "tool_input": ["command": "ls"]]
        let first = startHook(bash)
        _ = try await waitForQuestion()
        let second = startHook(bash)
        let replaced = try await value(of: first)
        XCTAssertTrue(replaced.isEmpty)
        let pending = try await waitForQuestion()
        XCTAssertTrue(board.answer(["questionId": pending["id"]!, "decision": "allow"]))
        _ = try await value(of: second)
    }

    func testToolUseIdPicksTheAskThatRan() async throws {
        let bash: JSON = ["hook_event_name": "PermissionRequest", "session_id": "s1", "tool_name": "Bash", "tool_input": ["command": "ls"]]
        let first = startHook(bash.merging(["tool_use_id": "a"]) { $1 })
        _ = try await waitForQuestion()
        let second = startHook(bash.merging(["tool_use_id": "b"]) { $1 })
        try await Task.sleep(for: .milliseconds(50))
        _ = await board.handleHook(["hook_event_name": "PostToolUse", "session_id": "s1", "tool_name": "Bash", "tool_use_id": "b", "tool_input": ["command": "ls"]])
        _ = try await value(of: second)
        XCTAssertNil(first.value)
        XCTAssertNotNil(question())
        _ = await board.handleHook(["hook_event_name": "Stop", "session_id": "s1"])
        _ = try await value(of: first)
    }

    func testAskOfUnknownSessionReturnsAtOnce() async {
        var hook = Self.questionHook
        hook["session_id"] = "ghost"
        let result = await board.handleHook(hook)
        XCTAssertTrue(result.isEmpty)
        let reply = await board.awaitReply(["hook_event_name": "Stop", "session_id": "ghost", "last_assistant_message": "Fertig."])
        XCTAssertEqual(reply, "")
    }

    func testAskTimesOutEmpty() async throws {
        board = Board(claudeDir: dir, askSeconds: 0.2)
        let result = await board.handleHook(Self.questionHook)
        XCTAssertTrue(result.isEmpty)
        XCTAssertNil(question())
    }

    func testEndedSessionReleasesAsk() async throws {
        let hook = startHook(Self.questionHook)
        _ = try await waitForQuestion()
        try FileManager.default.removeItem(at: dir.appending(path: "sessions/1.json"))
        _ = board.snapshot(standAnswers: false)
        let result = try await value(of: hook)
        XCTAssertTrue(result.isEmpty)
    }

    private func lastEvent(_ board: Board) -> JSON? {
        (board.snapshot(standAnswers: false)["events"] as? [JSON])?.last
    }

    private func idleBoard() throws -> Board {
        try write(["pid": Int(getpid()), "sessionId": "s1", "cwd": "/x/app", "name": "Fix", "status": "idle"], to: "sessions/1.json")
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

    func testParkedStopReturnsReplyFromStand() async throws {
        let board = board!
        let stop: JSON = ["hook_event_name": "Stop", "session_id": "s1", "last_assistant_message": "Soll ich committen?"]
        let parked = Task { @MainActor in await board.awaitReply(stop) }
        try await waitForCanReply()
        XCTAssertTrue(board.resolveParked(of: "s1", with: "Ja"))
        let reply = await parked.value
        XCTAssertEqual(reply, "Ja")
        XCTAssertFalse(board.resolveParked(of: "s1", with: "Nochmal"))
        XCTAssertEqual(sessions(board.snapshot(standAnswers: false))[0]["canReply"] as? Bool, false)
    }

    func testNewStopReplacesOlderPark() async throws {
        let board = board!
        let stop: JSON = ["hook_event_name": "Stop", "session_id": "s1", "last_assistant_message": "Fertig."]
        let first = Task { @MainActor in await board.awaitReply(stop) }
        try await waitForCanReply()
        let second = Task { @MainActor in await board.awaitReply(stop) }
        let firstReply = await first.value
        XCTAssertEqual(firstReply, "")
        XCTAssertTrue(board.resolveParked(of: "s1", with: "Weiter"))
        let secondReply = await second.value
        XCTAssertEqual(secondReply, "Weiter")
    }

    func testPromptResolvesParkButNotificationDoesNot() async throws {
        let board = board!
        let parked = Task { @MainActor in await board.awaitReply(["hook_event_name": "Stop", "session_id": "s1", "last_assistant_message": "Fertig."]) }
        try await waitForCanReply()
        _ = await board.handleHook(["hook_event_name": "Notification", "session_id": "s1"])
        XCTAssertEqual(sessions(board.snapshot(standAnswers: false))[0]["canReply"] as? Bool, true)
        _ = await board.handleHook(["hook_event_name": "UserPromptSubmit", "session_id": "s1"])
        let reply = await parked.value
        XCTAssertEqual(reply, "")
        XCTAssertEqual(sessions(board.snapshot(standAnswers: false))[0]["canReply"] as? Bool, false)
    }

    func testParkTimesOutEmpty() async {
        let board = Board(claudeDir: dir, parkSeconds: 0.2)
        let reply = await board.awaitReply(["hook_event_name": "Stop", "session_id": "s1", "last_assistant_message": "Fertig."])
        XCTAssertEqual(reply, "")
    }

    func testParkedPollsAreCapped() async throws {
        try write(["pid": Int(getpid()), "sessionId": "s2", "cwd": "/x/other", "status": "idle"], to: "sessions/2.json")
        let board = Board(claudeDir: dir, maxParked: 1)
        let first = Task { @MainActor in await board.awaitReply(["hook_event_name": "Stop", "session_id": "s1", "last_assistant_message": "Fertig."]) }
        try await Task.sleep(for: .milliseconds(50))
        let refused = await board.awaitReply(["hook_event_name": "Stop", "session_id": "s2", "last_assistant_message": "Fertig."])
        XCTAssertEqual(refused, "")
        XCTAssertTrue(board.resolveParked(of: "s1", with: "Weiter"))
        let reply = await first.value
        XCTAssertEqual(reply, "Weiter")
    }

    func testSweepReleasesEndedSessionsWithoutSnapshot() async throws {
        let board = Board(claudeDir: dir, sweepInterval: 0.1)
        let parked = Task { @MainActor in await board.awaitReply(["hook_event_name": "Stop", "session_id": "s1", "last_assistant_message": "Fertig."]) }
        try await Task.sleep(for: .milliseconds(50))
        try FileManager.default.removeItem(at: dir.appending(path: "sessions/1.json"))
        let reply = await parked.value
        XCTAssertEqual(reply, "")
    }

    func testCodexStopIsNotParked() async {
        let reply = await board.awaitReply(["hook_event_name": "Stop", "session_id": "s1", "agent": "codex", "last_assistant_message": "Fertig."])
        XCTAssertEqual(reply, "")
    }

    func testFreeTextReplyQuotesWaitingQuestion() async {
        _ = await board.handleHook(["hook_event_name": "Stop", "session_id": "s1", "last_assistant_message": "Soll ich committen?"])
        XCTAssertEqual(board.freeTextReply(of: "s1", text: "Nein, erst testen"),
                       "Antwort des Users über Amberlight auf „Soll ich committen?“:\nNein, erst testen")
        XCTAssertEqual(board.freeTextReply(of: "s1", text: "Und dann pushen"), "Nachricht des Users über Amberlight:\nUnd dann pushen")
    }

    func testStopWithoutStandReturnsImmediately() async {
        let result = await board.handleHook(["hook_event_name": "Stop", "session_id": "s1", "last_assistant_message": "Soll ich committen?"])
        XCTAssertTrue(result.isEmpty)
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
        XCTAssertNotNil(waiting?["id"] as? String)
        XCTAssertEqual((board.snapshot(standAnswers: false)["events"] as? [JSON])?.last?["kind"] as? String, "waiting")
    }

    func testNextStepRepliesWithLabelOnlyAndCapsQuestion() async {
        _ = await board.handleHook(["hook_event_name": "PostToolUse", "session_id": "s1", "tool_name": "mcp__ccd_turn__wrap_up",
                                    "tool_input": ["recap": "x", "ask": "Welcher Fix zuerst?" + String(repeating: "x", count: 400),
                                                   "actions": [["label": "Fix 1", "message": "Bitte zuerst Fix 1"],
                                                               ["label": "Fix 2", "message": ""]]]])
        let waiting = sessions(board.snapshot(standAnswers: false))[0]["waiting"] as? JSON
        let id = waiting?["id"] as? String ?? ""
        XCTAssertEqual(waiting?["options"] as? [String], ["Fix 1", "Fix 2"])
        XCTAssertEqual((waiting?["text"] as? String)?.count, 240)
        XCTAssertNil(waiting?["replies"])
        XCTAssertNil(board.redeemReply(of: "s1", noteId: id, option: 2))
        XCTAssertNil(board.redeemReply(of: "other", noteId: id, option: 0))
        XCTAssertNil(board.redeemReply(of: "s1", noteId: "stale", option: 0))
        XCTAssertEqual(board.redeemReply(of: "s1", noteId: id, option: 0), "Fix 1")
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

    private func question() -> JSON? {
        sessions(board.snapshot(standAnswers: false)).first?["question"] as? JSON
    }

    private func waitForQuestion() async throws -> JSON {
        for _ in 0..<50 {
            if let pending = question() { return pending }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("question never appeared")
        return [:]
    }

    private func waitForCanReply() async throws {
        for _ in 0..<50 {
            if sessions(board.snapshot(standAnswers: false)).first?["canReply"] as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("park never appeared")
    }

    private func write(_ json: JSON, to path: String) throws {
        try JSONSerialization.data(withJSONObject: json).write(to: dir.appending(path: path))
    }
}
