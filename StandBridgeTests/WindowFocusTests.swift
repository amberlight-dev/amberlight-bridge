import XCTest
@testable import StandBridge

@MainActor
final class WindowFocusTests: XCTestCase {
    private func processArguments(argv: [String], env: [String]) -> [UInt8] {
        var raw = withUnsafeBytes(of: Int32(argv.count).littleEndian, Array.init)
        raw += Array("/usr/local/bin/claude".utf8) + [0, 0, 0]
        for string in argv + env { raw += Array(string.utf8) + [0] }
        return raw + [0]
    }

    func testReadsInheritedBundleIdFromEnvironment() {
        let raw = processArguments(argv: ["claude", "--resume"], env: ["TERM=xterm", "__CFBundleIdentifier=dev.herdr.app"])
        XCTAssertEqual(WindowFocus.inheritedValue("__CFBundleIdentifier", inProcessArguments: raw), "dev.herdr.app")
    }

    func testIgnoresLookalikeArgument() {
        let raw = processArguments(argv: ["claude", "__CFBundleIdentifier=evil"], env: ["TERM=xterm"])
        XCTAssertNil(WindowFocus.inheritedValue("__CFBundleIdentifier", inProcessArguments: raw))
    }

    func testIgnoresTruncatedBuffer() {
        XCTAssertNil(WindowFocus.inheritedValue("__CFBundleIdentifier", inProcessArguments: [1, 0]))
    }

    func testHintsPreferSessionNameThenPathThenRepo() {
        let cwd = NSHomeDirectory() + "/Development/duo-stand"
        let hints = WindowFocus.windowHints(for: ["name": "Fix login", "cwd": cwd])
        XCTAssertEqual(hints, ["Fix login", cwd, "~/Development/duo-stand", "duo-stand"])
    }

    func testHintsSkipEmptyAndRootValues() {
        XCTAssertEqual(WindowFocus.windowHints(for: ["name": "", "cwd": "/"]), [])
        XCTAssertEqual(WindowFocus.windowHints(for: ["cwd": NSHomeDirectory()]), [NSHomeDirectory(), (NSHomeDirectory() as NSString).lastPathComponent])
    }

    func testPicksWindowByStrongestHint() {
        let titles = ["duo-stand – README.md", "kirk – Main.kt", "✳ fix login"]
        XCTAssertEqual(WindowFocus.bestWindowIndex(titles: titles, hints: ["Fix login", "duo-stand"]), 2)
        XCTAssertEqual(WindowFocus.bestWindowIndex(titles: titles, hints: ["Nope", "duo-stand"]), 0)
        XCTAssertNil(WindowFocus.bestWindowIndex(titles: titles, hints: ["other"]))
    }
}
