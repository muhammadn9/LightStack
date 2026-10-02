import XCTest
@testable import Lightstack

/// Tests the session -> badge status mapping.
final class StatusBadgeTests: XCTestCase {

    private let dayInSeconds: TimeInterval = 86_400

    func testCompletedTakesPrecedenceOverDate() {
        let past = Date().addingTimeInterval(-5 * dayInSeconds)
        XCTAssertEqual(BadgeStatus(completed: true, date: past), .done)
        XCTAssertEqual(BadgeStatus(completed: true, date: Date()), .done)
    }

    func testTodayIsDetected() {
        XCTAssertEqual(BadgeStatus(completed: false, date: Date()), .today)
    }

    func testPastIncompleteIsMissed() {
        let past = Date().addingTimeInterval(-5 * dayInSeconds)
        XCTAssertEqual(BadgeStatus(completed: false, date: past), .missed)
    }

    func testFutureIncompleteHasNoBadge() {
        let future = Date().addingTimeInterval(5 * dayInSeconds)
        XCTAssertNil(BadgeStatus(completed: false, date: future))
    }

    func testEveryStatusHasANonEmptyLabel() {
        for status in BadgeStatus.allCases {
            XCTAssertFalse(status.label.isEmpty, "\(status) has no label")
        }
    }
}
