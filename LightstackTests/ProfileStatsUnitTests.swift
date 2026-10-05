import XCTest
@testable import Lightstack

final class ProfileStatsUnitTests: XCTestCase {

    private let created = Date(timeIntervalSince1970: 1_000_000)

    func testQuickWorkoutIsNeverZeroMinutes() {
        let m = WorkoutSessionService.durationMinutes(activeSeconds: 20, createdAt: created, now: created.addingTimeInterval(20))
        XCTAssertEqual(m, 1)
    }

    func testPrefersActiveTimerOverCreationTime() {
        // Plan generated an hour before; only 30 active minutes.
        let m = WorkoutSessionService.durationMinutes(activeSeconds: 1800, createdAt: created, now: created.addingTimeInterval(3600))
        XCTAssertEqual(m, 30)
    }

    func testFallsBackToCreationTimeAndRounds() {
        let m = WorkoutSessionService.durationMinutes(activeSeconds: nil, createdAt: created, now: created.addingTimeInterval(95 * 60 + 40))
        XCTAssertEqual(m, 96)
        XCTAssertEqual(WorkoutSessionService.durationMinutes(activeSeconds: 0, createdAt: created, now: created.addingTimeInterval(600)), 10)
    }

    func testEstimatedOneRepMax() {
        XCTAssertEqual(PersonalRecordsListView.estimatedOneRepMax(weight: 135, reps: 6) ?? 0, 162, accuracy: 0.01)
        XCTAssertNil(PersonalRecordsListView.estimatedOneRepMax(weight: 135, reps: 0))
        XCTAssertNil(PersonalRecordsListView.estimatedOneRepMax(weight: 0, reps: 5))
    }
}
