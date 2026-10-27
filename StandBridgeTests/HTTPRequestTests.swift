import XCTest
@testable import StandBridge

@MainActor
final class HTTPRequestTests: XCTestCase {
    func testParsesQueryHeadersAndBody() throws {
        let raw = "POST /answer?answer=1 HTTP/1.1\r\nAuthorization: Bearer abc\r\nContent-Length: 11\r\n\r\n{\"a\":\"b\"}xx"
        let request = try XCTUnwrap(HTTPRequest.parse(Data(raw.utf8)))
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/answer")
        XCTAssertEqual(request.query["answer"], "1")
        XCTAssertEqual(request.headers["authorization"], "Bearer abc")
        XCTAssertEqual(request.body.count, 11)
    }

    func testWaitsForCompleteBody() {
        let raw = "POST /hook HTTP/1.1\r\nContent-Length: 20\r\n\r\n{\"a\":"
        XCTAssertNil(HTTPRequest.parse(Data(raw.utf8)))
    }

    func testNegativeContentLengthParsesWithEmptyBody() throws {
        let raw = "GET / HTTP/1.1\r\nContent-Length: -1\r\n\r\nxyz"
        let request = try XCTUnwrap(HTTPRequest.parse(Data(raw.utf8)))
        XCTAssertEqual(request.body.count, 0)
    }

    func testHookRejectsBrowserLikeRequests() async throws {
        let server = BridgeServer(board: Board(claudeDir: FileManager.default.temporaryDirectory), token: "abcd1234", port: 1, hostName: "mac.local")
        func hook(_ headers: String) async throws -> Int {
            let raw = "POST /hook HTTP/1.1\r\n\(headers)Content-Length: 2\r\n\r\n{}"
            return await server.route(try XCTUnwrap(HTTPRequest.parse(Data(raw.utf8))), fromLoopback: true).0
        }
        let curl = try await hook("Host: 127.0.0.1:1\r\nX-Stand-Hook: abcd1234\r\n")
        let ipv6 = try await hook("Host: [::1]:1\r\nX-Stand-Hook: abcd1234\r\n")
        let noHeader = try await hook("Host: 127.0.0.1:1\r\n")
        let wrongToken = try await hook("Host: 127.0.0.1:1\r\nX-Stand-Hook: nope\r\n")
        let withOrigin = try await hook("Host: 127.0.0.1:1\r\nX-Stand-Hook: abcd1234\r\nOrigin: https://evil.example\r\n")
        let rebound = try await hook("Host: evil.example:1\r\nX-Stand-Hook: abcd1234\r\n")
        let noHost = try await hook("X-Stand-Hook: abcd1234\r\n")
        XCTAssertEqual([curl, ipv6, noHeader, wrongToken, withOrigin, rebound, noHost], [200, 200, 401, 401, 403, 403, 403])
    }

