import XCTest
@testable import StandBridge

@MainActor
final class RequestLogTests: XCTestCase {
    private func request(_ method: String, _ path: String) throws -> HTTPRequest {
        try XCTUnwrap(HTTPRequest.parse(Data("\(method) \(path) HTTP/1.1\r\n\r\n".utf8)))
    }

    private func makeServer() -> BridgeServer {
        BridgeServer(board: Board(claudeDir: FileManager.default.temporaryDirectory), token: "abcd1234", port: 1, hostName: "mac.local")
    }

    func testTileSnappingSurvivesAnUnmeasuredCanvas() {
        XCTAssertEqual(LayoutTile.cells(0, per: 0), 0)
        XCTAssertEqual(LayoutTile.cells(40, per: 0), 0)
        XCTAssertEqual(LayoutTile.cells(.nan, per: 120), 0)
        XCTAssertEqual(LayoutTile.cells(130, per: 120), 1)
        XCTAssertEqual(LayoutTile.cells(-250, per: 120), -2)
        XCTAssertEqual(LayoutTile.cells(1e12, per: 0.001), 100)
    }

    func testSnapshotFromThePhoneMarksItConnectedWithoutFloodingTheLog() throws {
        let server = makeServer()
        let now = Date(timeIntervalSince1970: 1000)
        server.record(try request("GET", "/snapshot"), status: 200, host: "192.168.1.20", loopback: false, at: now)
        server.record(try request("GET", "/snapshot"), status: 401, host: "192.168.1.99", loopback: false, at: now.addingTimeInterval(1))
        server.record(try request("GET", "/snapshot"), status: 200, host: "127.0.0.1", loopback: true, at: now.addingTimeInterval(2))
        XCTAssertEqual(server.lastClient, ClientContact(at: now, host: "192.168.1.20"))
        XCTAssertTrue(server.requestLog.isEmpty)
        XCTAssertTrue(server.lastClient!.isOnline(now: now.addingTimeInterval(5)))
        XCTAssertFalse(server.lastClient!.isOnline(now: now.addingTimeInterval(30)))
    }

    func testLogKeepsTheLatestActionsAndSkipsPolling() throws {
        let server = makeServer()
        server.record(try request("GET", "/system"), status: 200, host: "phone", loopback: false)
        for index in 0..<(RequestLogEntry.limit + 5) {
            server.record(try request("POST", "/open"), status: index.isMultiple(of: 2) ? 200 : 404, host: "phone", loopback: false)
        }
        server.record(try request("POST", "/hook"), status: 200, host: "127.0.0.1", loopback: true)
        XCTAssertEqual(server.requestLog.count, RequestLogEntry.limit)
        XCTAssertEqual(server.requestLog.last?.title, "Hook von Claude Code")
        XCTAssertEqual(server.requestLog.last?.host, "Mac")
        XCTAssertFalse(server.requestLog.contains { $0.path == "/system" })
    }
}
