import XCTest
import Supabase
@testable import Lightstack

final class WorkoutReplaceTests: XCTestCase {

    private var storage: LocalStorageService!
    private var repo: WorkoutRepository!
    private let userId = UUID()

    override func setUp() {
        super.setUp()
        storage = LocalStorageService(inMemory: true)
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://example.invalid") ?? URL(fileURLWithPath: "/"),
            supabaseKey: "test"
        )
        let supabase = SupabaseService(client: client)
        repo = WorkoutRepository(
            localStorage: storage,
            supabaseService: supabase,
            offlineQueueManager: OfflineQueueManager(supabaseService: supabase)
        )
    }

    private func seed(name: String, exerciseName: String) -> (Workout, Exercise, WorkoutSet) {
        let workout = Workout.create(userId: userId, workoutType: name, energyLevel: nil, timeAvailableMinutes: nil)
        storage.saveWorkout(workout)
        let exercise = Exercise.create(
            workoutId: workout.id, name: exerciseName, muscleGroup: "Chest", orderIndex: 0,
            targetSets: 1, targetReps: "5", targetRir: nil, restSeconds: 90, coachNote: nil
        )
        storage.saveExercises([exercise], workoutId: workout.id)
        let set = WorkoutSet.create(exerciseId: exercise.id, setNumber: 1, weightLbs: 100, reps: 5, rir: nil)
        storage.saveSet(set, exerciseId: exercise.id)
        return (workout, exercise, set)
    }

    func testReplaceSwapsContentsAndLeavesOtherWorkoutsUntouched() {
        let (original, oldEx, oldSet) = seed(name: "Push", exerciseName: "Bench Press")
        let (other, otherEx, otherSet) = seed(name: "Pull", exerciseName: "Row")

        var edited = original
        edited.workoutType = "Push Edited"
        let newEx = Exercise.create(
            workoutId: original.id, name: "Overhead Press", muscleGroup: "Shoulders", orderIndex: 0,
            targetSets: 2, targetReps: "8", targetRir: nil, restSeconds: 90, coachNote: nil
        )
        let s1 = WorkoutSet.create(exerciseId: newEx.id, setNumber: 1, weightLbs: 60, reps: 8, rir: 2)
        let s2 = WorkoutSet.create(exerciseId: newEx.id, setNumber: 2, weightLbs: 65, reps: 6, rir: nil)

        repo.replaceWorkoutContents(edited, exercises: [newEx], sets: [newEx.id: [s1, s2]])

        XCTAssertEqual(storage.fetchWorkout(id: original.id)?.workoutType, "Push Edited")
        let exercises = storage.fetchExercises(workoutId: original.id)
        XCTAssertEqual(exercises.compactMap { $0.id }, [newEx.id])
        XCTAssertFalse(exercises.contains { $0.id == oldEx.id })
        XCTAssertEqual(storage.fetchSets(exerciseId: newEx.id).compactMap { $0.id }, [s1.id, s2.id])
        XCTAssertTrue(storage.fetchSets(exerciseId: oldEx.id).isEmpty)
        _ = oldSet

        XCTAssertEqual(storage.fetchExercises(workoutId: other.id).compactMap { $0.id }, [otherEx.id])
        XCTAssertEqual(storage.fetchSets(exerciseId: otherEx.id).compactMap { $0.id }, [otherSet.id])
        XCTAssertEqual(storage.fetchWorkout(id: other.id)?.workoutType, "Pull")
    }

    func testReplaceWithNoExercisesClearsWorkoutContents() {
        let (original, _, _) = seed(name: "Push", exerciseName: "Bench Press")
        repo.replaceWorkoutContents(original, exercises: [], sets: [:])
        XCTAssertTrue(storage.fetchExercises(workoutId: original.id).isEmpty)
        XCTAssertNotNil(storage.fetchWorkout(id: original.id))
    }
}
