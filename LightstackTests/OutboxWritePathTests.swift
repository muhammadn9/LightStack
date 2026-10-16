import XCTest
@testable import Lightstack

/// Phase 2.2: every cloud write goes through the outbox, in causal order, idempotently.
@MainActor
final class OutboxWritePathTests: XCTestCase {

    private var stack: OutboxTestStack!
    private var workoutRepo: WorkoutRepository!
    private var prRepo: PRRepository!
    private var monthRepo: MonthPlanRepository!
    private var restRepo: RestDayRepository!
    private var userId: UUID { stack.userId }

    override func setUp() {
        super.setUp()
        stack = OutboxTestStack()
        workoutRepo = WorkoutRepository(localStorage: stack.storage, offlineQueueManager: stack.queue)
        prRepo = PRRepository(localStorage: stack.storage, offlineQueueManager: stack.queue)
        monthRepo = MonthPlanRepository(
            localStorage: stack.storage,
            supabaseService: SupabaseServiceFactory.unreachable(),
            offlineQueueManager: stack.queue
        )
        restRepo = RestDayRepository(localStorage: stack.storage, offlineQueueManager: stack.queue)
    }

    // MARK: - Helpers

    private func makeWorkout(_ type: String = "Push") -> Workout {
        Workout.create(userId: userId, workoutType: type, energyLevel: nil, timeAvailableMinutes: nil)
    }

    private func makeExercise(_ workoutId: UUID, name: String = "Bench Press", index: Int = 0) -> Exercise {
        Exercise.create(workoutId: workoutId, name: name, muscleGroup: "Chest", orderIndex: index,
                        targetSets: 3, targetReps: "5", targetRir: nil, restSeconds: 90, coachNote: nil)
    }

    private func makeSet(_ exerciseId: UUID, number: Int = 1, weight: Double = 100, reps: Int = 5) -> WorkoutSet {
        WorkoutSet.create(exerciseId: exerciseId, setNumber: number, weightLbs: weight, reps: reps, rir: nil)
    }

    private func queuedTypes() async -> [QueuedOperationType] {
        await stack.queue.waitForSubmissions()
        return await stack.queue.queuedOperations().map(\.type)
    }

    /// Workout with one exercise and one set, saved locally only (as if already synced).
    private func seedLocal() -> (Workout, Exercise, WorkoutSet) {
        let w = makeWorkout()
        stack.storage.saveWorkout(w)
        let e = makeExercise(w.id)
        stack.storage.saveExercises([e], workoutId: w.id)
        let s = makeSet(e.id)
        stack.storage.saveSet(s, exerciseId: e.id)
        return (w, e, s)
    }

    // MARK: - Outbox-first

    func testRepositoryWritesQueueAndNeverCallRemoteDirectly() async {
        let w = makeWorkout()
        workoutRepo.createWorkout(w)
        let e = makeExercise(w.id)
        workoutRepo.saveExercises([e], workoutId: w.id)
        let s = makeSet(e.id)
        workoutRepo.saveSet(s, exerciseId: e.id)
        workoutRepo.updateWorkout(w)

        let types = await queuedTypes()
        XCTAssertEqual(Set(types), [.insertWorkout, .insertExercises, .insertSet, .updateWorkout])
        XCTAssertTrue(stack.remote.calls.isEmpty, "nothing may reach the remote until a flush")

        await stack.flushAll()
        XCTAssertEqual(stack.remote.calls.count, 4)
        let pending = await stack.queue.pendingCount
        XCTAssertEqual(pending, 0)
    }

    func testMonthPlanWritesQueue() async {
        let plan = MonthPlan.create(userId: userId, title: "P", targetGoal: nil,
                                    startDate: Date(), endDate: Date().addingTimeInterval(86_400 * 20), aiOverview: nil)
        let session = PlannedSession.create(monthPlanId: plan.id, userId: userId, plannedDate: Date(),
                                            workoutType: "Push", focusNote: nil, isRestDay: false)
        monthRepo.savePlan(plan, sessions: [session])
        monthRepo.markSessionCompleted(session, workoutId: UUID())
        let types = await queuedTypes()
        XCTAssertEqual(Set(types), [.insertMonthPlan, .insertPlannedSessions, .updatePlannedSession])
        XCTAssertTrue(stack.remote.calls.isEmpty)
    }

