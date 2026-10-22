import XCTest
@testable import Lightstack

/// One-time data cleanup: PR dedupe / orphans / junk names, exact-duplicate workouts,
/// never-started plans, and History excluding empty workouts.
@MainActor
final class DataHygieneTests: XCTestCase {

    private var stack: OutboxTestStack!
    private var storage: LocalStorageService { stack.storage }
    private var workoutRepo: WorkoutRepository!
    private var prRepo: PRRepository!
    private var userId: UUID { stack.userId }
    private var defaults: UserDefaults!
    private let cal = Calendar.current

    override func setUp() {
        super.setUp()
        stack = OutboxTestStack()
        workoutRepo = WorkoutRepository(localStorage: stack.storage, offlineQueueManager: stack.queue)
        prRepo = PRRepository(localStorage: stack.storage, offlineQueueManager: stack.queue)
        defaults = UserDefaults(suiteName: "hygiene-\(UUID().uuidString)")
    }

    // MARK: Helpers

    @discardableResult
    private func addWorkout(type: String = "Push", daysAgo: Int = 1, createdOffset: TimeInterval = 0,
                            sets: [(String, Double, Int, Int?)]) -> Workout {
        var w = Workout.create(userId: userId, workoutType: type, energyLevel: nil, timeAvailableMinutes: nil)
        let day = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: Date())) ?? Date()
        w.date = cal.date(byAdding: .hour, value: 12, to: day) ?? day
        w.createdAt = w.date.addingTimeInterval(createdOffset)
        storage.saveWorkout(w)
        var byName: [String: Exercise] = [:]
        for (i, entry) in sets.enumerated() where byName[entry.0] == nil {
            let e = Exercise.create(workoutId: w.id, name: entry.0, muscleGroup: "Chest", orderIndex: i,
                                    targetSets: 3, targetReps: "5", targetRir: nil, restSeconds: 90, coachNote: nil)
            storage.saveExercises([e], workoutId: w.id)
            byName[entry.0] = e
        }
        for (i, entry) in sets.enumerated() {
            guard let e = byName[entry.0] else { continue }
            storage.saveSet(WorkoutSet.create(exerciseId: e.id, setNumber: i + 1, weightLbs: entry.1, reps: entry.2, rir: entry.3),
                            exerciseId: e.id)
        }
        return w
    }

    private func addEmptyPlan(type: String = "Push", daysAgo: Int, createdOffset: TimeInterval = 0) -> Workout {
        var w = Workout.create(userId: userId, workoutType: type, energyLevel: nil, timeAvailableMinutes: nil)
        let day = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: Date())) ?? Date()
        w.date = cal.date(byAdding: .hour, value: 9, to: day) ?? day
        w.createdAt = w.date.addingTimeInterval(createdOffset)
        storage.saveWorkout(w)
        let e = Exercise.create(workoutId: w.id, name: "Bench Press", muscleGroup: "Chest", orderIndex: 0,
                                targetSets: 3, targetReps: "5", targetRir: nil, restSeconds: 90, coachNote: nil)
        storage.saveExercises([e], workoutId: w.id)
        return w
    }

    private func savePR(_ name: String, _ weight: Double, _ reps: Int) {
        storage.savePersonalRecord(PersonalRecord.create(userId: userId, exerciseName: name, weightLbs: weight, reps: reps, workoutId: nil))
    }

    private func queuedPRDeletes() async -> [DeletePersonalRecordsPayload] {
        await stack.queue.waitForSubmissions()
        let decoder = JSONDecoder()
        return await stack.queue.queuedOperations().filter { $0.type == .deletePersonalRecords }
            .compactMap { try? decoder.decode(DeletePersonalRecordsPayload.self, from: $0.payload) }
    }

    private func workoutIds() -> Set<UUID> {
        Set(storage.fetchAllWorkouts(userId: userId).compactMap(\.id))
    }

    // MARK: PRs

    func testBetterPRReplacesOldRowAndQueuesCloudDelete() async {
        _ = prRepo.checkAndRecordPR(userId: userId, exerciseName: "Bench Press", weightLbs: 100, reps: 5, workoutId: nil)
        _ = prRepo.checkAndRecordPR(userId: userId, exerciseName: "Bench Press", weightLbs: 120, reps: 5, workoutId: nil)
        let all = prRepo.fetchAllPRs(userId: userId)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.weightLbs, 120)
        let deletes = await queuedPRDeletes()
        XCTAssertEqual(deletes.map(\.exerciseName), ["Bench Press"])
        XCTAssertEqual(deletes.first?.keepId, all.first?.id)
    }

    func testPRNameIsSanitized() {
        let pr = prRepo.checkAndRecordPR(userId: userId, exerciseName: "**Chest** Dumbbell Bench Press", weightLbs: 50, reps: 8, workoutId: nil)
        XCTAssertEqual(pr?.exerciseName, "Chest Dumbbell Bench Press")
    }

    func testCleanupDedupesExactDuplicatePRs() async {
        addWorkout(sets: [("Dumbbell Lateral Raise", 25, 10, 2)])
        for _ in 0..<3 { savePR("Dumbbell Lateral Raise", 25, 10) }
        XCTAssertEqual(prRepo.fetchAllPRs(userId: userId).count, 3)

        prRepo.cleanUpRecords(userId: userId)

        let all = prRepo.fetchAllPRs(userId: userId)
        XCTAssertEqual(all.count, 1)
        let deletes = await queuedPRDeletes()
        XCTAssertTrue(deletes.contains { $0.exerciseName == "Dumbbell Lateral Raise" && $0.keepId == all.first?.id },
                      "the cloud rows of this exercise are swept except the kept one")
    }

    func testCleanupRemovesOrphanPRsLocallyAndInCloud() async {
        addWorkout(sets: [("Bench Press", 100, 5, nil)])
        savePR("Bench Press", 100, 5)
        savePR("Old Merged Name", 90, 5)

        let summary = prRepo.cleanUpRecords(userId: userId)

        XCTAssertEqual(summary.orphansRemoved, 1)
        XCTAssertEqual(prRepo.fetchAllPRs(userId: userId).map(\.exerciseName), ["Bench Press"])
        let deletes = await queuedPRDeletes()
        XCTAssertTrue(deletes.contains { $0.exerciseName == "Old Merged Name" && $0.keepId == nil })

        // The queued delete reaches the (fake) cloud.
        await stack.flushAll()
        XCTAssertTrue(stack.remote.calls.contains("deletePersonalRecords:Old Merged Name"))
    }

    func testCleanupSanitizesJunkNamedPRs() {
        addWorkout(sets: [("**Chest** Dumbbell Bench Press", 50, 2, nil)])
        savePR("**Chest** Dumbbell Bench Press", 50, 2)

        prRepo.cleanUpRecords(userId: userId)

        XCTAssertEqual(prRepo.fetchAllPRs(userId: userId).map(\.exerciseName), ["Chest Dumbbell Bench Press"])
    }

    func testPRCleanupIsIdempotent() {
        addWorkout(sets: [("Bench Press", 100, 5, nil)])
        for _ in 0..<2 { savePR("Bench Press", 100, 5) }
        prRepo.cleanUpRecords(userId: userId)
        let first = prRepo.fetchAllPRs(userId: userId)
        prRepo.cleanUpRecords(userId: userId)
        XCTAssertEqual(prRepo.fetchAllPRs(userId: userId).map(\.id), first.map(\.id))
    }

    // MARK: Duplicate workouts

    func testExactDuplicateWorkoutsKeepEarliestAndRecalculatePRs() {
        let sets: [(String, Double, Int, Int?)] = [("Bench Press", 100, 5, 2), ("Bench Press", 100, 5, 2)]
        let first = addWorkout(daysAgo: 2, createdOffset: 0, sets: sets)
        let second = addWorkout(daysAgo: 2, createdOffset: 60, sets: sets)
        let third = addWorkout(daysAgo: 2, createdOffset: 120, sets: sets)
        prRepo.recalculateAllPRs(userId: userId)
        // The PR points at one of the copies; make it the one that will be deleted.
        storage.deletePersonalRecord(userId: userId, exerciseName: "Bench Press")
        var pr = PersonalRecord.create(userId: userId, exerciseName: "Bench Press", weightLbs: 100, reps: 5, workoutId: third.id)
        pr.dateAchieved = first.date
        storage.savePersonalRecord(pr)

        let cleanup = DuplicateWorkoutCleanup(localStorage: storage, workoutRepository: workoutRepo, prRepository: prRepo)
        XCTAssertEqual(cleanup.removeExactDuplicates(userId: userId), 2)

        XCTAssertEqual(workoutIds(), [first.id])
        XCTAssertFalse(workoutIds().contains(second.id))
        XCTAssertEqual(prRepo.fetchPR(userId: userId, exerciseName: "Bench Press")?.workoutId, first.id,
                       "PRs are rebuilt from the surviving workout")
    }

    func testNonExactDuplicatesAreNeverDeleted() {
        let base: [(String, Double, Int, Int?)] = [("Bench Press", 100, 5, 2)]
        let a = addWorkout(daysAgo: 3, sets: base)
        let diffWeight = addWorkout(daysAgo: 3, createdOffset: 10, sets: [("Bench Press", 105, 5, 2)])
        let diffRir = addWorkout(daysAgo: 3, createdOffset: 20, sets: [("Bench Press", 100, 5, 1)])
        let diffType = addWorkout(type: "Pull", daysAgo: 3, createdOffset: 30, sets: base)
        let diffDay = addWorkout(daysAgo: 4, createdOffset: 40, sets: base)
        let extraSet = addWorkout(daysAgo: 3, createdOffset: 50, sets: base + [("Bench Press", 100, 5, 2)])

        let cleanup = DuplicateWorkoutCleanup(localStorage: storage, workoutRepository: workoutRepo, prRepository: prRepo)
        XCTAssertEqual(cleanup.removeExactDuplicates(userId: userId), 0)
        XCTAssertEqual(workoutIds(), [a.id, diffWeight.id, diffRir.id, diffType.id, diffDay.id, extraSet.id])
    }

    func testDuplicateDeleteQueuesWorkoutDeleteAndTombstone() async {
        let sets: [(String, Double, Int, Int?)] = [("Squat", 200, 3, nil)]
        _ = addWorkout(daysAgo: 5, sets: sets)
        let dupe = addWorkout(daysAgo: 5, createdOffset: 5, sets: sets)
        let cleanup = DuplicateWorkoutCleanup(localStorage: storage, workoutRepository: workoutRepo, prRepository: prRepo)
        cleanup.removeExactDuplicates(userId: userId)
        await stack.queue.waitForSubmissions()
        let ops = await stack.queue.queuedOperations()
        XCTAssertTrue(ops.contains { $0.type == .deleteWorkout })
        let tombstones = ops.filter { $0.type == .insertTombstone }
            .compactMap { try? JSONDecoder().decode(TombstonePayload.self, from: $0.payload) }
        XCTAssertTrue(tombstones.contains { $0.entity == .workout && $0.recordIds.contains(dupe.id) })
    }

    // MARK: Unstarted plans

    func testUnstartedPlanCleanupKeepsPendingAndRealSessions() {
        let real = addWorkout(daysAgo: 1, sets: [("Bench Press", 100, 5, nil)])
        let oldEmpty = addEmptyPlan(daysAgo: 6)
        let yesterdayEmpty = addEmptyPlan(daysAgo: 1)
        let todayOld = addEmptyPlan(daysAgo: 0, createdOffset: 0)
        let todayPending = addEmptyPlan(daysAgo: 0, createdOffset: 600)

        let cleanup = StaleWorkoutCleanup(localStorage: storage, workoutRepository: workoutRepo)
        XCTAssertEqual(cleanup.removeUnstartedPlans(userId: userId, keeping: todayPending.id), 3)

        XCTAssertEqual(workoutIds(), [real.id, todayPending.id])
        XCTAssertFalse(workoutIds().contains(oldEmpty.id))
        XCTAssertFalse(workoutIds().contains(yesterdayEmpty.id))
        XCTAssertFalse(workoutIds().contains(todayOld.id))
    }

    func testUnstartedPlanCleanupKeepsNewestPlanOfTodayWhenNoPendingId() {
        let older = addEmptyPlan(daysAgo: 0, createdOffset: 0)
        let newest = addEmptyPlan(daysAgo: 0, createdOffset: 300)
        let cleanup = StaleWorkoutCleanup(localStorage: storage, workoutRepository: workoutRepo)
        XCTAssertEqual(cleanup.removeUnstartedPlans(userId: userId, keeping: nil), 1)
        XCTAssertEqual(workoutIds(), [newest.id])
        XCTAssertFalse(workoutIds().contains(older.id))
    }

    func testSupersededPlanRemovedWhenNewPlanGenerated() {
        let older = addEmptyPlan(daysAgo: 0, createdOffset: 0)
        let newer = addEmptyPlan(daysAgo: 0, createdOffset: 300)
        let cleanup = StaleWorkoutCleanup(localStorage: storage, workoutRepository: workoutRepo)
        XCTAssertEqual(cleanup.removeSupersededPlans(userId: userId, newPlanId: newer.id), 1)
        XCTAssertEqual(workoutIds(), [newer.id])
        XCTAssertFalse(workoutIds().contains(older.id))
    }

    // MARK: Service flag

    func testHygieneRunsOncePerVersionAndUser() {
        addWorkout(sets: [("Bench Press", 100, 5, nil)])
        let service = DataHygieneService(localStorage: storage, workoutRepository: workoutRepo,
                                         prRepository: prRepo, defaults: defaults)
        XCTAssertNotNil(service.runIfNeeded(userId: userId))
        XCTAssertNil(service.runIfNeeded(userId: userId))
        XCTAssertNotNil(service.runIfNeeded(userId: UUID()), "flag is per user")
    }

    // MARK: History filtering

    func testHistoryAndStatsExcludeWorkoutsWithNoLoggedSets() {
        let real = addWorkout(daysAgo: 1, sets: [("Bench Press", 100, 5, nil)])
        _ = addEmptyPlan(daysAgo: 2)
        let logged = workoutRepo.fetchRecentLoggedWorkouts(userId: userId, limit: 100)
        XCTAssertEqual(logged.map(\.id), [real.id])
        XCTAssertEqual(workoutRepo.fetchRecentWorkouts(userId: userId, limit: 100).count, 2)

        let vm = HistoryViewModel(workoutRepository: workoutRepo, prRepository: prRepo)
        vm.loadWorkouts(userId: userId)
        XCTAssertEqual(vm.workouts.map(\.id), [real.id])
        XCTAssertEqual(WorkoutStatsService(localStorage: storage).totalSessions(userId: userId), 1)
    }
}
