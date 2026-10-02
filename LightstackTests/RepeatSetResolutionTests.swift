import XCTest
@testable import Lightstack

final class RepeatSetResolutionTests: XCTestCase {

    private let hint = PreviousSetHint(weightLbs: 135, reps: 8, rir: 1)

    private func resolve(_ weight: String = "", _ reps: String = "", _ rir: String = "",
                         hint: PreviousSetHint?) -> (weight: Double, reps: Int, rir: Int)? {
        ActiveWorkoutViewModel.resolveStrength(weight: weight, reps: reps, rir: rir, previous: hint)
    }

    func testBlankFieldsResolveToHint() {
        let result = resolve(hint: hint)
        XCTAssertEqual(result?.weight, 135)
        XCTAssertEqual(result?.reps, 8)
        XCTAssertEqual(result?.rir, 1)
    }

    func testTypedValuesOverrideHint() {
        let result = resolve("140", "6", "3", hint: hint)
        XCTAssertEqual(result?.weight, 140)
        XCTAssertEqual(result?.reps, 6)
        XCTAssertEqual(result?.rir, 3)
    }

    func testZeroWeightResolvesToZeroWithAndWithoutHint() {
        XCTAssertEqual(resolve("0", "5", hint: hint)?.weight, 0)
        XCTAssertEqual(resolve("0", "5", hint: nil)?.weight, 0)
    }

    func testBodyweightResolvesToZero() {
        XCTAssertEqual(resolve("bw", "5", hint: hint)?.weight, 0)
        XCTAssertEqual(resolve("BW", "5", hint: nil)?.weight, 0)
    }

    func testZeroRepsResolvesToZeroReps() {
        XCTAssertEqual(resolve("100", "0", hint: hint)?.reps, 0)
    }

    func testBlankRepsWithoutHintIsNil() {
        XCTAssertNil(resolve("100", "", hint: nil))
    }

    func testBlankRirWithoutHintDefaultsToTwo() {
        XCTAssertEqual(resolve("100", "5", "", hint: nil)?.rir, 2)
    }

    func testGarbageWeightIsNil() {
        XCTAssertNil(resolve("abc", "5", hint: hint))
    }

    func testSyncPendingSetsCreatesRowForEveryHint() {
        let viewModel = ActiveWorkoutViewModel()
        let exercise = Exercise.create(
            workoutId: UUID(),
            name: "Bench Press",
            muscleGroup: "Chest",
            orderIndex: 0,
            targetSets: 2,
            targetReps: "8",
            targetRir: "2",
            restSeconds: 90,
            coachNote: nil
        )
        let hints = [
            PreviousSetHint(weightLbs: 135, reps: 8, rir: 2),
            PreviousSetHint(weightLbs: 145, reps: 6, rir: 1),
            PreviousSetHint(weightLbs: 0, reps: 5, rir: 0)
        ]
        viewModel.previousHints[exercise.id] = hints
        viewModel.syncPendingSets(for: exercise)

        let rows = viewModel.pendingSets[exercise.id] ?? []
        XCTAssertEqual(rows.count, 3)
        for (i, row) in rows.enumerated() {
            XCTAssertEqual(row.weight, "")
            XCTAssertEqual(row.reps, "")
            XCTAssertEqual(row.rir, "")
            XCTAssertEqual(row.previous, hints[i])
        }
    }
}