    // MARK: - Causal ordering

    func testSequencesIncreaseAtTheCallSite() async {
        let w = makeWorkout()
        workoutRepo.createWorkout(w)
        let e = makeExercise(w.id)
        workoutRepo.saveExercises([e], workoutId: w.id)
        let s = makeSet(e.id)
        workoutRepo.saveSet(s, exerciseId: e.id)
        await stack.queue.waitForSubmissions()
        let ops = await stack.queue.queuedOperations()
        let byType = Dictionary(uniqueKeysWithValues: ops.map { ($0.type, $0.sequence) })
        XCTAssertTrue(byType[.insertWorkout]! < byType[.insertExercises]!)
        XCTAssertTrue(byType[.insertExercises]! < byType[.insertSet]!)
    }

    func testReverseArrivalStillUploadsParentsFirstAndSameTypeInSequenceOrder() async throws {
        let queue = stack.queue
        let w1 = makeWorkout("first"), w2 = makeWorkout("second")
        let e = makeExercise(w1.id)
        let s = makeSet(e.id)
        // Sequences are taken in "call order" ...
        let sW1 = queue.sequencer.next(), sW2 = queue.sequencer.next()
        let sE = queue.sequencer.next(), sS = queue.sequencer.next()
        let enc = JSONEncoder()
        // ... but the follow-up tasks reach the actor in the opposite order.
        await queue.enqueueEncoded(.insertSet, data: try enc.encode(s), recordKey: s.id.uuidString, sequence: sS, flush: false)
        await queue.enqueueEncoded(.insertExercises, data: try enc.encode([e]), recordKey: nil, sequence: sE, flush: false)
        await queue.enqueueEncoded(.insertWorkout, data: try enc.encode(w2), recordKey: w2.id.uuidString, sequence: sW2, flush: false)
        await queue.enqueueEncoded(.insertWorkout, data: try enc.encode(w1), recordKey: w1.id.uuidString, sequence: sW1, flush: false)

        await queue.flush()
        XCTAssertEqual(stack.remote.calls, [
            "insertWorkout:first", "insertWorkout:second", "insertExercises:Bench Press", "insertSet:"
        ])
    }

    func testConcurrentSubmitsFromRepositoryKeepCallOrder() async {
        for _ in 0..<20 {
            let local = OutboxTestStack()
            let repo = WorkoutRepository(localStorage: local.storage, offlineQueueManager: local.queue)
            let w = makeWorkout()
            repo.createWorkout(w)
            let e = makeExercise(w.id)
            repo.saveExercises([e], workoutId: w.id)
            let sets = (1...5).map { makeSet(e.id, number: $0) }
            sets.forEach { repo.saveSet($0, exerciseId: e.id) }
            await local.flushAll()
            XCTAssertEqual(local.remote.workouts.count, 1)
            XCTAssertEqual(local.remote.exercises.count, 1)
            XCTAssertEqual(local.remote.sets.count, 5)
            let pending = await local.queue.pendingCount
            XCTAssertEqual(pending, 0)
        }
    }

    func testSequenceSurvivesRestart() async {
        let dir = makeTempDirectory()
        let userId = self.userId
        func make() -> OfflineQueueManager {
            OfflineQueueManager(remote: FakeRemote(), directory: dir, ownerProvider: { userId },
                                defaults: UserDefaults(suiteName: "oq-\(UUID().uuidString)") ?? .standard, autoFlush: false)
        }
        let first = make()
        first.submit(.insertWorkout, payload: makeWorkout("a"))
        first.submit(.insertWorkout, payload: makeWorkout("b"))
        await first.waitForSubmissions()
        let maxBefore = await first.queuedOperations().map(\.sequence).max() ?? 0
        XCTAssertGreaterThan(maxBefore, 0)

        let second = make()
        XCTAssertGreaterThan(second.sequencer.next(), maxBefore)
    }

