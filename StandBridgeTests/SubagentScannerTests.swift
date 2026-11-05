import XCTest
@testable import StandBridge

@MainActor
final class SubagentScannerTests: XCTestCase {
    private var dir: URL!
    private var agents: URL!
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        agents = dir.appending(path: "projects/-x-app/s1/subagents")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appending(path: "sessions"), withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testProjectNameReplacesEveryNonAlphanumeric() {
        XCTAssertEqual(SubagentScanner.projectName(for: "/Users/max.muster/dev/lab73/other/duostand"), "-Users-max-muster-dev-lab73-other-duostand")
        XCTAssertEqual(SubagentScanner.projectName(for: "/Users/max.muster/dev/core-app/.claude/worktrees/zen-curran-139d2c"),
                       "-Users-max-muster-dev-core-app--claude-worktrees-zen-curran-139d2c")
    }

    func testScanDerivesStateActivityAndNesting() async throws {
        let now = start.addingTimeInterval(600)
        try agent("a1", meta: ["description": "Build widget", "spawnDepth": 1, "requestShape": "background", "spawnedWithWorktree": true],
                  lines: [prompt("Bau das"), toolUse("Bash", ["command": "cd /x && xcodebuild test", "description": "Run Mac tests"])],
                  created: start, modified: now.addingTimeInterval(-5))
        try agent("a2", meta: ["description": "Research trains", "finished": true],
                  lines: [prompt("Recherche"), toolUse("SubagentHandback", ["message": "## **Fertig:** ÖBB geht\n\nDetails"]), handbackResult()],
                  created: start, modified: now.addingTimeInterval(-60))
        try agent("a3", meta: ["description": "Stopped one", "stoppedByUser": true], lines: [prompt("x"), toolUse("Read", ["file_path": "/x/a.swift"])],
                  created: start, modified: now.addingTimeInterval(-30))
        try agent("a4", meta: ["description": "Broken one"], lines: [prompt("x"), apiError()], created: start, modified: now.addingTimeInterval(-20))
        try agent("a5", meta: ["description": "Nested fork", "agentType": "fork", "spawnDepth": 2, "parentAgentId": "a1"],
                  lines: [prompt("x"), toolUse("Edit", ["file_path": "/x/DuoStand/NTSWidget.swift"]), toolResult()],
                  created: start.addingTimeInterval(60), modified: now)
        try agent("a6", meta: ["description": "Long ago", "finished": true], lines: [prompt("x"), finalText("Erledigt.")],
                  created: start.addingTimeInterval(-7200), modified: start.addingTimeInterval(-5000))
        try agent("a7", meta: ["description": "Orphan"], lines: [prompt("x"), toolUse("Grep", ["pattern": "TODO"])],
                  created: start.addingTimeInterval(-900), modified: start.addingTimeInterval(-800))

        let scanner = SubagentScanner(projectsDir: dir.appending(path: "projects"))
        let reports = await scanner.scan([.init(id: "s1", cwd: "/x/app", startedAt: start)], now: now)
        let report = try XCTUnwrap(reports["s1"])

        XCTAssertEqual(report.agents.map(\.id), ["a1", "a5", "a4", "a3", "a2", "a7"])
        XCTAssertEqual(report.older, 1)
        let byId = Dictionary(uniqueKeysWithValues: report.agents.map { ($0.id, $0) })
        XCTAssertEqual(byId["a1"]?.state, .running)
        XCTAssertEqual(byId["a1"]?.activity, "Bash: Run Mac tests")
        XCTAssertEqual(byId["a1"]?.background, true)
        XCTAssertEqual(byId["a1"]?.worktree, true)
        XCTAssertEqual(byId["a5"]?.state, .running)
        XCTAssertEqual(byId["a5"]?.activity, "Edit NTSWidget.swift")
        XCTAssertEqual(byId["a5"]?.depth, 2)
        XCTAssertEqual(byId["a5"]?.parentId, "a1")
        XCTAssertEqual(byId["a2"]?.state, .done)
        XCTAssertEqual(byId["a2"]?.summary, "Fertig: ÖBB geht")
        XCTAssertEqual(byId["a3"]?.state, .stopped)
        XCTAssertEqual(byId["a4"]?.state, .failed)
        XCTAssertEqual(byId["a4"]?.summary, "API Error: 529 overloaded")
        XCTAssertEqual(byId["a7"]?.state, .stopped)
        XCTAssertEqual(byId["a7"]?.activity, "Grep: TODO")
    }

    func testTranscriptWithoutFinishedFlagEndsWithFinalTextOrInterruption() async throws {
        let now = start.addingTimeInterval(600)
        try agent("b1", meta: ["description": "Old style"], lines: [prompt("x"), toolUse("Read", ["file_path": "/x/a.swift"]), toolResult(), finalText("Alles erledigt.\nMehr")],
                  created: start, modified: now.addingTimeInterval(-10))
        try agent("b2", meta: ["description": "Interrupted"], lines: [prompt("x"), toolUse("Bash", ["command": "sleep 100"]), prompt("[Request interrupted by user]")],
                  created: start, modified: now.addingTimeInterval(-10))
        try agent("b3", meta: ["description": "Resumed", "finished": true], lines: [prompt("x"), finalText("Fertig."), prompt("Noch was"), toolUse("Glob", ["pattern": "*.swift"])],
                  created: start, modified: now.addingTimeInterval(-10), metaModified: now.addingTimeInterval(-300))
        let scanner = SubagentScanner(projectsDir: dir.appending(path: "projects"))
        let reports = await scanner.scan([.init(id: "s1", cwd: "/x/app", startedAt: start)], now: now)
        let report = try XCTUnwrap(reports["s1"])
        let byId = Dictionary(uniqueKeysWithValues: report.agents.map { ($0.id, $0) })
        XCTAssertEqual(byId["b1"]?.state, .done)
        XCTAssertEqual(byId["b1"]?.summary, "Alles erledigt.")
        XCTAssertEqual(byId["b1"]?.activity, "Read a.swift")
        XCTAssertEqual(byId["b2"]?.state, .stopped)
        XCTAssertEqual(byId["b3"]?.state, .running)
        XCTAssertEqual(byId["b3"]?.activity, "Glob: *.swift")
    }

