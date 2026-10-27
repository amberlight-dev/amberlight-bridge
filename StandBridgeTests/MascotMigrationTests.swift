import XCTest
@testable import StandBridge

@MainActor
final class MascotMigrationTests: XCTestCase {
    func testSavedLayoutWithLegacyMascotLoadsAndRewritesTheNewName() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "mascot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "layout.json")
        let page = StandPage(name: "Start", items: [PlacedWidget(widget: .mascot, frame: GridRect(x: 0, y: 0, w: 2, h: 1))])
        let pages = String(decoding: try JSONEncoder().encode([page]), as: UTF8.self)
        let legacy = #"{"revision":3,"pages":"# + pages.replacingOccurrences(of: #""mascot""#, with: #""clawd""#) + "}"
        XCTAssertTrue(legacy.contains("clawd"))
        try Data(legacy.utf8).write(to: file)

        let store = LayoutStore(file: file)

        XCTAssertEqual(store.revision, 3)
        XCTAssertEqual(store.pages.first?.items.first?.widget, .mascot)
        try store.replace(store.pages)
        let saved = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(saved.contains(#""mascot""#))
        XCTAssertFalse(saved.contains("clawd"))
    }
}