    func testLegacyOperationsWithoutSequenceStillDecodeAndFlushInOrder() async throws {
        let dir = makeTempDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let userId = self.userId
        let enc = JSONEncoder()
        func legacy(_ label: String) throws -> [String: Any] {
            [
                "id": UUID().uuidString,
                "type": "insertWorkout",
                "payload": try enc.encode(makeWorkout(label)).base64EncodedString(),
                "enqueuedAt": 1_000.0,
                "attempts": 0
            ]
        }
        let json = try JSONSerialization.data(withJSONObject: [try legacy("L1"), try legacy("L2")])
        try json.write(to: dir.appendingPathComponent("queue.json"))

        let remote = FakeRemote()
        let queue = OfflineQueueManager(remote: remote, directory: dir, ownerProvider: { userId },
                                        defaults: UserDefaults(suiteName: "oq-\(UUID().uuidString)") ?? .standard,
                                        autoFlush: false)
        queue.submit(.insertWorkout, payload: makeWorkout("New"))
        await queue.waitForSubmissions()
        await queue.flush()
        XCTAssertEqual(remote.calls, ["insertWorkout:L1", "insertWorkout:L2", "insertWorkout:New"])
        let failed = await queue.failedCount
        XCTAssertEqual(failed, 0)
    }

    // MARK: - Contiguous-prefix flushing

    func testChildIsNotUploadedBeforeItsParentHasArrived() async throws {
        let queue = stack.queue
        let remote = stack.remote
        remote.script = { type, _ in
            type == .insertExercises && remote.workouts.isEmpty ? QueueTestError.postgres("23503") : nil
        }
        let w = makeWorkout()
        let e = makeExercise(w.id)
        let sParent = queue.sequencer.next()   // the app wrote the workout first ...
        let sChild = queue.sequencer.next()    // ... then its exercise
        let enc = JSONEncoder()
        // The child's follow-up task reaches the queue first.
        await queue.enqueueEncoded(.insertExercises, data: try enc.encode([e]), recordKey: nil, sequence: sChild, flush: false)
        await queue.flush()
        XCTAssertTrue(remote.calls.isEmpty, "child must wait for the missing earlier write")
        let waiting = await queue.queuedOperations()
        XCTAssertEqual(waiting.count, 1)
        XCTAssertEqual(waiting.first?.attempts, 0)

        await queue.enqueueEncoded(.insertWorkout, data: try enc.encode(w), recordKey: w.id.uuidString, sequence: sParent, flush: false)
        await queue.flush()
        XCTAssertEqual(remote.calls, ["insertWorkout:Push", "insertExercises:Bench Press"])
        let pending = await queue.pendingCount
        let failed = await queue.failedCount
        XCTAssertEqual(pending, 0)
        XCTAssertEqual(failed, 0)
    }

    func testIssuedSequenceThatNeverArrivesBlocksOnlyUntilAbandoned() async throws {
        let queue = stack.queue
        let lost = queue.sequencer.next()
        let kept = queue.sequencer.next()
        let w = makeWorkout()
        await queue.enqueueEncoded(.insertWorkout, data: try JSONEncoder().encode(w),
                                   recordKey: w.id.uuidString, sequence: kept, flush: false)
        await queue.flush()
        XCTAssertTrue(stack.remote.calls.isEmpty)
        queue.sequencer.markArrived(lost)   // what the failure paths do
        await queue.flush()
        XCTAssertEqual(stack.remote.calls.count, 1)
    }

    func testCoalescedAndSupersededSequencesStillAdvanceThePrefix() async {
        let w = makeWorkout()
        workoutRepo.createWorkout(w)
        let e = makeExercise(w.id)
        workoutRepo.saveExercises([e], workoutId: w.id)
        var s = makeSet(e.id)
        workoutRepo.saveSet(s, exerciseId: e.id)
        s.isPR = true
        workoutRepo.updateSet(s)                       // coalesces into the insert
        workoutRepo.replaceWorkoutContents(w, exercises: [], sets: [:])   // supersedes the exercise insert
        await stack.queue.waitForSubmissions()
        let last = stack.queue.sequencer.next()
        stack.queue.sequencer.markArrived(last)
        XCTAssertEqual(stack.queue.sequencer.contiguousPrefix, last)
        await stack.flushAll()
        let pending = await stack.queue.pendingCount
        XCTAssertEqual(pending, 0)
    }

