import AppKit
import XCTest
@testable import StandBridge

@MainActor
final class MacReplyTests: XCTestCase {
    private final class FakeDesk: ReplyDesk {
        static let image = NSPasteboard.PasteboardType.png
        var canPaste = true
        var clipboard: ClipboardSnapshot = [[.string: Data("vorher".utf8), FakeDesk.image: Data([1, 2])]]
        var focusOutcome = WindowFocus.Outcome.window
        var frontmost = true
        var readyForInput = true
        var pasted = 0

        var text: String? { clipboard.first?[.string].map { String(decoding: $0, as: UTF8.self) } }

        func snapshotClipboard() -> ClipboardSnapshot { clipboard }
        func restoreClipboard(_ snapshot: ClipboardSnapshot) { clipboard = snapshot }
        func copy(_ text: String) { clipboard = [[.string: Data(text.utf8)]] }
        func focus(_ entry: JSON) async -> WindowFocus.Outcome { focusOutcome }
        func isFrontmost(_ entry: JSON) async -> Bool { frontmost }
        func isReadyForInput(_ entry: JSON) async -> Bool { readyForInput }
        func pasteAndSubmit() { pasted += 1 }
    }

    func testSwitchOffOnlyCopies() async {
        let desk = FakeDesk()
        let result = await MacReply.send("Ja", to: [:], via: desk, direct: false)
        XCTAssertEqual(desk.pasted, 0)
        XCTAssertEqual(desk.text, "Ja")
        XCTAssertEqual(result["sent"] as? Bool, false)
        XCTAssertEqual(result["copied"] as? Bool, true)
    }

    func testMissingAccessibilityFallsBackToClipboard() async {
        let desk = FakeDesk()
        desk.canPaste = false
        let result = await MacReply.send("Ja", to: [:], via: desk, direct: true)
        XCTAssertEqual(desk.pasted, 0)
        XCTAssertEqual(result["copied"] as? Bool, true)
    }

    func testWrongWindowOrAppDoesNotPaste() async {
        let onlyApp = FakeDesk()
        onlyApp.focusOutcome = .app
        let notFront = FakeDesk()
        notFront.frontmost = false
        let noTextField = FakeDesk()
        noTextField.readyForInput = false
        _ = await MacReply.send("Ja", to: [:], via: onlyApp, direct: true)
        _ = await MacReply.send("Ja", to: [:], via: notFront, direct: true)
        let result = await MacReply.send("Ja", to: [:], via: noTextField, direct: true)
        XCTAssertEqual(onlyApp.pasted + notFront.pasted + noTextField.pasted, 0)
        XCTAssertEqual(result["copied"] as? Bool, true)
    }

    func testDirectSendPastesOnceAndRestoresWholeClipboard() async {
        let desk = FakeDesk()
        let before = desk.clipboard
        let result = await MacReply.send("Ja", to: [:], via: desk, direct: true)
        XCTAssertEqual(desk.pasted, 1)
        XCTAssertEqual(desk.clipboard, before)
        XCTAssertEqual(desk.clipboard.first?[FakeDesk.image], Data([1, 2]))
        XCTAssertEqual(result["sent"] as? Bool, true)
    }

    func testUnknownProcessIsNeverForegroundOnTerminal() {
        XCTAssertFalse(WindowFocus.isForegroundOnTerminal(-1))
    }

    func testTokenIs256BitAndReplacesLegacyToken() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "token")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "bbde706d".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(BridgeIdentity.isLegacyToken(at: file))
        let token = try BridgeIdentity.loadToken(at: file)
        XCTAssertEqual(token.count, 64)
        XCTAssertTrue(token.allSatisfy(\.isHexDigit))
        XCTAssertFalse(BridgeIdentity.isLegacyToken(at: file))
        XCTAssertEqual(try BridgeIdentity.loadToken(at: file), token)
        XCTAssertNotEqual(try BridgeIdentity.randomToken(), try BridgeIdentity.randomToken())
    }
}
