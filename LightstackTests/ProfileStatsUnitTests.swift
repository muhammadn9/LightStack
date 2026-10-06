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

    // MARK: - Top lifts (one best per exercise)

    private func pr(_ name: String, _ weight: Double, _ reps: Int, daysAgo: Double) -> PersonalRecord {
        var r = PersonalRecord.create(userId: UUID(), exerciseName: name, weightLbs: weight, reps: reps, workoutId: nil)
        r.dateAchieved = created.addingTimeInterval(-daysAgo * 86_400)
        return r
    }

    func testNameVariantsShareAKey() {
        let key = PersonalRecordsListView.exerciseKey
        XCTAssertEqual(key("Alternating hammer curl"), key("Alternating Hammer Curl"))
        XCTAssertEqual(key("Bulgarian Split Squat"), key("Bulgarian split squats"))
        XCTAssertEqual(key("Cable lat pull down machine"), key("Cable Lat  pull-down machine"))
        XCTAssertEqual(key("DB Bench Press"), key("Dumbbell bench press"))
        XCTAssertNotEqual(key("Barbell curl"), key("Dumbbell curl"))
        XCTAssertEqual(key("Cross"), "cross")  // "-ss" words are not singularised
    }

    func testBestPerExerciseKeepsOnlyTheMaxUnderTheLatestName() {
        let records = [
            pr("Bulgarian split squats", 30, 8, daysAgo: 40),
            pr("Bulgarian Split Squat", 35, 7, daysAgo: 5),
            pr("Barbell Bench Press", 150, 8, daysAgo: 10)
        ]
        let best = PersonalRecordsListView.bestPerExercise(records)
        XCTAssertEqual(best.count, 2)
        let squat = best.first { $0.exerciseName.hasPrefix("Bulgarian") }
        XCTAssertEqual(squat?.weightLbs, 35)
        XCTAssertEqual(squat?.exerciseName, "Bulgarian Split Squat")
        let sorted = PersonalRecordsListView.sorted(best, by: .heaviest)
        XCTAssertEqual(sorted.first?.exerciseName, "Barbell Bench Press")
    }
}