    func testDependencyFailuresRetryQuicklyThenBackOff() {
        XCTAssertEqual((1...3).map { OfflineQueueManager.backoff(attempts: $0, dependency: true) }, [2, 2, 5])
        XCTAssertEqual(OfflineQueueManager.backoff(attempts: 4, dependency: true), 80)
        XCTAssertEqual(OfflineQueueManager.backoff(attempts: 1), 10)
    }

    func testRestDayRemoteDeleteMatchesByDayNotId() async {
        let day = Date()
        restRepo.addRestDay(userId: userId, date: day)
        await stack.flushAll()
        // Another device's row for the same day, with a different id.
        try? await stack.remote.upsertRestDay(RestDay(id: UUID(), userId: userId, date: day.startOfDay, createdAt: Date()))
        XCTAssertEqual(stack.remote.restDays.count, 2)
        restRepo.removeRestDay(userId: userId, date: day)
        await stack.flushAll()
        XCTAssertTrue(stack.remote.restDays.isEmpty)
    }

    // MARK: - Coalescing and set updates

    func testUpdateSetCoalescesWithPendingInsertAndPRFlagReachesCloud() async {
        let w = makeWorkout()
        workoutRepo.createWorkout(w)
        let e = makeExercise(w.id)
        workoutRepo.saveExercises([e], workoutId: w.id)
        var s = makeSet(e.id)
        workoutRepo.saveSet(s, exerciseId: e.id)
        s.isPR = true
        workoutRepo.updateSet(s)

        let types = await queuedTypes()
        XCTAssertEqual(types.filter { $0 == .insertSet }.count, 1, "update replaces the pending insert in place")
        await stack.flushAll()
        XCTAssertEqual(stack.remote.sets[s.id]?.isPR, true)
        XCTAssertEqual(stack.remote.calls.filter { $0.hasPrefix("insertSet") }.count, 1)
    }

    func testOlderPayloadArrivingLateDoesNotOverwriteNewer() async throws {
        let queue = stack.queue
        let e = UUID()
        var s = makeSet(e)
        let sOld = queue.sequencer.next()
        s.isPR = false
        let oldData = try JSONEncoder().encode(s)
        let sNew = queue.sequencer.next()
        s.isPR = true
        let newData = try JSONEncoder().encode(s)
        await queue.enqueueEncoded(.insertSet, data: newData, recordKey: s.id.uuidString, sequence: sNew, flush: false)
        await queue.enqueueEncoded(.insertSet, data: oldData, recordKey: s.id.uuidString, sequence: sOld, flush: false)
        let ops = await queue.queuedOperations()
        XCTAssertEqual(ops.count, 1)
        await queue.flush()
        XCTAssertEqual(stack.remote.sets[s.id]?.isPR, true)
    }

    func testUpdateDuringInFlightUploadIsNotLost() async throws {
        let w = makeWorkout()
        workoutRepo.createWorkout(w)
        let e = makeExercise(w.id)
        workoutRepo.saveExercises([e], workoutId: w.id)
        var s = makeSet(e.id)
        workoutRepo.saveSet(s, exerciseId: e.id)
        await stack.queue.waitForSubmissions()

        // Pause the remote on the first call of the flush, then change the set.
        stack.remote.armSuspension()
        let queue = stack.queue
        let flushing = Task { await queue.flush() }
        for _ in 0..<400 where !stack.remote.isSuspended { try await Task.sleep(nanoseconds: 5_000_000) }
        s.isPR = true
        workoutRepo.updateSet(s)
        await queue.waitForSubmissions()
        stack.remote.release()
        await flushing.value
        await queue.flush()
        XCTAssertEqual(stack.remote.sets[s.id]?.isPR, true)
    }

