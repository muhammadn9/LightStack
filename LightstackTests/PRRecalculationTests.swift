import XCTest
import Supabase
@testable import Lightstack

final class PRRecalculationTests: XCTestCase {

    private var storage: LocalStorageService!
    private var prRepo: PRRepository!
    private let userId = UUID()

    override func setUp() {
        super.setUp()
        storage = LocalStorageService(inMemory: true)
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://example.invalid") ?? URL(fileURLWithPath: "/"),
            supabaseKey: "test"
        )
        let supabase = SupabaseService(client: client)
        prRepo = PRRepository(
            localStorage: storage,
            supabaseService: supabase,
            offlineQueueManager: OfflineQueueManager(supabaseService: supabase)
        )
    }

    private func makeExercise(named name: String) -> Exercise {
        let workout = Workout.create(userId: userId, workoutType: "Push", energyLevel: nil, timeAvailableMinutes: nil)
        storage.saveWorkout(workout)
        let exercise = Exercise.create(
            workoutId: workout.id, name: name, muscleGroup: "Chest", orderIndex: 0,
            targetSets: 3, targetReps: "5", targetRir: nil, restSeconds: 90, coachNote: nil
        )
        storage.saveExercises([exercise], workoutId: workout.id)
        return exercise
    }

    private func addSet(_ exercise: Exercise, weight: Double, reps: Int) -> WorkoutSet {
        let set = WorkoutSet.create(exerciseId: exercise.id, setNumber: 1, weightLbs: weight, reps: reps, rir: nil)
        storage.saveSet(set, exerciseId: exercise.id)
        return set
    }

    func testDeleteSetRemovesOnlyThatSet() {
        let ex = makeExercise(named: "Bench Press")
        let a = addSet(ex, weight: 100, reps: 5)
        _ = addSet(ex, weight: 120, reps: 5)
        storage.deleteSet(setId: a.id)
        let remaining = storage.fetchSets(exerciseId: ex.id)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertNotEqual(remaining.first?.id, a.id)
    }

    func testRecalculateAfterDeletingPRSetFallsBackToNextBest() {
        let ex = makeExercise(named: "Bench Press")
        _ = addSet(ex, weight: 100, reps: 5)
        let best = addSet(ex, weight: 150, reps: 5)
        prRepo.recalculatePR(userId: userId, exerciseName: "Bench Press")
        XCTAssertEqual(prRepo.fetchPR(userId: userId, exerciseName: "Bench Press")?.weightLbs, 150)

        storage.deleteSet(setId: best.id)
        prRepo.recalculatePR(userId: userId, exerciseName: "Bench Press")
        XCTAssertEqual(prRepo.fetchPR(userId: userId, exerciseName: "Bench Press")?.weightLbs, 100)
    }

    func testRecalculateRemovesPRWhenNoSetsRemain() {
        let ex = makeExercise(named: "Squat")
        let only = addSet(ex, weight: 200, reps: 3)
        prRepo.recalculatePR(userId: userId, exerciseName: "Squat")
        XCTAssertNotNil(prRepo.fetchPR(userId: userId, exerciseName: "Squat"))

        storage.deleteSet(setId: only.id)
        prRepo.recalculatePR(userId: userId, exerciseName: "Squat")
        XCTAssertNil(prRepo.fetchPR(userId: userId, exerciseName: "Squat"))
    }

    func testRecalculateAllRepairsStaleAndMissingPRs() {
        let bench = makeExercise(named: "Bench Press")
        let squat = makeExercise(named: "Squat")
        _ = addSet(bench, weight: 100, reps: 5)
        _ = addSet(squat, weight: 180, reps: 5)

        // Stale PR for an exercise with no sets, and an inflated PR for bench.
        storage.savePersonalRecord(PersonalRecord.create(
            userId: userId, exerciseName: "Deadlift", weightLbs: 300, reps: 1, workoutId: nil))
        storage.savePersonalRecord(PersonalRecord.create(
            userId: userId, exerciseName: "Bench Press", weightLbs: 250, reps: 5, workoutId: nil))
        // Squat has sets but no PR record.

        prRepo.recalculateAllPRs(userId: userId)

        XCTAssertNil(prRepo.fetchPR(userId: userId, exerciseName: "Deadlift"))
        XCTAssertEqual(prRepo.fetchPR(userId: userId, exerciseName: "Bench Press")?.weightLbs, 100)
        XCTAssertEqual(prRepo.fetchPR(userId: userId, exerciseName: "Squat")?.weightLbs, 180)
        XCTAssertEqual(prRepo.fetchAllPRs(userId: userId).count, 2)
    }
}