    func testTailReaderReachesPastHugeToolResults() throws {
        let huge = String(repeating: "x", count: 300_000)
        try agent("c1", meta: ["description": "Reader"], lines: [prompt("x"), toolUse("Read", ["file_path": "/x/Big.swift"]), toolResult(huge)],
                  created: start, modified: start)
        let file = agents.appending(path: "agent-c1.jsonl")
        let size = try XCTUnwrap(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let tail = SubagentScanner.readTail(of: file, size: size)
        XCTAssertNil(tail.ending)
        XCTAssertEqual(tail.activity, "Read Big.swift")
    }

    func testScanFindsSessionInOtherProjectFolderAndPicksUpChanges() async throws {
        try agent("d1", meta: ["description": "Moved"], lines: [prompt("x"), toolUse("Bash", ["command": "swift build"])], created: start, modified: start)
        let scanner = SubagentScanner(projectsDir: dir.appending(path: "projects"))
        let session = SubagentScanner.SessionRef(id: "s1", cwd: "/somewhere/else")
        let first = await scanner.scan([session], now: start.addingTimeInterval(5))["s1"]
        XCTAssertEqual(first?.agents.first?.activity, "Bash: swift build")
        try agent("d1", meta: ["description": "Moved"], lines: [prompt("x"), toolUse("Bash", ["command": "swift build"]), toolResult(), toolUse("Write", ["file_path": "/y/Out.swift"])],
                  created: start, modified: start.addingTimeInterval(8))
        let second = await scanner.scan([session], now: start.addingTimeInterval(10))["s1"]
        XCTAssertEqual(second?.agents.first?.activity, "Write Out.swift")
    }

    func testBoardSnapshotCarriesSubagentsPerSession() async throws {
        let now = Date.now
        try write(["pid": Int(getpid()), "sessionId": "s1", "cwd": "/x/app", "name": "Fix", "status": "idle",
                   "startedAt": (now.timeIntervalSince1970 - 3600) * 1000], to: "sessions/1.json")
        try agent("e1", meta: ["description": "Running helper"], lines: [prompt("x"), toolUse("Bash", ["command": "make"])],
                  created: now.addingTimeInterval(-60), modified: now.addingTimeInterval(-2))
        try agent("e2", meta: ["description": "Ancient", "finished": true], lines: [prompt("x"), finalText("ok")],
                  created: now.addingTimeInterval(-3500), modified: now.addingTimeInterval(-3400))
        let board = Board(claudeDir: dir)
        await board.refreshSubagents()
        let session = try XCTUnwrap((board.snapshot(standAnswers: false)["sessions"] as? [JSON])?.first)
        let listed = try XCTUnwrap(session["subagents"] as? [JSON])
        XCTAssertEqual(listed.map { $0["id"] as? String }, ["e1"])
        XCTAssertEqual(listed.first?["state"] as? String, "running")
        XCTAssertEqual(listed.first?["activity"] as? String, "Bash: make")
        XCTAssertEqual(session["subagentsOlder"] as? Int, 1)
        XCTAssertEqual(try XCTUnwrap(session["startedAt"] as? Double), now.timeIntervalSince1970 - 3600, accuracy: 1)
        XCTAssertNotNil(try? JSONSerialization.data(withJSONObject: session))
    }

    private func agent(_ id: String, meta: JSON, lines: [JSON], created: Date, modified: Date, metaModified: Date? = nil) throws {
        let transcript = agents.appending(path: "agent-\(id).jsonl")
        let metaFile = agents.appending(path: "agent-\(id).meta.json")
        let body = try lines.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }.joined(separator: "\n") + "\n"
        try Data(body.utf8).write(to: transcript)
        try JSONSerialization.data(withJSONObject: meta).write(to: metaFile)
        try FileManager.default.setAttributes([.creationDate: created, .modificationDate: modified], ofItemAtPath: transcript.path)
        try FileManager.default.setAttributes([.modificationDate: metaModified ?? modified], ofItemAtPath: metaFile.path)
    }

    private func write(_ json: JSON, to path: String) throws {
        try JSONSerialization.data(withJSONObject: json).write(to: dir.appending(path: path))
    }

    private func prompt(_ text: String) -> JSON {
        ["type": "user", "message": ["role": "user", "content": text]]
    }

    private func toolUse(_ name: String, _ input: JSON) -> JSON {
        ["type": "assistant", "message": ["role": "assistant", "stop_reason": "tool_use",
                                          "content": [["type": "tool_use", "id": "t", "name": name, "input": input]]]]
    }

    private func toolResult(_ text: String = "ok") -> JSON {
        ["type": "user", "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "t", "content": text]]]]
    }

    private func handbackResult() -> JSON {
        ["type": "user", "toolEndsTurn": true, "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "t", "content": "delivered"]]]]
    }

    private func finalText(_ text: String) -> JSON {
        ["type": "assistant", "message": ["role": "assistant", "stop_reason": "end_turn", "content": [["type": "text", "text": text]]]]
    }

    private func apiError() -> JSON {
        ["type": "assistant", "isApiErrorMessage": true,
         "message": ["role": "assistant", "stop_reason": "stop_sequence", "model": "<synthetic>", "content": [["type": "text", "text": "API Error: 529 overloaded"]]]]
    }
}
