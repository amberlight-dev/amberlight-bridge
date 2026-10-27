import XCTest
@testable import StandBridge

@MainActor
final class MacLauncherTests: XCTestCase {
    private func request(_ method: String, _ path: String, token: String, body: String = "") throws -> HTTPRequest {
        let raw = "\(method) \(path) HTTP/1.1\r\nAuthorization: Bearer \(token)\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        return try XCTUnwrap(HTTPRequest.parse(Data(raw.utf8)))
    }

    private func makeServer() -> BridgeServer {
        BridgeServer(board: Board(claudeDir: FileManager.default.temporaryDirectory), token: "abcd1234", port: 1, hostName: "mac.local")
    }

    func testLauncherRoutesRequireToken() async throws {
        let server = makeServer()
        var opened = false
        server.open = { _ in
            opened = true
            return true
        }
        let apps = await server.route(try request("GET", "/apps", token: "nope"), fromLoopback: true).0
        let icon = await server.route(try request("GET", "/icon?bundleId=com.apple.Safari", token: "nope"), fromLoopback: true).0
        let open = await server.route(try request("POST", "/open", token: "nope", body: "{\"bundleId\":\"x\"}"), fromLoopback: true).0
        XCTAssertEqual([apps, icon, open], [401, 401, 401])
        XCTAssertFalse(opened)
    }

    func testOpenPassesTargetAndReportsFailure() async throws {
        let server = makeServer()
        var targets: [String] = []
        server.apps = { [["name": "Safari", "bundleId": "com.apple.Safari", "running": false]] }
        server.open = { target in
            targets.append(target["bundleId"] as? String ?? target["url"] as? String ?? "")
            return target["bundleId"] != nil
        }
        let app = await server.route(try request("POST", "/open", token: "abcd1234", body: "{\"bundleId\":\"com.apple.Safari\"}"), fromLoopback: false).0
        let link = await server.route(try request("POST", "/open", token: "abcd1234", body: "{\"url\":\"https://claude.ai\"}"), fromLoopback: false).0
        XCTAssertEqual([app, link], [200, 404])
        XCTAssertEqual(targets, ["com.apple.Safari", "https://claude.ai"])
    }

    func testOpenRefusesTargetsOutsideAppsWebAndSavedShortcuts() async throws {
        let server = makeServer()
        var opened: [String] = []
        server.apps = { [["name": "Safari", "bundleId": "com.apple.Safari", "running": false]] }
        server.open = { opened.append("\($0)"); return true }
        server.layout.updateShortcuts {
            $0 = [StandShortcut(kind: .url, value: "obsidian://open?vault=x", title: "Vault"),
                  StandShortcut(kind: .shortcut, value: "Licht aus", title: "Licht aus")]
        }
        func open(_ body: String) async throws -> Int {
            await server.route(try request("POST", "/open", token: "abcd1234", body: body), fromLoopback: false).0
        }
        let statuses = [
            try await open("{\"bundleId\":\"com.apple.Terminal\"}"),
            try await open("{\"url\":\"smb://evil/share\"}"),
            try await open("{\"url\":\"vscode://anything\"}"),
            try await open("{\"shortcut\":\"Alles löschen\"}"),
            try await open("{\"url\":\"obsidian://open?vault=x\"}"),
            try await open("{\"shortcut\":\"Licht aus\"}"),
        ]
        XCTAssertEqual(statuses, [403, 403, 403, 403, 200, 200])
        XCTAssertEqual(opened.count, 2)
    }

    func testOpenFolderOnlyOpensPlainFolders() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appending(path: "Evil.app"), withIntermediateDirectories: true)
        try Data("echo".utf8).write(to: dir.appending(path: "x.command"))
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(MacLauncher.isPlainFolder(dir))
        XCTAssertFalse(MacLauncher.isPlainFolder(dir.appending(path: "x.command")))
        XCTAssertFalse(MacLauncher.isPlainFolder(dir.appending(path: "Evil.app")))
    }

    func testAppsAndIconRoutesReturnPayload() async throws {
        let server = makeServer()
        server.apps = { [["name": "Safari", "bundleId": "com.apple.Safari", "running": false]] }
        server.icon = { $0 == "com.apple.Safari" ? Data([1, 2, 3]) : nil }
        let (appsStatus, apps) = await server.route(try request("GET", "/apps", token: "abcd1234"), fromLoopback: false)
        let (iconStatus, icon) = await server.route(try request("GET", "/icon?bundleId=com.apple.Safari", token: "abcd1234"), fromLoopback: false)
        let missing = await server.route(try request("GET", "/icon?bundleId=nope", token: "abcd1234"), fromLoopback: false).0
        XCTAssertEqual([appsStatus, iconStatus, missing], [200, 200, 404])
        XCTAssertEqual((apps["apps"] as? [JSON])?.first?["bundleId"] as? String, "com.apple.Safari")
        XCTAssertEqual(icon["png"] as? String, Data([1, 2, 3]).base64EncodedString())
    }

    func testListsInstalledAppsWithPNGIcons() throws {
        let apps = MacLauncher.apps()
        let safari = try XCTUnwrap(apps.first { $0["bundleId"] as? String == "com.apple.Safari" })
        XCTAssertEqual(safari["name"] as? String, "Safari")
        let png = try XCTUnwrap(MacLauncher.icon(bundleId: "com.apple.Safari"))
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        XCTAssertNil(MacLauncher.icon(bundleId: "invalid.bundle.id.duostand"))
    }

    func testRejectsFileURLs() {
        XCTAssertNil(MacLauncher.openableURL("file:///Applications/Calculator.app"))
        XCTAssertNil(MacLauncher.openableURL("not a url"))
        XCTAssertNotNil(MacLauncher.openableURL("https://claude.ai"))
        XCTAssertNotNil(MacLauncher.openableURL("obsidian://open?vault=x"))
        XCTAssertNil(MacLauncher.openableURL("SMB://evil/share"))
        XCTAssertNil(MacLauncher.openableURL("x-man-page:///ls"))
    }
}
