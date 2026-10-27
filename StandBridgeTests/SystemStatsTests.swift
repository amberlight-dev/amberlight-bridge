import XCTest
@testable import StandBridge

@MainActor
final class SystemStatsTests: XCTestCase {
    private func request(token: String) throws -> HTTPRequest {
        let raw = "GET /system HTTP/1.1\r\nAuthorization: Bearer \(token)\r\nContent-Length: 0\r\n\r\n"
        return try XCTUnwrap(HTTPRequest.parse(Data(raw.utf8)))
    }

    private func makeServer() -> BridgeServer {
        BridgeServer(board: Board(claudeDir: FileManager.default.temporaryDirectory), token: "abcd1234", port: 1, hostName: "mac.local")
    }

    func testSystemRouteRequiresToken() async throws {
        let server = makeServer()
        var sampled = false
        server.system = {
            sampled = true
            return [:]
        }
        let status = await server.route(try request(token: "nope"), fromLoopback: true).0
        XCTAssertEqual(status, 401)
        XCTAssertFalse(sampled)
    }

    func testSystemRouteReturnsSample() async throws {
        let server = makeServer()
        server.system = { ["cpu": 0.25, "memory": 0.5] }
        let (status, payload) = await server.route(try request(token: "abcd1234"), fromLoopback: false)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(payload["cpu"] as? Double, 0.25)
        XCTAssertEqual(payload["memory"] as? Double, 0.5)
    }

    func testRealSampleIsAFraction() throws {
        _ = SystemStats.current()
        Thread.sleep(forTimeInterval: 0.2)
        let sample = SystemStats.current()
        let cpu = try XCTUnwrap(sample["cpu"] as? Double)
        let memory = try XCTUnwrap(sample["memory"] as? Double)
        XCTAssertTrue((0...1).contains(cpu))
        XCTAssertTrue(memory > 0 && memory <= 1)
        let used = try XCTUnwrap(sample["memoryUsed"] as? Double)
        let total = try XCTUnwrap(sample["memoryTotal"] as? Double)
        XCTAssertEqual(total, Double(ProcessInfo.processInfo.physicalMemory))
        XCTAssertTrue(used > 0 && used <= total)
        XCTAssertTrue(["normal", "warn", "critical"].contains(sample["pressure"] as? String ?? ""))
        XCTAssertTrue(["nominal", "fair", "serious", "critical"].contains(sample["thermal"] as? String ?? ""))
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(sample["netIn"] as? Double), 0)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(sample["netOut"] as? Double), 0)
        XCTAssertNotNil(try? JSONSerialization.data(withJSONObject: sample))
    }
}
