import Network
import XCTest
@testable import StandBridge

@MainActor
final class ConnectionTimeoutTests: XCTestCase {
    func testClientThatNeverFinishesItsRequestIsDisconnected() async throws {
        let server = BridgeServer(board: Board(claudeDir: FileManager.default.temporaryDirectory), deviceToken: "abcd1234", localToken: "hook5678", port: 7493, hostName: "localhost")
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

    func testAwaitAnswersWithEmptyPlainTextBody() async throws {
        let server = BridgeServer(board: Board(claudeDir: FileManager.default.temporaryDirectory, parkSeconds: 0.2), deviceToken: "abcd1234", localToken: "hook5678", port: 7494, hostName: "localhost")
        server.start()
        try await Task.sleep(for: .milliseconds(300))
        var request = URLRequest(url: URL(string: "http://127.0.0.1:7494/hook/await")!)
        request.httpMethod = "POST"
        request.setValue("hook5678", forHTTPHeaderField: "x-stand-hook")
        request.httpBody = Data(#"{"hook_event_name":"Stop","session_id":"x"}"#.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Type"), "text/plain; charset=utf-8")
        XCTAssertTrue(data.isEmpty)
    }
}
