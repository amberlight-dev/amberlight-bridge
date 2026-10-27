import Network
import XCTest
@testable import StandBridge

@MainActor
final class ConnectionTimeoutTests: XCTestCase {
    func testClientThatNeverFinishesItsRequestIsDisconnected() async throws {
        let server = BridgeServer(board: Board(claudeDir: FileManager.default.temporaryDirectory), token: "abcd1234", port: 7493, hostName: "localhost")
        server.readTimeout = .milliseconds(300)
        server.start()
        try await Task.sleep(for: .milliseconds(300))
        let client = NWConnection(host: "127.0.0.1", port: 7493, using: .tcp)
        client.start(queue: .main)
        client.send(content: Data("GET /snapshot HTTP/1.1\r\n".utf8), completion: .idempotent)
        let started = Date.now
        let closed = await withCheckedContinuation { continuation in
            client.receive(minimumIncompleteLength: 1, maximumLength: 1024) { _, _, isComplete, error in
                continuation.resume(returning: isComplete || error != nil)
            }
        }
        client.cancel()
        XCTAssertTrue(closed)
        XCTAssertLessThan(Date.now.timeIntervalSince(started), 5)
    }
}
