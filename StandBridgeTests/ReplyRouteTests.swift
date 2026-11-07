import XCTest
@testable import StandBridge

@MainActor
final class ReplyRouteTests: XCTestCase {
    private var dir: URL!
    private var server: BridgeServer!
    private var noteId = ""
    private var replies: [(String, String)] = []

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appending(path: "sessions"), withIntermediateDirectories: true)
        let entry: JSON = ["pid": Int(getpid()), "sessionId": "s1", "cwd": "/x/app", "name": "Fix", "status": "idle"]
        try JSONSerialization.data(withJSONObject: entry).write(to: dir.appending(path: "sessions/1.json"))
        let board = Board(claudeDir: dir)
        _ = await board.handleHook(["hook_event_name": "PostToolUse", "session_id": "s1", "tool_name": "mcp__ccd_turn__wrap_up",
                                    "tool_input": ["ask": "Committen?", "actions": [["label": "Ja", "message": "Ja, bitte committen"]]]])
        let sessions = board.snapshot(standAnswers: false)["sessions"] as? [JSON]
        noteId = (sessions?.first?["waiting"] as? JSON)?["id"] as? String ?? ""
        server = BridgeServer(board: board, layout: LayoutStore(file: dir.appending(path: "layout.json")), deviceToken: "abcd1234", localToken: "hook5678", port: 1, hostName: "mac.local")
        replies = []
        server.reply = { [unowned self] text, entry in
            replies.append((text, entry["sessionId"] as? String ?? ""))
            return ["sent": true, "copied": false]
        }
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func post(_ body: String, token: String = "abcd1234") async throws -> (Int, JSON) {
        let raw = "POST /reply HTTP/1.1\r\nAuthorization: Bearer \(token)\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        return await server.route(try XCTUnwrap(HTTPRequest.parse(Data(raw.utf8))), fromLoopback: false)
    }

    func testRequiresToken() async throws {
        let status = try await post("{\"sessionId\":\"s1\",\"noteId\":\"\(noteId)\",\"option\":0}", token: "nope").0
        XCTAssertEqual(status, 401)
        XCTAssertTrue(replies.isEmpty)
    }

    func testSendsTheOfferedLabelOnceAndLogsIt() async throws {
        let body = "{\"sessionId\":\"s1\",\"noteId\":\"\(noteId)\",\"option\":0}"
        let (status, payload) = try await post(body)
        let again = try await post(body).0
        XCTAssertEqual([status, again], [200, 404])
        XCTAssertEqual(payload["sent"] as? Bool, true)
        XCTAssertEqual(replies.map(\.0), ["Ja"])
        XCTAssertEqual(server.replyLog.count, 1)
    }

    func testRejectsUnknownOptionsSessionsNotesAndBadText() async throws {
        let wrongOption = try await post("{\"sessionId\":\"s1\",\"noteId\":\"\(noteId)\",\"option\":3}").0
        let wrongSession = try await post("{\"sessionId\":\"s2\",\"noteId\":\"\(noteId)\",\"option\":0}").0
        let staleNote = try await post("{\"sessionId\":\"s1\",\"noteId\":\"old\",\"option\":0}").0
        let blank = try await post("{\"sessionId\":\"s1\",\"text\":\"   \"}").0
        let tooLong = try await post("{\"sessionId\":\"s1\",\"text\":\"\(String(repeating: "x", count: 4001))\"}").0
        let unknownSession = try await post("{\"sessionId\":\"s2\",\"text\":\"hallo\"}").0
        XCTAssertEqual([wrongOption, wrongSession, staleNote, blank, tooLong, unknownSession], [404, 404, 404, 400, 400, 404])
        XCTAssertTrue(replies.isEmpty)
    }

    func testRefusesPasteWhileSessionHasOpenAsk() async throws {
        let board = server.board
        let ask = Task { @MainActor in
            _ = await board.handleHook(["hook_event_name": "PermissionRequest", "session_id": "s1", "tool_name": "Bash", "tool_input": ["command": "ls"]])
        }
        try await Task.sleep(for: .milliseconds(50))
        let (status, payload) = try await post("{\"sessionId\":\"s1\",\"noteId\":\"\(noteId)\",\"option\":0}")
        XCTAssertEqual(status, 200)
        XCTAssertEqual(payload as NSDictionary, ["sent": false, "copied": false])
        XCTAssertTrue(replies.isEmpty)
        _ = await board.handleHook(["hook_event_name": "UserPromptSubmit", "session_id": "s1"])
        await ask.value
    }

    private func awaitStop() -> Task<(Int, String), Never> {
        let body = #"{"hook_event_name":"Stop","session_id":"s1","last_assistant_message":"Fertig."}"#
        let raw = "POST /hook/await HTTP/1.1\r\nHost: 127.0.0.1:1\r\nX-Stand-Hook: hook5678\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let server = server!
        return Task { @MainActor in
            let (status, payload) = await server.route(HTTPRequest.parse(Data(raw.utf8))!, fromLoopback: true)
            return (status, payload["text"] as? String ?? "?")
        }
    }

    private func waitForCanReply() async throws {
        for _ in 0..<50 {
            let session = (server.board.snapshot(standAnswers: false)["sessions"] as? [JSON])?.first
            if session?["canReply"] as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("park never appeared")
    }

    func testFreeTextGoesToParkedStopAsPlainText() async throws {
        let parked = awaitStop()
        try await waitForCanReply()
        let (status, payload) = try await post(#"{"sessionId":"s1","text":"  Nein, erst testen  "}"#)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(payload as NSDictionary, ["sent": true, "copied": false])
        let (hookStatus, text) = await parked.value
        XCTAssertEqual(hookStatus, 200)
        XCTAssertEqual(text, "Antwort des Users über Amberlight auf „Committen?“:\nNein, erst testen")
        XCTAssertTrue(replies.isEmpty)
        XCTAssertEqual(server.replyLog.count, 1)
    }

    func testOptionGoesToParkedStop() async throws {
        let parked = awaitStop()
        try await waitForCanReply()
        let status = try await post("{\"sessionId\":\"s1\",\"noteId\":\"\(noteId)\",\"option\":0}").0
        XCTAssertEqual(status, 200)
        let text = await parked.value.1
        XCTAssertEqual(text, "Ja")
        XCTAssertTrue(replies.isEmpty)
    }

    func testSupersededParkAnswersEmpty() async throws {
        let parked = awaitStop()
        try await waitForCanReply()
        _ = await server.board.handleHook(["hook_event_name": "UserPromptSubmit", "session_id": "s1"])
        let (status, text) = await parked.value
        XCTAssertEqual([status], [200])
        XCTAssertEqual(text, "")
    }

    func testFreeTextWithoutParkFallsBackToMacReply() async throws {
        let (status, payload) = try await post(#"{"sessionId":"s1","text":"Weiter"}"#)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(payload["sent"] as? Bool, true)
        XCTAssertEqual(replies.map(\.0), ["Antwort des Users über Amberlight auf „Committen?“:\nWeiter"])
    }

    func testConstantTimeEqualsIsCorrect() {
        XCTAssertTrue(BridgeServer.constantTimeEquals("Bearer abc", "Bearer abc"))
        XCTAssertFalse(BridgeServer.constantTimeEquals("Bearer abd", "Bearer abc"))
        XCTAssertFalse(BridgeServer.constantTimeEquals("Bearer ab", "Bearer abc"))
        XCTAssertFalse(BridgeServer.constantTimeEquals("", "Bearer abc"))
    }
}