    func testDeletesAndInsertsAreNeverCoalesced() async {
        let (_, _, s) = seedLocal()
        workoutRepo.saveSet(s, exerciseId: s.exerciseId)
        workoutRepo.deleteSet(s)
        let types = await queuedTypes()
        XCTAssertTrue(types.contains(.insertSet))
        XCTAssertTrue(types.contains(.deleteSet))
    }

    // MARK: - Replace (delete-before-insert)

    func testReplaceDeletesBeforeInsertsAndNewExercisesSurvive() async {
        let w = makeWorkout()
        workoutRepo.createWorkout(w)
        let oldEx = makeExercise(w.id, name: "Old")
        workoutRepo.saveExercises([oldEx], workoutId: w.id)
        let oldSet = makeSet(oldEx.id)
        workoutRepo.saveSet(oldSet, exerciseId: oldEx.id)
        await stack.flushAll()
        XCTAssertEqual(stack.remote.exercises.count, 1)

        let newEx = makeExercise(w.id, name: "New")
        let newSet = makeSet(newEx.id, weight: 60)
        workoutRepo.replaceWorkoutContents(w, exercises: [newEx], sets: [newEx.id: [newSet]])
        await stack.flushAll()

        let calls = stack.remote.calls
        let del = calls.lastIndex { $0.hasPrefix("deleteExercises") }
        let ins = calls.lastIndex { $0.hasPrefix("insertExercises:New") }
        XCTAssertNotNil(del)
        XCTAssertNotNil(ins)
        if let del, let ins { XCTAssertLessThan(del, ins) }
        XCTAssertEqual(Set(stack.remote.exercises.keys), [newEx.id])
        XCTAssertEqual(Set(stack.remote.sets.keys), [newSet.id])
        XCTAssertTrue(stack.remote.tombstones.contains("exercise:\(oldEx.id.uuidString)"))
        XCTAssertTrue(stack.remote.tombstones.contains("set:\(oldSet.id.uuidString)"))
    }

    func testReplaceReusingExerciseIdsDoesNotTombstoneThem() async {
        let (w, e, s) = seedLocal()
        workoutRepo.replaceWorkoutContents(w, exercises: [e], sets: [e.id: [s]])
        await stack.flushAll()
        XCTAssertFalse(stack.remote.tombstones.contains("exercise:\(e.id.uuidString)"))
        XCTAssertFalse(stack.remote.tombstones.contains("set:\(s.id.uuidString)"))
        XCTAssertEqual(Set(stack.remote.exercises.keys), [e.id])
    }

    func testReplaceDropsOnlyEarlierQueuedInserts() async {
        let w = makeWorkout()
        workoutRepo.createWorkout(w)
        let stale = makeExercise(w.id, name: "Stale")
        workoutRepo.saveExercises([stale], workoutId: w.id)
        let fresh = makeExercise(w.id, name: "Fresh")
        workoutRepo.replaceWorkoutContents(w, exercises: [fresh], sets: [:])
        await stack.flushAll()
        XCTAssertEqual(Set(stack.remote.exercises.keys), [fresh.id])
    }

    // MARK: - Idempotent replay

    func testReplayingTheSameInsertTwiceLeavesOneRowAndNoDeadLetter() async {
        let w = makeWorkout()
        let e = makeExercise(w.id)
        await stack.queue.enqueue(.insertWorkout, payload: w)
        await stack.queue.enqueue(.insertWorkout, payload: w)
        await stack.queue.enqueue(.insertExercises, payload: [e])
        await stack.queue.enqueue(.insertExercises, payload: [e])
        await stack.queue.flush()
        XCTAssertEqual(stack.remote.workouts.count, 1)
        XCTAssertEqual(stack.remote.exercises.count, 1)
        let failed = await stack.queue.failedCount
        XCTAssertEqual(failed, 0)
    }

    // MARK: - Tombstones

