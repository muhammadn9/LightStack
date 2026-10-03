import XCTest
@testable import Lightstack

final class WorkoutImportDedupeTests: XCTestCase {

    private func date(_ day: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    private func workout(_ name: String, day: Int, hour: Int = 12) -> ImportedWorkout {
        ImportedWorkout(
            date: date(day, hour: hour), name: name, notes: nil,
            exercises: [ImportedExercise(name: "Row", muscleGroup: "Back", notes: nil,
                                         sets: [ImportedSet(weightLbs: 100, reps: 8, rir: nil)])]
        )
    }

    func testSameDayDifferentCaseIsDuplicate() {
        let r = WorkoutImportService.dedupe([workout("Pull ", day: 14, hour: 8)],
                                            existing: [(date: date(14, hour: 20), name: "pull")])
        XCTAssertEqual(r.toImport.count, 0)
        XCTAssertEqual(r.duplicates, 1)
    }

    func testDifferentDayIsNotDuplicate() {
        let r = WorkoutImportService.dedupe([workout("Pull", day: 15)], existing: [(date: date(14), name: "Pull")])
        XCTAssertEqual(r.toImport.count, 1)
        XCTAssertEqual(r.duplicates, 0)
    }

    func testDifferentNameIsNotDuplicate() {
        let r = WorkoutImportService.dedupe([workout("Push", day: 14)], existing: [(date: date(14), name: "Pull")])
        XCTAssertEqual(r.toImport.count, 1)
    }

    func testDuplicatesWithinBatchCollapse() {
        let r = WorkoutImportService.dedupe([workout("Pull", day: 14), workout("PULL", day: 14), workout("Push", day: 14)],
                                            existing: [])
        XCTAssertEqual(r.toImport.map(\.name), ["Pull", "Push"])
        XCTAssertEqual(r.duplicates, 1)
    }
}
