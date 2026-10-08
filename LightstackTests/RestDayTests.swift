import XCTest
import CoreData
@testable import Lightstack

final class RestDayTests: XCTestCase {

    private var storage: LocalStorageService!
    private let userId = UUID()
    private let calendar = Calendar.current

    override func setUp() {
        super.setUp()
        storage = LocalStorageService(inMemory: true)
    }

    private func day(_ offset: Int) -> Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    private func addWorkout(daysAgo: Int) {
        var w = Workout.create(userId: userId, workoutType: "Push", energyLevel: nil, timeAvailableMinutes: nil)
        w.date = calendar.date(byAdding: .hour, value: 12, to: day(-daysAgo)) ?? day(-daysAgo)
        storage.saveWorkout(w)
    }

    func testAddRestDayIsIdempotentPerDay() {
        storage.addRestDay(userId: userId, date: day(0))
        storage.addRestDay(userId: userId, date: calendar.date(byAdding: .hour, value: 9, to: day(0)) ?? day(0))
        XCTAssertEqual(storage.fetchRestDays(userId: userId).count, 1)
        XCTAssertTrue(storage.isRestDay(userId: userId, date: day(0)))
    }

    func testRemoveRestDay() {
        storage.addRestDay(userId: userId, date: day(-1))
        storage.removeRestDay(userId: userId, date: day(-1))
        XCTAssertTrue(storage.fetchRestDays(userId: userId).isEmpty)
        storage.removeRestDay(userId: userId, date: day(-1))   // no-op, no crash
    }

    func testFetchRestDaysInRange() {
        storage.addRestDay(userId: userId, date: day(-10))
        storage.addRestDay(userId: userId, date: day(-2))
        storage.addRestDay(userId: UUID(), date: day(-2))      // another user
        let found = storage.fetchRestDays(userId: userId, in: day(-5)...day(0))
        XCTAssertEqual(found.count, 1)
    }

    func testRestDayBridgesGapInStreak() {
        addWorkout(daysAgo: 0)
        addWorkout(daysAgo: 1)
        addWorkout(daysAgo: 3)
        XCTAssertEqual(storage.countConsecutiveWorkoutDays(userId: userId), 2)
        storage.addRestDay(userId: userId, date: day(-2))
        XCTAssertEqual(storage.countConsecutiveWorkoutDays(userId: userId), 4)
    }

    func testRestOnlyStreak() {
        storage.addRestDay(userId: userId, date: day(-1))
        storage.addRestDay(userId: userId, date: day(-2))
        XCTAssertEqual(storage.countConsecutiveWorkoutDays(userId: userId), 2)
    }

    func testRestDayTodayCounts() {
        addWorkout(daysAgo: 1)
        storage.addRestDay(userId: userId, date: day(0))
        XCTAssertEqual(storage.countConsecutiveWorkoutDays(userId: userId), 2)
    }

    func testStaleRestDayDoesNotStartStreak() {
        storage.addRestDay(userId: userId, date: day(-3))
        XCTAssertEqual(storage.countConsecutiveWorkoutDays(userId: userId), 0)
    }

    func testRestDaysDoNotChangeWorkoutCounts() {
        addWorkout(daysAgo: 0)
        storage.addRestDay(userId: userId, date: day(-1))
        let service = ProgressStatsService(localStorage: storage)
        let snap = service.snapshot(userId: userId)
        XCTAssertEqual(snap.totalWorkouts, 1)
        XCTAssertEqual(snap.streak, 2)
        XCTAssertTrue(snap.restDays.contains(day(-1)))
        XCTAssertEqual(snap.workoutsPerWeek.reduce(0, +), 1)
        XCTAssertEqual(snap.daysTrainedThisWeek <= 1, true)
    }
}
