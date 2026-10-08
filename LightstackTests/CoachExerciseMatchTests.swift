import XCTest
@testable import Lightstack

final class CoachExerciseMatchTests: XCTestCase {

    private let workoutId = UUID()

    private func exercises(_ names: [String]) -> [Exercise] {
        names.enumerated().map { index, name in
            Exercise.create(workoutId: workoutId, name: name, muscleGroup: "Chest", orderIndex: index,
                            targetSets: 3, targetReps: "8", targetRir: "2", restSeconds: 90, coachNote: nil)
        }
    }

    func testExactNameWins() {
        let list = exercises(["Bench Press", "Barbell Bench Press"])
        XCTAssertEqual(TodayViewModel.exerciseIndex(named: "barbell bench press", in: list), 1)
    }

    func testShortenedNameMatchesTheOnlyCandidate() {
        let list = exercises(["Barbell Bench Press", "Cable Triceps Pushdown"])
        XCTAssertEqual(TodayViewModel.exerciseIndex(named: "Bench Press", in: list), 0)
    }

    func testCaseAndPluralVariantsMatch() {
        let list = exercises(["Single arm pec fly machine", "Bulgarian split squats"])
        XCTAssertEqual(TodayViewModel.exerciseIndex(named: "Bulgarian Split Squat", in: list), 1)
        XCTAssertEqual(TodayViewModel.exerciseIndex(named: "Single Arm Pec Fly", in: list), 0)
    }

    func testAmbiguousNameMatchesNothing() {
        let list = exercises(["Incline Dumbbell Press", "Flat Dumbbell Press"])
        XCTAssertNil(TodayViewModel.exerciseIndex(named: "Dumbbell Press", in: list))
    }

    func testUnknownNameMatchesNothing() {
        XCTAssertNil(TodayViewModel.exerciseIndex(named: "Leg Press", in: exercises(["Barbell Bench Press"])))
    }

    func testTargetNameOnlyForChangesToExistingExercises() {
        XCTAssertEqual(WorkoutModification.removeExercise(name: "Squat").targetExerciseName, "Squat")
        XCTAssertNil(WorkoutModification.groupSuperset(names: ["A", "B"]).targetExerciseName)
    }
}
