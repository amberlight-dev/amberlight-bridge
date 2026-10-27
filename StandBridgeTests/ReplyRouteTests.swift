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
        let entry: JSON = ["pid": Int(getpid()), "sessionId": "s1", "cwd": "/x/orbit", "name": "Fix", "status": "idle"]
        try JSONSerialization.data(withJSONObject: entry).write(to: dir.appending(path: "sessions/1.json"))
        let board = Board(claudeDir: dir)
        _ = await board.handleHook(["hook_event_name": "PostToolUse", "session_id": "s1", "tool_name": "mcp__ccd_turn__wrap_up",
                                    "tool_input": ["ask": "Committen?", "actions": [["label": "Ja", "message": "Ja, bitte committen"]]]])
        let sessions = board.snapshot(standAnswers: false)["sessions"] as? [JSON]
        noteId = (sessions?.first?["waiting"] as? JSON)?["id"] as? String ?? ""
        server = BridgeServer(board: board, layout: LayoutStore(file: dir.appending(path: "layout.json")), token: "abcd1234", port: 1, hostName: "mac.local")
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

    func testSendsTheOfferedMessageOnceAndLogsIt() async throws {
        let body = "{\"sessionId\":\"s1\",\"noteId\":\"\(noteId)\",\"option\":0}"
        let (status, payload) = try await post(body)
        let again = try await post(body).0
        XCTAssertEqual([status, again], [200, 404])
        XCTAssertEqual(payload["sent"] as? Bool, true)
        XCTAssertEqual(replies.map(\.0), ["Ja, bitte committen"])
        XCTAssertEqual(server.replyLog.count, 1)
    }

    func testRejectsUnknownOptionsSessionsNotesAndFreeText() async throws {
        let wrongOption = try await post("{\"sessionId\":\"s1\",\"noteId\":\"\(noteId)\",\"option\":3}").0
        let wrongSession = try await post("{\"sessionId\":\"s2\",\"noteId\":\"\(noteId)\",\"option\":0}").0
        let staleNote = try await post("{\"sessionId\":\"s1\",\"noteId\":\"old\",\"option\":0}").0
        let freeText = try await post("{\"sessionId\":\"s1\",\"text\":\"rm -rf /\"}").0
        XCTAssertEqual([wrongOption, wrongSession, staleNote, freeText], [404, 404, 404, 404])
        XCTAssertTrue(replies.isEmpty)
    }

    func testConstantTimeEqualsIsCorrect() {
        XCTAssertTrue(BridgeServer.constantTimeEquals("Bearer abc", "Bearer abc"))
        XCTAssertFalse(BridgeServer.constantTimeEquals("Bearer abd", "Bearer abc"))
        XCTAssertFalse(BridgeServer.constantTimeEquals("Bearer ab", "Bearer abc"))
        XCTAssertFalse(BridgeServer.constantTimeEquals("", "Bearer abc"))
    }
}
