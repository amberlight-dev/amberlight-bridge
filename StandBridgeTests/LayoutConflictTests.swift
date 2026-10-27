import XCTest
@testable import StandBridge

@MainActor
final class LayoutConflictTests: XCTestCase {
    private var file: URL!

    override func setUp() async throws {
        file = FileManager.default.temporaryDirectory.appending(path: "layout-\(UUID().uuidString)/layout.json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    private func put(_ server: BridgeServer, pages: [StandPage], base: Int?) async throws -> (Int, JSON) {
        var body: JSON = ["pages": try JSONSerialization.jsonObject(with: JSONEncoder().encode(pages))]
        body["baseRevision"] = base
        let data = try JSONSerialization.data(withJSONObject: body)
        let head = "PUT /layout HTTP/1.1\r\nAuthorization: Bearer abcd1234\r\nContent-Length: \(data.count)\r\n\r\n"
        return await server.route(try XCTUnwrap(HTTPRequest.parse(Data(head.utf8) + data)), fromLoopback: false)
    }

    func testStaleBaseRevisionIsRejectedWithCurrentLayout() async throws {
        let server = BridgeServer(board: Board(claudeDir: FileManager.default.temporaryDirectory), layout: LayoutStore(file: file),
                                  token: "abcd1234", port: 1, hostName: "mac.local")
        let first = try await put(server, pages: [.desk()], base: 0).0
        let stale = try await put(server, pages: [.turntable()], base: 0)
        let current = try await put(server, pages: [.nightstand()], base: 1).0
        let legacy = try await put(server, pages: [.desk()], base: nil).0
        XCTAssertEqual([first, stale.0, current, legacy], [200, 409, 200, 200])
        XCTAssertEqual(stale.1["revision"] as? Int, 1)
        XCTAssertEqual(server.layout.revision, 3)
    }

    func testDeviceBackupIsStoredRotatedAndValidated() async throws {
        let server = BridgeServer(board: Board(claudeDir: FileManager.default.temporaryDirectory), layout: LayoutStore(file: file),
                                  token: "abcd1234", port: 1, hostName: "mac.local")
        func post(_ body: JSON, token: String = "abcd1234") async throws -> Int {
            let data = try JSONSerialization.data(withJSONObject: body)
            let head = "POST /layout/backup HTTP/1.1\r\nAuthorization: Bearer \(token)\r\nContent-Length: \(data.count)\r\n\r\n"
            return await server.route(try XCTUnwrap(HTTPRequest.parse(Data(head.utf8) + data)), fromLoopback: false).0
        }
        let pages = try JSONSerialization.jsonObject(with: JSONEncoder().encode([StandPage.desk()]))
        let statuses = [try await post(["pages": pages], token: "nope"), try await post(["nope": 1]), try await post(["pages": pages])]
        XCTAssertEqual(statuses, [401, 400, 200])
        XCTAssertEqual(server.layout.revision, 0)
        for index in 0..<7 {
            XCTAssertTrue(server.layout.storeDeviceBackup(json: ["pages": pages], at: Date(timeIntervalSince1970: Double(index))))
        }
        XCTAssertEqual(LayoutStore.backups(of: file, kind: .device).count, LayoutStore.keptBackups)
    }

    func testEveryReplaceKeepsTheLastFiveBackups() throws {
        let store = LayoutStore(file: file)
        for index in 0..<8 { try store.replace([StandPage(name: "Seite \(index)", items: [])]) }
        let backups = LayoutStore.backups(of: file)
        XCTAssertEqual(backups.map(\.revision), [7, 6, 5, 4, 3])
        let newest = try JSONSerialization.jsonObject(with: Data(contentsOf: backups[0].url)) as? JSON
        XCTAssertEqual(newest?["revision"] as? Int, 7)
    }
}
