import XCTest
@testable import Lightstack

final class ExerciseOrderingTests: XCTestCase {

    private let workoutId = UUID()

    private func ex(_ name: String, _ idx: Int, group: UUID? = nil) -> Exercise {
        Exercise.create(
            workoutId: workoutId, name: name, muscleGroup: "Chest", orderIndex: idx,
            targetSets: 3, targetReps: "10", targetRir: nil, restSeconds: nil, coachNote: nil,
            supersetGroupId: group
        )
    }

    private func names(_ list: [Exercise]) -> [String] { list.map(\.name) }

    func testUnitsTreatSupersetAsOneRow() {
        let g = UUID()
        let list = [ex("A", 0), ex("B", 1, group: g), ex("C", 2, group: g), ex("D", 3)]
        let units = ExerciseOrdering.units(from: list)
        XCTAssertEqual(units.count, 3)
        XCTAssertEqual(units[1], [list[1].id, list[2].id])
    }

    func testReorderMovesWholeSupersetAndRenumbers() {
        let g = UUID()
        let list = [ex("A", 0), ex("B", 1, group: g), ex("C", 2, group: g), ex("D", 3)]
        let units = ExerciseOrdering.units(from: list)
        let result = ExerciseOrdering.reordered(list, unitOrder: [units[1], units[0], units[2]])
        XCTAssertEqual(names(result), ["B", "C", "A", "D"])
        XCTAssertEqual(result.map(\.orderIndex), [0, 1, 2, 3])
        XCTAssertTrue(SupersetGroup.isValid(groupId: g, in: result))
    }

    func testReorderKeepsSupersetContiguousWhenMovedToEnd() {
        let g = UUID()
        let list = [ex("A", 0, group: g), ex("B", 1, group: g), ex("C", 2), ex("D", 3)]
        let units = ExerciseOrdering.units(from: list)
        let result = ExerciseOrdering.reordered(list, unitOrder: [units[1], units[2], units[0]])
        XCTAssertEqual(names(result), ["C", "D", "A", "B"])
        XCTAssertTrue(SupersetGroup.isValid(groupId: g, in: result))
    }

    func testReorderAppendsExercisesMissingFromOrder() {
        let list = [ex("A", 0), ex("B", 1), ex("C", 2)]
        let result = ExerciseOrdering.reordered(list, unitOrder: [[list[2].id]])
        XCTAssertEqual(names(result), ["C", "A", "B"])
    }

    func testInsertAfterCurrentUnit() {
        let list = [ex("A", 0), ex("B", 1), ex("C", 2)]
        let result = ExerciseOrdering.inserting(ex("N", 99), afterUnit: 0, in: list)
        XCTAssertEqual(names(result), ["A", "N", "B", "C"])
        XCTAssertEqual(result.map(\.orderIndex), [0, 1, 2, 3])
    }

    func testInsertAfterSupersetGoesAfterWholeGroup() {
        let g = UUID()
        let list = [ex("A", 0), ex("B", 1, group: g), ex("C", 2, group: g), ex("D", 3)]
        let result = ExerciseOrdering.inserting(ex("N", 99), afterUnit: 1, in: list)
        XCTAssertEqual(names(result), ["A", "B", "C", "N", "D"])
        XCTAssertTrue(SupersetGroup.isValid(groupId: g, in: result))
    }

    func testInsertAfterLastAndOutOfRangeAppends() {
        let list = [ex("A", 0), ex("B", 1)]
        XCTAssertEqual(names(ExerciseOrdering.inserting(ex("N", 9), afterUnit: 1, in: list)), ["A", "B", "N"])
        XCTAssertEqual(names(ExerciseOrdering.inserting(ex("N", 9), afterUnit: 7, in: list)), ["A", "B", "N"])
    }

    func testHistoryExercisesDedupeCaseInsensitivelyKeepingMostRecent() {
        let rows = [("Bench Press", "Chest"), ("bench press", "Other"), ("  ", "X"), ("Squat", "")]
        let result = HistoryExercise.distinct(rows)
        XCTAssertEqual(result.map(\.name), ["Bench Press", "Squat"])
        XCTAssertEqual(result[0].muscleGroup, "Chest")
        XCTAssertEqual(result[1].muscleGroup, "Other")
    }

    func testHistoryExerciseSearchFilter() {
        let items = HistoryExercise.distinct([("Bench Press", "Chest"), ("Squat", "Legs")])
        XCTAssertEqual(HistoryExercise.filtered(items, search: "BENCH").map(\.name), ["Bench Press"])
        XCTAssertEqual(HistoryExercise.filtered(items, search: "").count, 2)
        XCTAssertTrue(HistoryExercise.filtered(items, search: "zzz").isEmpty)
    }

    func testHistoryWorkoutNamesExcludeSplitDaysCaseInsensitively() {
        let result = HistoryWorkoutNames.distinct(
            ["Arm Day", "push", "Arm day", " Legs ", "Chest & Back", ""],
            excluding: ["Push", "Pull", "Legs"]
        )
        XCTAssertEqual(result, ["Arm Day", "Chest & Back"])
    }
}
