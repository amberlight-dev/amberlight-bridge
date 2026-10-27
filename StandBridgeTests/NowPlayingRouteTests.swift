import XCTest
@testable import StandBridge

@MainActor
final class NowPlayingRouteTests: XCTestCase {
    private func request(_ method: String, _ path: String, token: String = "abcd1234", body: String = "") throws -> HTTPRequest {
        let raw = "\(method) \(path) HTTP/1.1\r\nAuthorization: Bearer \(token)\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        return try XCTUnwrap(HTTPRequest.parse(Data(raw.utf8)))
    }

    private func makeServer() -> BridgeServer {
        let server = BridgeServer(board: Board(claudeDir: FileManager.default.temporaryDirectory), token: "abcd1234", port: 1, hostName: "mac.local")
        server.nowPlaying = { ["title": "egoist", "playing": true, "artworkId": "a1"] }
        server.nowPlayingArtwork = { $0 == "a1" ? ["id": "a1", "data": "AAAA"] : nil }
        return server
    }

    func testRoutesRequireToken() async throws {
        let server = makeServer()
        let statuses = await [
            server.route(try request("GET", "/nowplaying", token: "nope"), fromLoopback: true).0,
            server.route(try request("GET", "/nowplaying/artwork?id=a1", token: "nope"), fromLoopback: true).0,
            server.route(try request("POST", "/nowplaying", token: "nope", body: #"{"command":"toggle"}"#), fromLoopback: true).0,
        ]
        XCTAssertEqual(statuses, [401, 401, 401])
    }

    func testInfoAndArtworkByIdentifier() async throws {
        let server = makeServer()
        let (status, info) = await server.route(try request("GET", "/nowplaying"), fromLoopback: false)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(info["title"] as? String, "egoist")

        let (artworkStatus, artwork) = await server.route(try request("GET", "/nowplaying/artwork?id=a1"), fromLoopback: false)
        XCTAssertEqual(artworkStatus, 200)
        XCTAssertEqual(artwork["data"] as? String, "AAAA")
        let stale = await server.route(try request("GET", "/nowplaying/artwork?id=old"), fromLoopback: false).0
        XCTAssertEqual(stale, 404)
    }

    func testControlPassesBodyAndReportsFailure() async throws {
        let server = makeServer()
        var received: [JSON] = []
        server.nowPlayingControl = { body in
            received.append(body)
            return body["command"] as? String == "next"
        }
        let ok = await server.route(try request("POST", "/nowplaying", body: #"{"command":"next"}"#), fromLoopback: false).0
        let rejected = await server.route(try request("POST", "/nowplaying", body: #"{"command":"bogus"}"#), fromLoopback: false).0
        XCTAssertEqual([ok, rejected], [200, 400])
        XCTAssertEqual(received.compactMap { $0["command"] as? String }, ["next", "bogus"])
    }
}
