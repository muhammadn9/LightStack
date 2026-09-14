import XCTest
@testable import Lightstack

/// Tests for HistoryViewModel.filtered(_:by:) and HistoryViewModel.availableTypes(in:).
final class HistoryFilterTests: XCTestCase {

    private func makeWorkout(type: String, date: Date = Date()) -> Workout {
        Workout(
            id: UUID(),
            userId: UUID(),
            localId: nil,
            date: date,
            workoutType: type,
            durationMinutes: nil,
            energyLevel: nil,
            timeAvailableMinutes: nil,
            userNote: nil,
            setupNote: nil,
            aiProgressionNote: nil,
            plannedSessionId: nil,
            syncStatus: .synced,
            createdAt: date
        )
    }

    // MARK: - filtered(_:by:)

    func testFilteredReturnsAllWorkoutsWhenTypeIsNil() {
        let workouts = [makeWorkout(type: "Push"), makeWorkout(type: "Pull"), makeWorkout(type: "Legs")]

        let result = HistoryViewModel.filtered(workouts, by: nil)

        XCTAssertEqual(result.count, 3)
    }

    func testFilteredReturnsOnlyMatchingWorkoutType() {
        let push1 = makeWorkout(type: "Push")
        let pull = makeWorkout(type: "Pull")
        let push2 = makeWorkout(type: "Push")

        let result = HistoryViewModel.filtered([push1, pull, push2], by: "Push")

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.workoutType == "Push" })
    }

    /// The comparison is case-insensitive: stored "push" matches a filter of "Push".
    func testFilteredComparisonIsCaseInsensitive() {
        let workouts = [makeWorkout(type: "push"), makeWorkout(type: "PULL")]

        let result = HistoryViewModel.filtered(workouts, by: "Push")

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.workoutType, "push")
    }

    func testFilteredReturnsEmptyWhenNoMatches() {
        let workouts = [makeWorkout(type: "Push"), makeWorkout(type: "Pull")]

        let result = HistoryViewModel.filtered(workouts, by: "Cardio")

        XCTAssertTrue(result.isEmpty)
    }

    /// "All" is not given special-case treatment by `filtered`; it is compared
    /// like any other string and only matches workouts literally typed "All".
    func testFilteredWithAllStringDoesNotActAsWildcard() {
        let workouts = [makeWorkout(type: "Push"), makeWorkout(type: "Pull")]

        let result = HistoryViewModel.filtered(workouts, by: "All")

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - availableTypes(in:)

    func testAvailableTypesReturnsUniqueSortedTypes() {
        let workouts = [
            makeWorkout(type: "Push"),
            makeWorkout(type: "Pull"),
            makeWorkout(type: "Push"),
            makeWorkout(type: "Legs")
        ]

        let result = HistoryViewModel.availableTypes(in: workouts)

        XCTAssertEqual(result, ["Legs", "Pull", "Push"])
    }

    func testAvailableTypesEmptyForNoWorkouts() {
        XCTAssertEqual(HistoryViewModel.availableTypes(in: []), [])
    }
}
