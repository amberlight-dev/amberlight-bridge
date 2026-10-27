import XCTest
@testable import StandBridge

@MainActor
final class WindowPrimerTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: hour, minute: minute))!
    }

    private func due(_ now: Date, lastRun: Date? = nil, resetsAt: Date? = nil, used: Double = 0.2) -> Bool {
        let window: JSON? = resetsAt.map { ["resetsAt": $0.timeIntervalSince1970, "used": used] }
        return WindowPrimer.isDue(now: now, minute: 7 * 60, lastRun: lastRun, sessionWindow: window, calendar: calendar)
    }

    func testPrimesOnlyBetweenStartAndThreeHoursLater() {
        XCTAssertFalse(due(at(6, 59)))
        XCTAssertTrue(due(at(7)))
        XCTAssertTrue(due(at(9, 59)))
        XCTAssertFalse(due(at(10)))
    }

    func testSkipsWhenAlreadyRunTodayOrWindowActive() {
        XCTAssertFalse(due(at(8), lastRun: at(7, 1)))
        XCTAssertTrue(due(at(8), lastRun: at(7).addingTimeInterval(-86_400)))
        XCTAssertFalse(due(at(8), resetsAt: at(9)))
        XCTAssertTrue(due(at(8), resetsAt: at(7, 30)))
        XCTAssertTrue(due(at(8), resetsAt: at(9), used: 0))
    }
}
