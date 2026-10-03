import XCTest
import CoreData
@testable import Lightstack

/// Restoring a session used to re-save its exercises, adding a full copy on
/// every app relaunch. Saves are now upserts, and a launch-time repair merges
/// copies created before the fix.
final class DuplicateExerciseTests: XCTestCase {

    private var storage: LocalStorageService!
    private var workout: Workout!

    override func setUp() {
        super.setUp()
        storage = LocalStorageService(inMemory: true)
        workout = Workout.create(userId: UUID(), workoutType: "Push", energyLevel: nil, timeAvailableMinutes: nil)
        storage.saveWorkout(workout)
    }

    private func makeExercise() -> Exercise {
        Exercise.create(
            workoutId: workout.id, name: "Smith Machine Chest Press", muscleGroup: "Chest", orderIndex: 0,
            targetSets: 3, targetReps: "5", targetRir: nil, restSeconds: 90, coachNote: nil
        )
    }

    func testSavingSameExercisesTwiceDoesNotDuplicate() {
        let exercise = makeExercise()
        storage.saveExercises([exercise], workoutId: workout.id)
        storage.saveExercises([exercise], workoutId: workout.id)
        XCTAssertEqual(storage.fetchExercises(workoutId: workout.id).count, 1)
    }

    func testSavingSameSetTwiceDoesNotDuplicate() {
        let exercise = makeExercise()
        storage.saveExercises([exercise], workoutId: workout.id)
        let set = WorkoutSet.create(exerciseId: exercise.id, setNumber: 1, weightLbs: 165, reps: 2, rir: 0)
        storage.saveSet(set, exerciseId: exercise.id)
        storage.saveSet(set, exerciseId: exercise.id)
        XCTAssertEqual(storage.fetchSets(exerciseId: exercise.id).count, 1)
    }

    func testRepairMergesExistingDuplicatesAndKeepsTheirSets() {
        let exercise = makeExercise()
        storage.saveExercises([exercise], workoutId: workout.id)
        let set = WorkoutSet.create(exerciseId: exercise.id, setNumber: 1, weightLbs: 165, reps: 2, rir: 0)
        storage.saveSet(set, exerciseId: exercise.id)

        // Recreate the old bug: extra entities sharing the same exercise id,
        // one of them holding a set the first copy doesn't have.
        let context = storage.context
        guard let workoutEntity = storage.fetchWorkout(id: workout.id) else { return XCTFail("no workout") }
        var extraSetEntity: CDWorkoutSet?
        for index in 0..<3 {
            let copy = CDExercise(context: context)
            exercise.applyToCoreData(copy)
            copy.workout = workoutEntity
            if index == 0 {
                let extra = CDWorkoutSet(context: context)
                WorkoutSet.create(exerciseId: exercise.id, setNumber: 2, weightLbs: 180, reps: 2, rir: 0)
                    .applyToCoreData(extra)
                extra.exercise = copy
                extraSetEntity = extra
            }
        }
        try? context.save()
        XCTAssertEqual(storage.fetchExercises(workoutId: workout.id).count, 4)

        XCTAssertEqual(storage.removeDuplicateExercises(), 3)
        let remaining = storage.fetchExercises(workoutId: workout.id)
        XCTAssertEqual(remaining.count, 1)
        let setWeights = (remaining.first?.sets as? Set<CDWorkoutSet> ?? []).map(\.weightLbs).sorted()
        XCTAssertEqual(setWeights, [165, 180])
        XCTAssertNotNil(extraSetEntity)
    }
}
