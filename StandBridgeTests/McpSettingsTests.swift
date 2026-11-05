import XCTest
@testable import StandBridge

@MainActor
final class McpSettingsTests: XCTestCase {
    private static let foreign: JSON = ["numStartups": 3, "mcpServers": ["other": ["type": "stdio", "command": "foo", "args": []]]]
    private let script = "/Applications/Amberlight Bridge.app/Contents/Resources/widgets-mcp.mjs"

    func testInstallDetectRemoveKeepsForeignEntries() {
        XCTAssertEqual(McpSettings.state(Self.foreign, script: script), .missing)
        let installed = McpSettings.installing(Self.foreign, script: script)
        XCTAssertEqual(McpSettings.state(installed, script: script), .installed)
        XCTAssertEqual(McpSettings.installing(installed, script: script) as NSDictionary, installed as NSDictionary)
        XCTAssertEqual(McpSettings.removing(installed) as NSDictionary, Self.foreign as NSDictionary)
    }

    func testMovedAppIsOutdatedAndReinstallFixesPath() {
        let installed = McpSettings.installing([:], script: "/old/widgets-mcp.mjs")
        XCTAssertEqual(McpSettings.state(installed, script: script), .outdated)
        XCTAssertEqual(McpSettings.state(McpSettings.installing(installed, script: script), script: script), .installed)
    }

    func testRemoveLastEntryDropsServersKeyAndConfigHasNoToken() {
        let installed = McpSettings.installing([:], script: script)
        XCTAssertNil(McpSettings.removing(installed)["mcpServers"])
        let text = String(data: try! JSONSerialization.data(withJSONObject: installed), encoding: .utf8)!
        XCTAssertFalse(text.lowercased().contains("token"))
    }

    func testFileRoundTripBacksUpAndNodeLookup() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: ".claude.json")
        try JSONSerialization.data(withJSONObject: Self.foreign).write(to: file)

        XCTAssertNotNil(try ClaudeSettings.update(file) { McpSettings.installing($0, script: script) })
        XCTAssertEqual(McpSettings.state(try ClaudeSettings.read(file), script: script), .installed)
        XCTAssertNil(try ClaudeSettings.update(file, backup: false, McpSettings.removing))
        XCTAssertEqual(try ClaudeSettings.read(file) as NSDictionary, Self.foreign as NSDictionary)

        XCTAssertNil(McpSettings.nodeURL(searching: [dir.path]))
        let node = dir.appending(path: "node")
        FileManager.default.createFile(atPath: node.path, contents: Data(), attributes: [.posixPermissions: 0o755])
        XCTAssertEqual(McpSettings.nodeURL(searching: [dir.path]), node)
    }
}