    func testInstalledHookCommandReadsTokenAtRuntime() {
        XCTAssertTrue(ClaudeSettings.blockingCommand.contains(#"$(cat "$HOME/.config/duo-stand/token")"#))
        XCTAssertTrue(ClaudeSettings.asyncCommand.contains("x-stand-hook"))
    }

    func testRouteChecksTokenAndLoopback() async throws {
        let server = BridgeServer(board: Board(claudeDir: FileManager.default.temporaryDirectory), token: "abcd1234", port: 1, hostName: "mac.local")
        let snapshot = "GET /snapshot HTTP/1.1\r\nAuthorization: Bearer abcd1234\r\n\r\n"
        let wrongToken = "GET /snapshot HTTP/1.1\r\nAuthorization: Bearer nope\r\n\r\n"
        let hook = "POST /hook HTTP/1.1\r\nHost: 127.0.0.1:1\r\nX-Stand-Hook: abcd1234\r\nContent-Length: 2\r\n\r\n{}"
        let ok = await server.route(try XCTUnwrap(HTTPRequest.parse(Data(snapshot.utf8))), fromLoopback: false).0
        let unauthorized = await server.route(try XCTUnwrap(HTTPRequest.parse(Data(wrongToken.utf8))), fromLoopback: false).0
        let remoteHook = await server.route(try XCTUnwrap(HTTPRequest.parse(Data(hook.utf8))), fromLoopback: false).0
        let localHook = await server.route(try XCTUnwrap(HTTPRequest.parse(Data(hook.utf8))), fromLoopback: true).0
        XCTAssertEqual([ok, unauthorized, remoteHook, localHook], [200, 401, 403, 200])
    }

    func testHookPayloadTagsAgentAndPid() throws {
        func payload(_ target: String, body: String = "{}") throws -> JSON {
            let raw = "POST \(target) HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
            return BridgeServer.hookPayload(try XCTUnwrap(HTTPRequest.parse(Data(raw.utf8))))
        }
        let claude = try payload("/hook", body: #"{"session_id":"s","pid":4242}"#)
        XCTAssertEqual(claude["agent"] as? String, "claude")
        XCTAssertNil(claude["pid"])
        let codex = try payload("/hook?agent=codex&pid=812")
        XCTAssertEqual(codex["agent"] as? String, "codex")
        XCTAssertEqual(codex["pid"] as? Int32, 812)
        XCTAssertNil(try payload("/hook?agent=codex&pid=1")["pid"])
        XCTAssertNil(try payload("/hook?agent=codex&pid=")["pid"])
        XCTAssertEqual(try payload("/hook?agent=gemini")["agent"] as? String, "claude")
    }

    func testCodexHookRouteRegistersSession() async throws {
        let server = BridgeServer(board: Board(claudeDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)),
                                  token: "abcd1234", port: 1, hostName: "mac.local")
        let body = #"{"hook_event_name":"UserPromptSubmit","session_id":"c1","cwd":"/x/shop","prompt":"los"}"#
        let raw = "POST /hook?agent=codex&pid=\(getpid()) HTTP/1.1\r\nHost: 127.0.0.1:1\r\nX-Stand-Hook: abcd1234\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let status = await server.route(try XCTUnwrap(HTTPRequest.parse(Data(raw.utf8))), fromLoopback: true).0
        XCTAssertEqual(status, 200)
        XCTAssertEqual(server.board.session("c1")?["agent"] as? String, "codex")
        XCTAssertEqual(server.board.session("c1")?["pid"] as? Int32, getpid())
    }

    func testFocusChecksTokenAndKnownSession() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appending(path: "sessions"), withIntermediateDirectories: true)
        let entry: JSON = ["pid": Int(getpid()), "sessionId": "s1", "cwd": "/x/orbit", "entrypoint": "cli"]
        try JSONSerialization.data(withJSONObject: entry).write(to: dir.appending(path: "sessions/1.json"))
        let server = BridgeServer(board: Board(claudeDir: dir), token: "abcd1234", port: 1, hostName: "mac.local")
        var focused: [String] = []
        server.focus = { entry in
            focused.append(entry["sessionId"] as? String ?? "")
            return .window
        }
        func focus(_ sessionId: String, token: String) async throws -> (Int, JSON) {
            let body = "{\"sessionId\":\"\(sessionId)\"}"
            let raw = "POST /focus HTTP/1.1\r\nAuthorization: Bearer \(token)\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
            return await server.route(try XCTUnwrap(HTTPRequest.parse(Data(raw.utf8))), fromLoopback: false)
        }
        let unauthorized = try await focus("s1", token: "nope").0
        let unknown = try await focus("ghost", token: "abcd1234").0
        let (ok, payload) = try await focus("s1", token: "abcd1234")
        XCTAssertEqual([unauthorized, unknown, ok], [401, 404, 200])
        XCTAssertEqual(payload["focused"] as? String, "window")
        XCTAssertEqual(focused, ["s1"])
        XCTAssertEqual(server.lastFocus, .window)
    }
}
