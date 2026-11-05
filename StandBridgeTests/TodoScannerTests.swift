import XCTest
@testable import StandBridge

final class TodoScannerTests: XCTestCase {
    private func line(_ blocks: String) -> Data {
        Data(#"{"type":"assistant","message":{"content":[\#(blocks)]}}"#.utf8)
    }

    func testLatestTodoWriteWins() {
        let old = line(#"{"type":"tool_use","name":"TodoWrite","input":{"todos":[{"content":"A","status":"pending","activeForm":"Doing A"}]}}"#)
        let new = line(#"{"type":"tool_use","name":"TodoWrite","input":{"todos":[{"content":"A","status":"completed","activeForm":"Doing A"},{"content":"B","status":"in_progress","activeForm":"Doing B"}]}}"#)
        let todos = TodoScanner.latestTodos(newestFirst: [new, old])
        XCTAssertEqual(todos?.map(\.state), [.completed, .inProgress])
        XCTAssertEqual(todos?.last?.activeForm, "Doing B")
    }

    func testIgnoresOtherToolsAndReturnsNilWithoutList() {
        let other = line(#"{"type":"tool_use","name":"Bash","input":{"command":"ls"}}"#)
        XCTAssertNil(TodoScanner.latestTodos(newestFirst: [other]))
    }

    func testUnknownStatusFallsBackToPending() {
        let write = line(#"{"type":"tool_use","name":"TodoWrite","input":{"todos":[{"content":"A","status":"weird"}]}}"#)
        XCTAssertEqual(TodoScanner.latestTodos(newestFirst: [write])?.first?.state, .pending)
    }
}
