import XCTest
@testable import Lightstack

/// Child operations whose parent row never reached the cloud (the old queue lost the parent's insert)
/// must not retry forever: the parent is queued from the local store, or the child is dropped as an orphan.
@MainActor
final class OutboxDependencyResolverTests: XCTestCase {

    private func makeLifts(workoutId: UUID, sets: Int = 2) -> (Exercise, [WorkoutSet]) {
        let exercise = Exercise.create(workoutId: workoutId, name: "Bench", muscleGroup: "Chest", orderIndex: 0,
                                       targetSets: 3, targetReps: "8", targetRir: nil, restSeconds: 60, coachNote: nil)
        let list = (1...sets).map { WorkoutSet.create(exerciseId: exercise.id, setNumber: $0, weightLbs: 100, reps: 5, rir: nil) }
        return (exercise, list)
    }

    /// Queues the child operations, then dead-letters them (as the old build did).
    private func deadLetterChildren(_ stack: OutboxTestStack, _ lifts: [(Exercise, [WorkoutSet])]) async {
        for (exercise, sets) in lifts {
            await stack.queue.enqueue(.insertExercises, payload: [exercise])
            for set in sets { await stack.queue.enqueue(.insertSet, payload: set, recordKey: set.id.uuidString) }
        }
        stack.remote.script = { _, _ in QueueTestError.postgres("23514") }
        await stack.queue.flush()
        stack.remote.script = nil
    }

    func testDeadLetteredChildrenOfALocalWorkoutGetTheirParentsAndUpload() async throws {
        let stack = OutboxTestStack(resolveDependencies: true)
        stack.remote.enforceParentRLS = true
        let workout = makeTestWorkout("Push", userId: stack.userId)
        let lifts = makeLifts(workoutId: workout.id)
        stack.storage.saveWorkout(workout)                      // local only: its insert was lost
        stack.storage.saveExercises([lifts.0], workoutId: workout.id)
        lifts.1.forEach { stack.storage.saveSet($0, exerciseId: lifts.0.id) }
        await deadLetterChildren(stack, [lifts])
        let dead = await stack.queue.failedCount
        XCTAssertEqual(dead, 3)

        await stack.queue.flush()

        XCTAssertNotNil(stack.remote.workouts[workout.id])
        XCTAssertNotNil(stack.remote.exercises[lifts.0.id])
        XCTAssertEqual(stack.remote.sets.count, 2)
        let failed = await stack.queue.failedCount
        let pending = await stack.queue.pendingCount
        XCTAssertEqual(failed, 0)
        XCTAssertEqual(pending, 0)
    }

    func testSetWhoseWholeChainIsMissingGetsExerciseAndWorkout() async throws {
        let stack = OutboxTestStack(resolveDependencies: true)
        stack.remote.enforceParentRLS = true
        let workout = makeTestWorkout("Pull", userId: stack.userId)
        let lifts = makeLifts(workoutId: workout.id, sets: 1)
        stack.storage.saveWorkout(workout)
        stack.storage.saveExercises([lifts.0], workoutId: workout.id)
        lifts.1.forEach { stack.storage.saveSet($0, exerciseId: lifts.0.id) }
        // Only the set operation exists (the exercise's and the workout's were lost).
        await stack.queue.enqueue(.insertSet, payload: lifts.1[0], recordKey: lifts.1[0].id.uuidString)
        stack.remote.script = { _, _ in QueueTestError.postgres("23514") }
        await stack.queue.flush()
        stack.remote.script = nil

        await stack.queue.flush()

        XCTAssertNotNil(stack.remote.workouts[workout.id])
        XCTAssertNotNil(stack.remote.exercises[lifts.0.id])
        XCTAssertNotNil(stack.remote.sets[lifts.1[0].id])
        let left = await stack.queue.failedCount + stack.queue.pendingCount
        XCTAssertEqual(left, 0)
    }