    func testDeleteWorkoutQueuesDeleteAndTombstonesForWorkoutExercisesAndSets() async {
        let (w, e, s) = seedLocal()
        workoutRepo.deleteWorkout(w)
        let types = await queuedTypes()
        XCTAssertTrue(types.contains(.deleteWorkout))
        await stack.flushAll()
        XCTAssertEqual(Set(stack.remote.tombstones), [
            "workout:\(w.id.uuidString)", "exercise:\(e.id.uuidString)", "set:\(s.id.uuidString)"
        ])
        XCTAssertNil(stack.storage.fetchWorkout(id: w.id))
    }

    func testDeleteExerciseTombstonesExerciseAndItsSets() async {
        let (_, e, s) = seedLocal()
        workoutRepo.deleteExercise(e.id)
        await stack.flushAll()
        XCTAssertEqual(Set(stack.remote.tombstones), ["exercise:\(e.id.uuidString)", "set:\(s.id.uuidString)"])
        XCTAssertTrue(stack.remote.calls.contains { $0.hasPrefix("deleteExercise:") })
    }

    func testDeleteSetTombstonesSet() async {
        let (_, _, s) = seedLocal()
        workoutRepo.deleteSet(s)
        await stack.flushAll()
        XCTAssertEqual(stack.remote.tombstones, ["set:\(s.id.uuidString)"])
        XCTAssertTrue(stack.remote.calls.contains { $0.hasPrefix("deleteSet:") })
    }

    func testDeleteExercisesForWorkoutIsQueuedNotSwallowedAndTombstoned() async {
        let (w, e, s) = seedLocal()
        workoutRepo.deleteExercises(forWorkoutId: w.id)
        let types = await queuedTypes()
        XCTAssertEqual(types.filter { $0 == .deleteExercises }.count, 1)
        await stack.flushAll()
        XCTAssertEqual(Set(stack.remote.tombstones), ["exercise:\(e.id.uuidString)", "set:\(s.id.uuidString)"])
        XCTAssertTrue(stack.storage.fetchExercises(workoutId: w.id).isEmpty)
    }

    func testFailedDeleteExercisesIsRetriedNotLost() async {
        let (w, _, _) = seedLocal()
        stack.remote.script = { type, _ in type == .deleteExercises ? QueueTestError.offline : nil }
        workoutRepo.deleteExercises(forWorkoutId: w.id)
        await stack.flushAll()
        let pending = await stack.queue.queuedOperations().map(\.type)
        XCTAssertTrue(pending.contains(.deleteExercises), "a failed remote delete stays queued")
    }

    func testDeleteMonthPlanQueuesRemoteDeleteAndTombstones() async {
        let plan = MonthPlan.create(userId: userId, title: "P", targetGoal: nil,
                                    startDate: Date(), endDate: Date().addingTimeInterval(86_400 * 20), aiOverview: nil)
        let session = PlannedSession.create(monthPlanId: plan.id, userId: userId, plannedDate: Date(),
                                            workoutType: "Push", focusNote: nil, isRestDay: false)
        monthRepo.savePlan(plan, sessions: [session])
        monthRepo.deletePlan(plan)
        await stack.flushAll()
        XCTAssertEqual(Set(stack.remote.tombstones), [
            "month_plan:\(plan.id.uuidString)", "planned_session:\(session.id.uuidString)"
        ])
        XCTAssertTrue(stack.remote.monthPlans.isEmpty)
        XCTAssertNil(stack.storage.fetchMonthPlan(id: plan.id))
    }

    func testTombstoneUsesQueueOwnerAndRunsAfterDeletes() async {
        let (w, _, _) = seedLocal()
        workoutRepo.deleteWorkout(w)
        await stack.queue.waitForSubmissions()
        let ordered = OfflineQueueManager.fkOrdered(await stack.queue.queuedOperations()).map(\.type)
        let firstTomb = ordered.firstIndex(of: .insertTombstone)
        let del = ordered.firstIndex(of: .deleteWorkout)
        XCTAssertNotNil(firstTomb)
        if let firstTomb, let del { XCTAssertLessThan(del, firstTomb) }
        let tomb = await stack.queue.queuedOperations().first { $0.type == .insertTombstone }
        let payload = tomb.flatMap { try? JSONDecoder().decode(TombstonePayload.self, from: $0.payload) }
        XCTAssertEqual(payload?.userId, userId)
    }

