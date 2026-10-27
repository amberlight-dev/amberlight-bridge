import XCTest
@testable import StandBridge

@MainActor
final class LayoutTests: XCTestCase {
    private var file: URL!

    override func setUp() async throws {
        file = FileManager.default.temporaryDirectory.appending(path: "layout-\(UUID().uuidString)/layout.json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    private func makeServer() -> BridgeServer {
        BridgeServer(
            board: Board(claudeDir: FileManager.default.temporaryDirectory),
            layout: LayoutStore(file: file),
            token: "abcd1234",
            port: 1,
            hostName: "mac.local"
        )
    }

    private func send(_ server: BridgeServer, _ method: String, _ path: String, token: String = "abcd1234", body: JSON? = nil) async throws -> (Int, JSON) {
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0) } ?? Data()
        let head = "\(method) \(path) HTTP/1.1\r\nAuthorization: Bearer \(token)\r\nContent-Length: \(data.count)\r\n\r\n"
        let request = try XCTUnwrap(HTTPRequest.parse(Data(head.utf8) + data))
        return await server.route(request, fromLoopback: false)
    }

    private func pagesJSON(_ pages: [StandPage]) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(pages))
    }

    private func decodedPages(_ payload: JSON) throws -> [StandPage] {
        let data = try JSONSerialization.data(withJSONObject: try XCTUnwrap(payload["pages"]))
        return try JSONDecoder().decode([StandPage].self, from: data)
    }

    func testRejectsWrongToken() async throws {
        let server = makeServer()
        let get = try await send(server, "GET", "/layout", token: "nope").0
        let put = try await send(server, "PUT", "/layout", token: "nope", body: ["pages": try pagesJSON([.desk()])]).0
        XCTAssertEqual([get, put], [401, 401])
        XCTAssertEqual(server.layout.revision, 0)
    }

    func testFreshBridgeStartsAtRevisionZero() async throws {
        let (status, payload) = try await send(makeServer(), "GET", "/layout")
        XCTAssertEqual(status, 200)
        XCTAssertEqual(payload["revision"] as? Int, 0)
        XCTAssertEqual(try decodedPages(payload), [])
    }

    func testEveryPutBumpsRevisionAndLastWriteWins() async throws {
        let server = makeServer()
        let first = [StandPage.desk(), .nightstand()]
        let second = [StandPage.turntable()]
        let (put1, reply1) = try await send(server, "PUT", "/layout", body: ["pages": try pagesJSON(first)])
        let (put2, reply2) = try await send(server, "PUT", "/layout", body: ["pages": try pagesJSON(second)])
        XCTAssertEqual([put1, put2], [200, 200])
        XCTAssertEqual(reply1["revision"] as? Int, 1)
        XCTAssertEqual(reply2["revision"] as? Int, 2)
        let (_, payload) = try await send(server, "GET", "/layout")
        XCTAssertEqual(payload["revision"] as? Int, 2)
        XCTAssertEqual(try decodedPages(payload), second)
    }

    func testRepeatedFirstContactReplacesNeverAppends() async throws {
        let server = makeServer()
        let phone = [StandPage.desk(), .nightstand(), .turntable()]
        let duo = [StandPage.desk(), .nightstand()]
        for pages in [phone, duo, phone, phone] {
            _ = try await send(server, "PUT", "/layout", body: ["pages": try pagesJSON(pages)])
        }
        let (_, payload) = try await send(server, "GET", "/layout")
        XCTAssertEqual(try decodedPages(payload), phone)
        XCTAssertEqual(payload["revision"] as? Int, 4)
    }

    func testShortcutsTravelWithTheLayoutAndSurviveOldClients() async throws {
        let server = makeServer()
        let mail = StandShortcut(kind: .app, value: "com.apple.mail", title: "Mail")
        let shortcuts = try JSONSerialization.jsonObject(with: JSONEncoder().encode([mail]))
        _ = try await send(server, "PUT", "/layout", body: ["pages": try pagesJSON([.desk()]), "shortcuts": shortcuts])
        _ = try await send(server, "PUT", "/layout", body: ["pages": try pagesJSON([.nightstand()])])
        let (_, payload) = try await send(server, "GET", "/layout")
        let data = try JSONSerialization.data(withJSONObject: try XCTUnwrap(payload["shortcuts"]))
        XCTAssertEqual(try JSONDecoder().decode([StandShortcut].self, from: data), [mail])
        XCTAssertEqual(LayoutStore(file: file).shortcuts, [mail])
        let broken = try await send(server, "PUT", "/layout", body: ["pages": try pagesJSON([.desk()]), "shortcuts": [["kind": "nope"]]]).0
        XCTAssertEqual(broken, 400)
    }

    func testOpenRouteOpensOnlySavedFolders() async throws {
        let server = makeServer()
        var opened: [String] = []
        server.openFolder = { opened.append($0); return true }
        server.open = { _ in false }
        server.layout.updateShortcuts { $0 = [StandShortcut(kind: .url, value: "file:///Users/test/Projekte/", title: "Projekte")] }
        let saved = try await send(server, "POST", "/open", body: ["url": "file:///Users/test/Projekte/"]).0
        let foreign = try await send(server, "POST", "/open", body: ["url": "file:///etc/"]).0
        XCTAssertEqual([saved, foreign], [200, 403])
        XCTAssertEqual(opened, ["file:///Users/test/Projekte/"])
    }

    func testPutCannotAddFolderLinksButKeepsTheMacOnes() async throws {
        let server = makeServer()
        let projects = StandShortcut(kind: .url, value: "file:///Users/test/Projekte/", title: "Projekte")
        server.layout.updateShortcuts { $0 = [projects] }
        let sneaked = StandShortcut(kind: .url, value: "file:///Volumes/evil/x.command", title: "x")
        let web = StandShortcut(kind: .url, value: "https://claude.ai", title: "Claude")
        let shortcuts = try JSONSerialization.jsonObject(with: JSONEncoder().encode([projects, sneaked, web]))
        _ = try await send(server, "PUT", "/layout", body: ["pages": try pagesJSON([.desk()]), "shortcuts": shortcuts])
        XCTAssertEqual(server.layout.shortcuts, [projects, web])
        XCTAssertEqual(server.layout.folderLinks, [projects.value])
    }

    func testLinkInputBecomesAnOpenableShortcut() {
        XCTAssertEqual(ShortcutsEditor.shortcut(forLink: " github.com/lab73 ")?.value, "https://github.com/lab73")
        XCTAssertEqual(ShortcutsEditor.shortcut(forLink: "github.com")?.title, "github.com")
        XCTAssertEqual(ShortcutsEditor.shortcut(forLink: "raycast://extensions")?.value, "raycast://extensions")
        XCTAssertNil(ShortcutsEditor.shortcut(forLink: "file:///etc/passwd"))
        XCTAssertNil(ShortcutsEditor.shortcut(forLink: "  "))
    }

    func testWidgetSettingsTravelThroughTheBridge() async throws {
        let server = makeServer()
        var item = PlacedWidget(widget: .clock, frame: GridRect(x: 0, y: 0, w: 2, h: 1))
        item.settings = WidgetSettings(showsSeconds: true, showsDate: false)
        let pages = [StandPage(name: "Uhr", items: [item])]
        _ = try await send(server, "PUT", "/layout", body: ["pages": try pagesJSON(pages)])
        let (_, payload) = try await send(server, "GET", "/layout")
        XCTAssertEqual(try decodedPages(payload).first?.items.first?.settings, item.settings)
        XCTAssertEqual(LayoutStore(file: file).pages, pages)
    }

    func testEdgesTravelAndSurviveClientsThatDoNotSendThem() async throws {
        let server = makeServer()
        let edges = #"{"version":2,"slots":["top","sessionPips"],"hiddenPages":[]}"#
        _ = try await send(server, "PUT", "/layout", body: ["pages": try pagesJSON([.desk()]), "edges": edges])
        _ = try await send(server, "PUT", "/layout", body: ["pages": try pagesJSON([.nightstand()])])
        let (_, payload) = try await send(server, "GET", "/layout")
        XCTAssertEqual(payload["edges"] as? String, edges)
        XCTAssertEqual(LayoutStore(file: file).edgesRaw, edges)
        let broken = try await send(server, "PUT", "/layout", body: ["pages": try pagesJSON([.desk()]), "edges": ["nope": 1]]).0
        XCTAssertEqual(broken, 400)
    }

    func testFreshStoreSendsNoEdges() async throws {
        let (_, payload) = try await send(makeServer(), "GET", "/layout")
        XCTAssertNil(payload["edges"])
    }

    func testPreferencesMergeAndDeviceStatusIsStored() async throws {
        let server = makeServer()
        _ = try await send(server, "PUT", "/layout", body: ["pages": try pagesJSON([.desk()]), "preferences": ["answerHere": false, "typeface": "didot"], "device": ["ledAvailable": true]])
        _ = try await send(server, "PUT", "/layout", body: ["pages": try pagesJSON([.desk()]), "preferences": ["typeface": "sfMono"]])
        let (_, payload) = try await send(server, "GET", "/layout")
        let preferences = try XCTUnwrap(payload["preferences"] as? JSON)
        XCTAssertEqual(preferences["answerHere"] as? Bool, false)
        XCTAssertEqual(preferences["typeface"] as? String, "sfMono")
        XCTAssertEqual((payload["device"] as? JSON)?["ledAvailable"] as? Bool, true)
        XCTAssertEqual(LayoutStore(file: file).preferences, StandPreferences(answerHere: false, typeface: "sfMono"))
        let broken = try await send(server, "PUT", "/layout", body: ["pages": try pagesJSON([.desk()]), "preferences": ["answerHere": "ja"]]).0
        XCTAssertEqual(broken, 400)
    }

    func testMacPreferenceEditsBumpTheRevisionOnlyOnChange() throws {
        let store = LayoutStore(file: file)
        try store.replace([.desk()])
        store.updatePreferences { $0.ledAlerts = true }
        store.updatePreferences { $0.ledAlerts = true }
        XCTAssertEqual(store.revision, 2)
        XCTAssertEqual(LayoutStore(file: file).preferences.ledAlerts, true)
    }

    func testOtherPortsGetTheirOwnStore() {
        XCTAssertEqual(LayoutStore.file(forPort: 7420).lastPathComponent, "layout.json")
        XCTAssertEqual(LayoutStore.file(forPort: 7421).lastPathComponent, "layout-7421.json")
    }

    func testRejectsMalformedPages() async throws {
        let server = makeServer()
        let missing = try await send(server, "PUT", "/layout", body: ["nope": 1]).0
        let unknownWidget = try await send(server, "PUT", "/layout", body: ["pages": [["id": UUID().uuidString, "name": "x", "style": ["dimmed": false], "items": [["id": UUID().uuidString, "widget": "toaster", "frame": ["x": 0, "y": 0, "w": 1, "h": 1]]]]]]).0
        XCTAssertEqual([missing, unknownWidget], [400, 400])
        XCTAssertEqual(server.layout.revision, 0)
    }

    func testSnapshotCarriesRevision() async throws {
        let server = makeServer()
        _ = try await send(server, "PUT", "/layout", body: ["pages": try pagesJSON([.desk()])])
        let (status, snapshot) = try await send(server, "GET", "/snapshot")
        XCTAssertEqual(status, 200)
        XCTAssertEqual(snapshot["layoutRevision"] as? Int, 1)
    }

    func testPersistsAcrossRestart() async throws {
        let pages = [StandPage.nightstand()]
        _ = try await send(makeServer(), "PUT", "/layout", body: ["pages": try pagesJSON(pages)])
        let restarted = LayoutStore(file: file)
        XCTAssertEqual(restarted.revision, 1)
        XCTAssertEqual(restarted.pages, pages)
    }

    func testEditorUpdateSkipsNoOps() throws {
        let store = LayoutStore(file: file)
        try store.replace([.desk()])
        store.update { _ in }
        XCTAssertEqual(store.revision, 1)
        store.update { $0[0].name = "Büro" }
        XCTAssertEqual(store.revision, 2)
        XCTAssertEqual(LayoutStore(file: file).pages.first?.name, "Büro")
    }
}