    func testChildrenOfAWorkoutDeletedLocallyAreDroppedAndNothingIsUploaded() async throws {
        let stack = OutboxTestStack(resolveDependencies: true)
        stack.remote.enforceParentRLS = true
        let gone = makeTestWorkout("Deleted", userId: stack.userId)
        let lifts = makeLifts(workoutId: gone.id)                // never saved locally: the workout is gone
        await deadLetterChildren(stack, [lifts])
        let callsBefore = stack.remote.calls.count

        await stack.queue.flush()

        let failed = await stack.queue.failedCount
        let pending = await stack.queue.pendingCount
        XCTAssertEqual(failed, 0)
        XCTAssertEqual(pending, 0)
        XCTAssertEqual(stack.remote.calls.count, callsBefore, "nothing was sent")
        XCTAssertTrue(stack.remote.workouts.isEmpty && stack.remote.exercises.isEmpty && stack.remote.sets.isEmpty)
    }

    func testChildrenOfATombstonedWorkoutAreDropped() async throws {
        let stack = OutboxTestStack(resolveDependencies: true)
        let workout = makeTestWorkout("Doomed", userId: stack.userId)
        let lifts = makeLifts(workoutId: workout.id)
        stack.storage.saveWorkout(workout)                       // still here, but the cloud says it was deleted
        stack.storage.saveExercises([lifts.0], workoutId: workout.id)
        await deadLetterChildren(stack, [lifts])

        await stack.queue.resolveDependencies(tombstoned: [.workout: [workout.id]])

        let failed = await stack.queue.failedCount
        let pending = await stack.queue.pendingCount
        XCTAssertEqual(failed + pending, 0)
    }

    func testMixedCaseKeepsEverythingElse() async throws {
        let stack = OutboxTestStack(resolveDependencies: true)
        stack.remote.enforceParentRLS = true
        let kept = makeTestWorkout("Kept", userId: stack.userId)
        let keptLifts = makeLifts(workoutId: kept.id)
        stack.storage.saveWorkout(kept)
        stack.storage.saveExercises([keptLifts.0], workoutId: kept.id)
        keptLifts.1.forEach { stack.storage.saveSet($0, exerciseId: keptLifts.0.id) }
        let orphanLifts = makeLifts(workoutId: UUID())
        await deadLetterChildren(stack, [keptLifts, orphanLifts])
        // An unrelated dead letter must survive.
        let pr = PersonalRecord.create(userId: stack.userId, exerciseName: "Bench", weightLbs: 100, reps: 5, workoutId: nil)
        await stack.queue.enqueue(.insertPersonalRecord, payload: pr, recordKey: pr.id.uuidString)
        stack.remote.script = { _, _ in QueueTestError.postgres("23514") }
        await stack.queue.flush()
        stack.remote.script = nil

        await stack.queue.flush()

        XCTAssertNotNil(stack.remote.workouts[kept.id])
        XCTAssertEqual(stack.remote.sets.count, 2, "only the kept workout's sets")
        XCTAssertNil(stack.remote.exercises[orphanLifts.0.id])
        let dead = await stack.queue.failedOperations()
        XCTAssertEqual(dead.map(\.type), [.insertPersonalRecord], "nothing else is dropped")
    }

    func testRestoreRepairQueuesTheWorkoutRowWhenOnlyItsChildrenArePending() async throws {
        let user = UUID(), remote = FakeRemote()
        remote.enforceParentRLS = true
        let stack = OutboxTestStack(userId: user, remote: remote)
        let repo = WorkoutRepository(localStorage: stack.storage, offlineQueueManager: stack.queue)
        let workout = makeTestWorkout("Lost Header", userId: user)
        let lifts = makeLifts(workoutId: workout.id)
        stack.storage.saveWorkout(workout)                       // the workout's own insert was lost
        repo.saveExercises([lifts.0], workoutId: workout.id)     // but its children are queued
        lifts.1.forEach { repo.saveSet($0, exerciseId: lifts.0.id) }
        let service = SyncRestoreService(
            remote: remote, storage: stack.storage, queue: stack.queue,
            prRepository: PRRepository(localStorage: stack.storage, offlineQueueManager: stack.queue),
            currentUserId: { user },
            defaults: UserDefaults(suiteName: "restore-\(UUID().uuidString)") ?? .standard
        )

        let summary = try await service.restoreAll(userId: user)
        XCTAssertEqual(summary.repairedWorkouts, 1)
        await stack.flushAll()

        XCTAssertNotNil(remote.workouts[workout.id])
        XCTAssertEqual(remote.sets.count, 2)
        let failed = await stack.queue.failedCount
        XCTAssertEqual(failed, 0)
    }
}