    // MARK: - Personal records (append-only)

    private func logSets(_ sets: [(Double, Int)]) -> [WorkoutSet] {
        let w = makeWorkout()
        stack.storage.saveWorkout(w)
        let e = makeExercise(w.id)
        stack.storage.saveExercises([e], workoutId: w.id)
        return sets.enumerated().map { i, entry in
            let s = makeSet(e.id, number: i + 1, weight: entry.0, reps: entry.1)
            stack.storage.saveSet(s, exerciseId: e.id)
            return s
        }
    }

    func testCheckAndRecordPRAppendsAndQueuesInsert() async {
        let pr = prRepo.checkAndRecordPR(userId: userId, exerciseName: "Bench Press", weightLbs: 100, reps: 5, workoutId: nil)
        XCTAssertNotNil(pr)
        let types = await queuedTypes()
        XCTAssertEqual(types, [.insertPersonalRecord])
        XCTAssertTrue(stack.remote.calls.isEmpty)
    }

    func testRecalculationAppendsNewPRAndNeverDeletesRemotely() async {
        let sets = logSets([(100, 5), (150, 5)])
        prRepo.recalculatePR(userId: userId, exerciseName: "Bench Press")
        await stack.flushAll()
        XCTAssertEqual(stack.remote.personalRecords.count, 1)
        XCTAssertEqual(stack.remote.personalRecords.values.first?.weightLbs, 150)

        // Unchanged result: nothing new is logged.
        prRepo.recalculatePR(userId: userId, exerciseName: "Bench Press")
        let unchanged = await queuedTypes()
        XCTAssertTrue(unchanged.isEmpty)

        // The best set is deleted: the new best is appended; the old cloud row stays.
        stack.storage.deleteSet(setId: sets[1].id)
        prRepo.recalculatePR(userId: userId, exerciseName: "Bench Press")
        await stack.flushAll()
        XCTAssertEqual(stack.remote.personalRecords.count, 2)
        XCTAssertEqual(Set(stack.remote.personalRecords.values.map(\.weightLbs)), [100, 150])
        XCTAssertEqual(prRepo.fetchPR(userId: userId, exerciseName: "Bench Press")?.weightLbs, 100)
        XCTAssertFalse(stack.remote.calls.contains { $0.lowercased().contains("deletepersonal") })
        XCTAssertFalse(stack.remote.tombstones.contains { $0.hasPrefix("personal_record") })
    }

    func testRecalculateAllQueuesOnlyChangedPRsAndNothingForRemovedOnes() async {
        _ = logSets([(100, 5)])
        stack.storage.savePersonalRecord(PersonalRecord.create(
            userId: userId, exerciseName: "Deadlift", weightLbs: 300, reps: 1, workoutId: nil))
        prRepo.recalculateAllPRs(userId: userId)
        await stack.flushAll()
        XCTAssertEqual(stack.remote.personalRecords.count, 1, "only the rebuilt Bench Press row; stale Deadlift is local-only")
        XCTAssertNil(prRepo.fetchPR(userId: userId, exerciseName: "Deadlift"))
    }

    // MARK: - Rest days

    func testRestDayCreateAndDeleteQueueOpsAndTombstone() async {
        let day = Date()
        restRepo.addRestDay(userId: userId, date: day)
        restRepo.addRestDay(userId: userId, date: day) // already a rest day: no second op
        var types = await queuedTypes()
        XCTAssertEqual(types, [.upsertRestDay])
        await stack.flushAll()
        XCTAssertEqual(stack.remote.restDays.count, 1)
        let id = stack.remote.restDays.keys.first

        restRepo.removeRestDay(userId: userId, date: day)
        types = await queuedTypes()
        XCTAssertEqual(Set(types), [.deleteRestDay, .insertTombstone])
        await stack.flushAll()
        XCTAssertTrue(stack.remote.restDays.isEmpty)
        XCTAssertEqual(stack.remote.tombstones, ["rest_day:\(id?.uuidString ?? "?")"])
        XCTAssertFalse(stack.storage.isRestDay(userId: userId, date: day))
    }

