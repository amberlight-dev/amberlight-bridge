import XCTest
@testable import StandBridge

@MainActor
final class CodexUsageTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private static func tokenCount(_ rateLimits: Any, at time: String = "2026-10-13T06:38:33.214Z") -> String {
        let line: JSON = ["timestamp": time, "type": "event_msg",
                          "payload": ["type": "token_count", "info": NSNull(), "rate_limits": rateLimits]]
        return String(data: try! JSONSerialization.data(withJSONObject: line), encoding: .utf8)!
    }

    private static let limits: JSON = [
        "limit_id": "codex", "limit_name": NSNull(),
        "primary": ["used_percent": 42.5, "window_minutes": 300, "resets_at": 1_794_398_203],
        "secondary": ["used_percent": 12, "window_minutes": 10080, "resets_at": 1_794_900_000],
        "credits": ["has_credits": false, "unlimited": false, "balance": NSNull()], "plan_type": "plus",
    ]

    @discardableResult
    private func rollout(_ day: String, _ name: String, _ lines: [String], modified: Date) throws -> URL {
        let folder = dir.appending(path: "sessions/\(day)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "rollout-\(name).jsonl")
        try Data(lines.joined(separator: "\n").utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        return file
    }

    func testReadsLatestRateLimitsFromNewestRollout() throws {
        let meta = #"{"timestamp":"2026-10-13T06:37:54Z","type":"session_meta","payload":{"id":"x","cwd":"/tmp"}}"#
        var older = Self.limits
        older["primary"] = ["used_percent": 5, "window_minutes": 300, "resets_at": 1_794_398_203]
        try rollout("2026/10/12", "a", [meta, Self.tokenCount(older)], modified: Date(timeIntervalSince1970: 1000))
        try rollout("2026/10/13", "b", [meta, Self.tokenCount(older), Self.tokenCount(Self.limits), "{broken", ""],
                    modified: Date(timeIntervalSince1970: 2000))

        let codex = try XCTUnwrap(CodexUsage.provider(in: dir.appending(path: "sessions")))
        XCTAssertEqual(codex["id"] as? String, "codex")
        XCTAssertEqual(codex["name"] as? String, "Codex")
        XCTAssertEqual(codex["updatedAt"] as? Double, 2000)
        let windows = try XCTUnwrap(codex["windows"] as? [JSON])
        XCTAssertEqual(windows.map { $0["minutes"] as? Int }, [300, 10080])
        XCTAssertEqual(windows.map { $0["used"] as? Double }, [0.425, 0.12])
        XCTAssertEqual(windows[0]["resetsAt"] as? Double, 1_794_398_203)
    }

    func testFallsBackToOlderRolloutWithoutRateLimits() throws {
        try rollout("2026/10/12", "a", [Self.tokenCount(Self.limits)], modified: Date(timeIntervalSince1970: 1000))
        try rollout("2026/10/13", "sub", [Self.tokenCount(NSNull())], modified: Date(timeIntervalSince1970: 2000))
        let windows = CodexUsage.provider(in: dir.appending(path: "sessions"))?["windows"] as? [JSON]
        XCTAssertEqual(windows?.first?["used"] as? Double, 0.425)
    }

    func testIgnoresOtherLimitBucketsAndMissingWindows() {
        var other = Self.limits
        other["limit_id"] = "codex_other"
        let onlyOther = Data(Self.tokenCount(other).utf8)
        XCTAssertNil(CodexUsage.provider(fromLines: onlyOther, modified: .now))

        let freePlan: JSON = ["primary": ["used_percent": 29, "window_minutes": 43200, "resets_at": 1_794_398_203], "secondary": NSNull()]
        let windows = CodexUsage.provider(fromLines: Data(Self.tokenCount(freePlan).utf8), modified: .now)?["windows"] as? [JSON]
        XCTAssertEqual(windows?.map { $0["minutes"] as? Int }, [43200])
    }

    func testMissingDirectoryHasNoUsage() {
        XCTAssertNil(CodexUsage.provider(in: dir.appending(path: "sessions")))
        XCTAssertNil(CodexUsage.cachedProvider(in: dir.appending(path: "sessions")))
    }

    func testProvidersKeepOrderAndClearExpiredWindows() {
        let claude: JSON = ["id": "claude", "windows": [["minutes": 300, "used": 0.9, "resetsAt": 100.0]]]
        let codex: JSON = ["id": "codex", "windows": [["minutes": 10080, "used": 0.3, "resetsAt": 9_999_999_999.0]]]
        let providers = Usage.providers([claude, nil, codex], now: Date(timeIntervalSince1970: 1_000_000))
        XCTAssertEqual(providers.map { $0["id"] as? String }, ["claude", "codex"])
        let expired = (providers[0]["windows"] as? [JSON])?.first
        XCTAssertEqual(expired?["used"] as? Double, 0)
        XCTAssertTrue(expired?["resetsAt"] is NSNull)
        XCTAssertEqual((providers[1]["windows"] as? [JSON])?.first?["used"] as? Double, 0.3)
    }
}