    func testRestDayJSONMapsDateAsCalendarDay() throws {
        let day = Calendar.current.startOfDay(for: Date())
        let rest = RestDay(id: UUID(), userId: userId, date: day, createdAt: Date())
        let row = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rest.toSupabase())) as? [String: Any]
        let text = row?["date"] as? String
        XCTAssertEqual(text?.count, 10)
        XCTAssertEqual(text?.dropFirst(4).first, "-")
        // The queue's own encoding round-trips.
        let back = try JSONDecoder().decode(RestDay.self, from: JSONEncoder().encode(rest))
        XCTAssertEqual(back, rest)
    }

    // MARK: - Local upserts by id

    func testSaveWorkoutPersonalRecordAndPlannedSessionsUpsertById() {
        let storage = stack.storage
        var w = makeWorkout()
        storage.saveWorkout(w)
        w.workoutType = "Renamed"
        storage.saveWorkout(w)
        XCTAssertEqual(storage.fetchRecentWorkouts(userId: userId, limit: 10).count, 1)
        XCTAssertEqual(storage.fetchWorkout(id: w.id)?.workoutType, "Renamed")

        var pr = PersonalRecord.create(userId: userId, exerciseName: "Squat", weightLbs: 200, reps: 3, workoutId: nil)
        storage.savePersonalRecord(pr)
        pr.weightLbs = 210
        storage.savePersonalRecord(pr)
        XCTAssertEqual(storage.fetchPersonalRecords(userId: userId).count, 1)
        XCTAssertEqual(storage.fetchPersonalRecords(userId: userId).first?.weightLbs, 210)

        let plan = MonthPlan.create(userId: userId, title: "P", targetGoal: nil, startDate: Date(),
                                    endDate: Date().addingTimeInterval(86_400), aiOverview: nil)
        storage.saveMonthPlan(plan)
        let session = PlannedSession.create(monthPlanId: plan.id, userId: userId, plannedDate: Date(),
                                            workoutType: "Push", focusNote: nil, isRestDay: false)
        storage.savePlannedSessions([session], monthPlanId: plan.id)
        storage.savePlannedSessions([session], monthPlanId: plan.id)   // what syncPlanFromRemote does on every fetch
        XCTAssertEqual(storage.fetchPlannedSessions(monthPlanId: plan.id).count, 1)
    }

    func testWorkoutSetupNoteRoundTrips() throws {
        var w = makeWorkout()
        w.setupNote = "Shoulder is sore"
        let back = try JSONDecoder().decode(Workout.self, from: JSONEncoder().encode(w))
        XCTAssertEqual(back.setupNote, "Shoulder is sore")
        let row = try JSONSerialization.jsonObject(with: JSONEncoder().encode(w.toSupabase())) as? [String: Any]
        XCTAssertEqual(row?["setup_note"] as? String, "Shoulder is sore")
    }

    // MARK: - Rename via queue

    func testExerciseMergeRenameGoesThroughQueue() async {
        let w = makeWorkout()
        workoutRepo.createWorkout(w)
        let e = makeExercise(w.id, name: "Leg extension machine")
        workoutRepo.saveExercises([e], workoutId: w.id)
        let merge = ExerciseMergeService(localStorage: stack.storage, offlineQueueManager: stack.queue, prRepository: prRepo)
        XCTAssertEqual(merge.merge(userId: userId, names: ["Leg extension machine", "Leg Extension"], keep: "Leg Extension"), 1)
        let types = await queuedTypes()
        XCTAssertTrue(types.contains(.renameExercises))
        XCTAssertTrue(stack.remote.calls.isEmpty)
        await stack.flushAll()
        XCTAssertEqual(stack.remote.renames.first?.name, "Leg Extension")
    }
}
