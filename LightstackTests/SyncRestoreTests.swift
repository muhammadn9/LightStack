import XCTest
@testable import Lightstack

/// Restore: downloads the cloud into the local store without queueing anything, honouring
/// tombstones, unuploaded local changes and the active workout.
@MainActor
final class SyncRestoreTests: XCTestCase {

    // MARK: - Helpers

    /// One phone: its own local store, outbox and restore service, sharing a cloud with other devices.
    struct Device {
        let stack: OutboxTestStack
        let service: SyncRestoreService
        let workouts: WorkoutRepository
        let restDays: RestDayRepository
        let signedIn: TestBox<UUID?>
        let active: TestBox<Set<UUID>>
        let defaults: UserDefaults
        var storage: LocalStorageService { stack.storage }
        var queue: OfflineQueueManager { stack.queue }
        var userId: UUID { stack.userId }

        func queuedTypes() async -> [QueuedOperationType] {
            await queue.waitForSubmissions()
            return await queue.queuedOperations().map(\.type)
        }
    }

    private func makeDevice(remote: FakeRemote, userId: UUID, pageSize: Int = 2) -> Device {
        let stack = OutboxTestStack(userId: userId, remote: remote)
        let signedIn = TestBox<UUID?>(userId)
        let active = TestBox<Set<UUID>>([])
        let defaults = UserDefaults(suiteName: "restore-\(UUID().uuidString)") ?? .standard
        let pr = PRRepository(localStorage: stack.storage, offlineQueueManager: stack.queue)
        let service = SyncRestoreService(
            remote: remote, storage: stack.storage, queue: stack.queue, prRepository: pr,
            currentUserId: { signedIn.value }, activeWorkoutIds: { active.value },
            defaults: defaults, pageSize: pageSize
        )
        return Device(
            stack: stack, service: service,
            workouts: WorkoutRepository(localStorage: stack.storage, offlineQueueManager: stack.queue),
            restDays: RestDayRepository(localStorage: stack.storage, offlineQueueManager: stack.queue),
            signedIn: signedIn, active: active, defaults: defaults
        )
    }

    typealias Lifts = [(Exercise, [WorkoutSet])]

    /// A workout with `exercises` = (name, number of sets) pairs.
    private func makeWorkout(_ type: String, user: UUID, daysAgo: Int = 0, exercises: [(String, Int)] = []) -> (Workout, Lifts) {
        var workout = Workout.create(userId: user, workoutType: type, energyLevel: nil, timeAvailableMinutes: nil)
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        workout.date = day
        workout.createdAt = day
        let lifts: Lifts = exercises.enumerated().map { index, entry in
            let exercise = Exercise.create(workoutId: workout.id, name: entry.0, muscleGroup: "Chest", orderIndex: index,
                                           targetSets: 3, targetReps: "8", targetRir: nil, restSeconds: 90, coachNote: nil)
            let sets = (0..<entry.1).map {
                WorkoutSet.create(exerciseId: exercise.id, setNumber: $0 + 1, weightLbs: Double(100 + 5 * $0), reps: 8, rir: 2)
            }
            return (exercise, sets)
        }
        return (workout, lifts)
    }

    /// Writes a workout straight into the local store (no queue, like a row an old build had uploaded or lost).
    private func saveLocally(_ item: (Workout, Lifts), on device: Device) {
        device.storage.saveWorkout(item.0)
        device.storage.saveExercises(item.1.map(\.0), workoutId: item.0.id)
        for (exercise, sets) in item.1 { sets.forEach { device.storage.saveSet($0, exerciseId: exercise.id) } }
    }

    private func makeProfile(_ user: UUID, name: String = "Remote Me") -> UserProfile {
        UserProfile.create(userId: user, displayName: name, age: 30, heightInches: 70, weightLbs: 180,
                           trainingAgeMonths: 24, primaryGoals: ["Strength"], splitDays: ["Push", "Pull"],
                           avoidExercises: ["Behind Neck Press"], equipment: ["Barbell": true],
                           customEquipment: "Sled", notesToCoach: "Left shoulder")
    }

    private func localWorkoutTypes(_ device: Device) -> [String] {
        device.storage.fetchRecentWorkouts(userId: device.userId, limit: 100).compactMap(\.workoutType).sorted()
    }

    // MARK: - Fresh device

    func testFreshDeviceRestoresEverythingWithoutQueueingAnything() async throws {
        let user = UUID(), remote = FakeRemote()
        remote.seedProfile(makeProfile(user))
        let push = makeWorkout("Push", user: user, daysAgo: 1, exercises: [("Bench", 3), ("Fly", 2)])
        let pull = makeWorkout("Pull", user: user, daysAgo: 2, exercises: [("Row", 3)])
        for item in [push, pull] { remote.seedWorkout(item.0, exercises: item.1) }
        let restDay = RestDay(id: UUID(), userId: user, date: Date().startOfDay, createdAt: Date())
        remote.seedRestDay(restDay)
        let plan = MonthPlan.create(userId: user, title: "Plan", targetGoal: nil, startDate: Date(),
                                    endDate: Date().addingTimeInterval(86_400 * 20), aiOverview: nil)
        let session = PlannedSession.create(monthPlanId: plan.id, userId: user, plannedDate: Date(),
                                            workoutType: "Push", focusNote: nil, isRestDay: false)
        remote.seedPlan(plan, sessions: [session])
        remote.seedSummary(AIContextSummary.create(userId: user, workoutType: "Push", summaryText: "Went well", sessionsCovered: 3))

        let device = makeDevice(remote: remote, userId: user)
        let summary = try await device.service.restoreAll(userId: user)

        XCTAssertTrue(summary.profileApplied)
        XCTAssertEqual(device.storage.fetchProfile(userId: user)?.displayName, "Remote Me")
        XCTAssertEqual(device.storage.fetchProfile(userId: user)?.notesToCoach, "Left shoulder")
        XCTAssertEqual(localWorkoutTypes(device), ["Pull", "Push"])
        XCTAssertEqual(device.storage.fetchExercises(workoutId: push.0.id).count, 2)
        let bench = try XCTUnwrap(device.storage.fetchExercises(workoutId: push.0.id).first)
        XCTAssertEqual(device.storage.fetchSets(exerciseId: try XCTUnwrap(bench.id)).count, 3)
        XCTAssertEqual(device.storage.fetchRestDays(userId: user).count, 1)
        XCTAssertNotNil(device.storage.fetchActiveMonthPlan(userId: user))
        XCTAssertEqual(device.storage.fetchPlannedSessions(monthPlanId: plan.id).count, 1)
        XCTAssertEqual(device.storage.fetchContextSummary(userId: user, workoutType: "Push")?.summaryText, "Went well")

        let types = await device.queuedTypes()
        XCTAssertTrue(types.isEmpty, "restore must not queue uploads, found \(types)")
        XCTAssertNotNil(device.service.lastSuccessfulRestore(userId: user))
    }

    func testRestoringTwiceChangesNothing() async throws {
        let user = UUID(), remote = FakeRemote()
        let item = makeWorkout("Push", user: user, exercises: [("Bench", 2)])
        remote.seedWorkout(item.0, exercises: item.1)
        let device = makeDevice(remote: remote, userId: user)
        try await device.service.restoreAll(userId: user)
        try await device.service.restoreAll(userId: user)
        XCTAssertEqual(localWorkoutTypes(device), ["Push"])
        XCTAssertEqual(device.storage.fetchExercises(workoutId: item.0.id).count, 1)
        let types = await device.queuedTypes()
        XCTAssertTrue(types.isEmpty)
    }

    func testHistoryIsFetchedPageByPage() async throws {
        let user = UUID(), remote = FakeRemote()
        for i in 0..<5 {
            let item = makeWorkout("W\(i)", user: user, daysAgo: i, exercises: [("Bench", 1)])
            remote.seedWorkout(item.0, exercises: item.1)
        }
        let device = makeDevice(remote: remote, userId: user, pageSize: 2)
        try await device.service.restoreAll(userId: user)
        XCTAssertEqual(localWorkoutTypes(device), ["W0", "W1", "W2", "W3", "W4"])
        // 5 workouts at 2 per page: pages of 2, 2 and 1 (the short page ends the loop).
        XCTAssertEqual(remote.readLog.filter { $0 == "fetchWorkoutHistoryPage" }.count, 3)
    }

    func testFullPageThenEmptyPageEndsTheLoop() async throws {
        let user = UUID(), remote = FakeRemote()
        for i in 0..<4 {
            let item = makeWorkout("W\(i)", user: user, daysAgo: i, exercises: [("Bench", 1)])
            remote.seedWorkout(item.0, exercises: item.1)
        }
        let device = makeDevice(remote: remote, userId: user, pageSize: 2)
        try await device.service.restoreAll(userId: user)
        XCTAssertEqual(localWorkoutTypes(device).count, 4)
        XCTAssertEqual(remote.readLog.filter { $0 == "fetchWorkoutHistoryPage" }.count, 3)
    }

    // MARK: - Tombstones

    func testTombstoneRemovesLocalRecordsAndIsNeverRestored() async throws {
        let user = UUID(), remote = FakeRemote()
        let gone = makeWorkout("Gone", user: user, exercises: [("Bench", 2)])
        let kept = makeWorkout("Kept", user: user, daysAgo: 1, exercises: [("Row", 2), ("Curl", 2)])
        remote.seedWorkout(gone.0, exercises: gone.1)          // cloud still has it...
        remote.seedTombstone(.workout, gone.0.id)              // ...but it was deleted elsewhere
        remote.seedWorkout(kept.0, exercises: kept.1)
        remote.seedTombstone(.exercise, kept.1[1].0.id)        // one exercise of Kept was deleted
        remote.seedTombstone(.set, kept.1[0].1[0].id)          // and one set
        let device = makeDevice(remote: remote, userId: user)
        saveLocally(gone, on: device)                          // this phone still has the old copy

        try await device.service.restoreAll(userId: user)

        XCTAssertEqual(localWorkoutTypes(device), ["Kept"])
        XCTAssertNil(device.storage.fetchWorkout(id: gone.0.id))
        XCTAssertEqual(device.storage.fetchExercises(workoutId: kept.0.id).count, 1)
        XCTAssertEqual(device.storage.fetchSets(exerciseId: kept.1[0].0.id).count, 1)
        let types = await device.queuedTypes()
        XCTAssertTrue(types.isEmpty, "a tombstoned record must not be re-uploaded: \(types)")
    }

    func testTombstonedRestDayIsDeletedAndNotRestored() async throws {
        let user = UUID(), remote = FakeRemote()
        let removed = RestDay(id: UUID(), userId: user, date: Date().startOfDay, createdAt: Date())
        let kept = RestDay(id: UUID(), userId: user, date: Date().startOfDay.addingTimeInterval(-86_400 * 3), createdAt: Date())
        remote.seedRestDay(removed); remote.seedRestDay(kept)
        remote.seedTombstone(.restDay, removed.id)
        let device = makeDevice(remote: remote, userId: user)
        device.storage.restoreRestDays([removed])               // local copy of the removed day
        try await device.service.restoreAll(userId: user)
        let days = device.storage.fetchRestDays(userId: user)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days.first?.id, kept.id)
    }

    func testTombstonePurgesPendingUpsertsButKeepsDeletes() async throws {
        let user = UUID(), remote = FakeRemote()
        let device = makeDevice(remote: remote, userId: user)
        let doomed = makeWorkout("Doomed", user: user, exercises: [("Bench", 2)])
        let alive = makeWorkout("Alive", user: user, daysAgo: 1, exercises: [("Row", 1)])
        // Both were logged here and are still queued (offline); "Doomed" was deleted on another device.
        for item in [doomed, alive] {
            device.workouts.importWorkout(item.0, exercises: item.1.map(\.0),
                                          sets: Dictionary(uniqueKeysWithValues: item.1.map { ($0.0.id, $0.1) }))
        }
        var edited = doomed.0; edited.workoutType = "Doomed edited"
        device.workouts.updateWorkout(edited)
        device.workouts.deleteSet(doomed.1[0].1[0])             // a pending delete + tombstone must survive
        remote.seedTombstone(.workout, doomed.0.id)

        try await device.service.restoreAll(userId: user)

        let ops = await device.queue.queuedOperations()
        let decoder = JSONDecoder()
        for op in ops where op.type == .insertWorkout || op.type == .updateWorkout {
            XCTAssertNotEqual(try decoder.decode(Workout.self, from: op.payload).id, doomed.0.id)
        }
        for op in ops where op.type == .insertExercises {
            XCTAssertTrue(try decoder.decode([Exercise].self, from: op.payload).allSatisfy { $0.workoutId != doomed.0.id })
        }
        for op in ops where op.type == .insertSet {
            XCTAssertNotEqual(try decoder.decode(WorkoutSet.self, from: op.payload).exerciseId, doomed.1[0].0.id)
        }
        XCTAssertTrue(ops.contains { $0.type == .deleteSet }, "pending deletes stay queued")
        XCTAssertTrue(ops.contains { $0.type == .insertTombstone }, "pending tombstones stay queued")

        await device.stack.flushAll()
        XCTAssertNil(remote.workouts[doomed.0.id], "no stray cloud row for the deleted workout")
        XCTAssertNotNil(remote.workouts[alive.0.id])
        XCTAssertNil(device.storage.fetchWorkout(id: doomed.0.id))
    }

    // MARK: - Local pending changes, active workout

    func testPendingLocalChangeWinsOverCloudCopy() async throws {
        let user = UUID(), remote = FakeRemote()
        let item = makeWorkout("Push", user: user, exercises: [("Bench", 2)])
        remote.seedWorkout(item.0, exercises: item.1)
        let device = makeDevice(remote: remote, userId: user)
        try await device.service.restoreAll(userId: user)

        var edited = item.0
        edited.workoutType = "Local Edit"
        device.workouts.updateWorkout(edited)                   // queued, not uploaded yet
        var cloud = item.0
        cloud.workoutType = "Cloud Edit"                         // changed elsewhere meanwhile
        remote.seedWorkout(cloud, exercises: item.1)

        let summary = try await device.service.restoreAll(userId: user)

        XCTAssertEqual(device.storage.fetchWorkout(id: item.0.id)?.workoutType, "Local Edit")
        XCTAssertEqual(summary.workoutsSkippedPending, 1)
        await device.stack.flushAll()
        XCTAssertEqual(remote.workouts[item.0.id]?.workoutType, "Local Edit", "the pending change then uploads")
    }

    func testRecordWhoseOnlyQueueStateIsADeadLetterCountsAsPending() async throws {
        let user = UUID(), remote = FakeRemote()
        let item = makeWorkout("Push", user: user, exercises: [("Bench", 2)])
        remote.seedWorkout(item.0, exercises: item.1)
        let device = makeDevice(remote: remote, userId: user)
        try await device.service.restoreAll(userId: user)          // normal rules from here on

        var edited = item.0
        edited.workoutType = "Local Edit"
        device.workouts.updateWorkout(edited)
        remote.script = { _, _ in QueueTestError.postgres("23514") }   // the upload is dead-lettered
        await device.stack.flushAll()
        let deadCount = await device.queue.failedCount
        XCTAssertEqual(deadCount, 1)
        remote.script = nil
        var cloud = item.0
        cloud.workoutType = "Cloud Edit"
        remote.seedWorkout(cloud, exercises: item.1)

        try await device.service.restoreAll(userId: user)
        XCTAssertEqual(device.storage.fetchWorkout(id: item.0.id)?.workoutType, "Local Edit", "dead letter = pending: local wins")

        // The revived operation then reaches the cloud.
        _ = await device.queue.retryFailed()
        await device.stack.flushAll()
        XCTAssertEqual(remote.workouts[item.0.id]?.workoutType, "Local Edit")
    }

    func testPendingSetChangeKeepsTheWholeWorkoutLocal() async throws {
        let user = UUID(), remote = FakeRemote()
        let item = makeWorkout("Push", user: user, exercises: [("Bench", 2)])
        remote.seedWorkout(item.0, exercises: item.1)
        let device = makeDevice(remote: remote, userId: user)
        try await device.service.restoreAll(userId: user)

        var set = item.1[0].1[0]
        set.weightLbs = 300
        device.workouts.updateSet(set)
        var cloudSet = set
        cloudSet.weightLbs = 111
        remote.seedWorkout(item.0, exercises: [(item.1[0].0, [cloudSet, item.1[0].1[1]])])

        try await device.service.restoreAll(userId: user)
        let stored = device.storage.fetchSets(exerciseId: item.1[0].0.id).first { $0.id == set.id }
        XCTAssertEqual(stored?.weightLbs, 300)
    }

    func testActiveWorkoutIsLeftUntouched() async throws {
        let user = UUID(), remote = FakeRemote()
        let item = makeWorkout("Cloud Name", user: user, exercises: [("Bench", 2)])
        remote.seedWorkout(item.0, exercises: item.1)
        let device = makeDevice(remote: remote, userId: user)
        var local = item.0
        local.workoutType = "Active Local"
        device.storage.saveWorkout(local)
        device.active.value = [item.0.id]

        let summary = try await device.service.restoreAll(userId: user)

        XCTAssertEqual(device.storage.fetchWorkout(id: item.0.id)?.workoutType, "Active Local")
        XCTAssertEqual(summary.workoutsSkippedActive, 1)
        XCTAssertTrue(device.storage.fetchExercises(workoutId: item.0.id).isEmpty)
        let types = await device.queuedTypes()
        XCTAssertTrue(types.isEmpty)
    }

    // MARK: - Junk

    func testEmptyWorkoutsAndSetlessExercisesAreNotRestoredOrDeletedRemotely() async throws {
        let user = UUID(), remote = FakeRemote()
        let empty = makeWorkout("Empty", user: user, daysAgo: 1)
        let setless = makeWorkout("Setless", user: user, daysAgo: 2, exercises: [("Bench", 0)])
        let mixed = makeWorkout("Mixed", user: user, daysAgo: 3, exercises: [("Squat", 2), ("Never Done", 0)])
        for item in [empty, setless, mixed] { remote.seedWorkout(item.0, exercises: item.1) }
        let device = makeDevice(remote: remote, userId: user)

        let summary = try await device.service.restoreAll(userId: user)

        XCTAssertEqual(localWorkoutTypes(device), ["Mixed"])
        let exercises = device.storage.fetchExercises(workoutId: mixed.0.id)
        XCTAssertEqual(exercises.map(\.name), ["Squat"])
        XCTAssertEqual(summary.workoutsSkippedEmpty, 2)
        XCTAssertEqual(remote.workouts.count, 3, "nothing is deleted from the cloud")
        XCTAssertEqual(remote.exercises.count, 3)
        XCTAssertTrue(remote.calls.allSatisfy { !$0.hasPrefix("delete") })
    }

    // MARK: - PRs

    func testPersonalRecordsAreRecomputedLocallyWithoutCloudPROps() async throws {
        let user = UUID(), remote = FakeRemote()
        let a = makeWorkout("Push", user: user, daysAgo: 1, exercises: [("Bench", 3)])
        let b = makeWorkout("Push", user: user, daysAgo: 5, exercises: [("Bench", 2), ("Row", 2)])
        for item in [a, b] { remote.seedWorkout(item.0, exercises: item.1) }
        let device = makeDevice(remote: remote, userId: user)

        try await device.service.restoreAll(userId: user)

        let names = Set(device.storage.fetchPersonalRecords(userId: user).compactMap(\.exerciseName))
        XCTAssertEqual(names, ["Bench", "Row"])
        let types = await device.queuedTypes()
        XCTAssertFalse(types.contains(.insertPersonalRecord))
        XCTAssertTrue(types.isEmpty)
        await device.stack.flushAll()
        XCTAssertTrue(remote.personalRecords.isEmpty)
    }

    // MARK: - Repair upload

    func testLocalOnlyRowsAreUploadedAfterACompleteFetch() async throws {
        let user = UUID(), remote = FakeRemote()
        let onCloud = makeWorkout("On Cloud", user: user, daysAgo: 9, exercises: [("Bench", 2)])
        remote.seedWorkout(onCloud.0, exercises: onCloud.1)
        let device = makeDevice(remote: remote, userId: user)

        let lost = makeWorkout("Lost", user: user, daysAgo: 1, exercises: [("Squat", 3), ("Never Done", 0)])
        let empty = makeWorkout("Empty Local", user: user, daysAgo: 2)
        let setlessOnly = makeWorkout("Setless Local", user: user, daysAgo: 3, exercises: [("Curl", 0)])
        let deletedElsewhere = makeWorkout("Deleted Elsewhere", user: user, daysAgo: 4, exercises: [("Row", 2)])
        for item in [lost, empty, setlessOnly, deletedElsewhere] { saveLocally(item, on: device) }
        remote.seedTombstone(.workout, deletedElsewhere.0.id)
        let lostRest = RestDay(id: UUID(), userId: user, date: Date().startOfDay, createdAt: Date())
        device.storage.restoreRestDays([lostRest])

        let summary = try await device.service.restoreAll(userId: user)
        XCTAssertEqual(summary.repairedWorkouts, 1)
        XCTAssertEqual(summary.repairedRestDays, 1)
        await device.stack.flushAll()

        XCTAssertNotNil(remote.workouts[lost.0.id])
        XCTAssertNil(remote.workouts[empty.0.id], "empty workouts are never uploaded")
        XCTAssertNil(remote.workouts[setlessOnly.0.id])
        XCTAssertNil(remote.workouts[deletedElsewhere.0.id], "a tombstoned workout is not resurrected")
        XCTAssertEqual(remote.exercises.values.filter { $0.workoutId == lost.0.id }.map(\.name), ["Squat"])
        XCTAssertEqual(remote.sets.values.filter { $0.exerciseId == lost.1[0].0.id }.count, 3)
        XCTAssertEqual(remote.restDays.count, 1)
    }

    func testCloudWorkoutWithNothingInItGetsItsLocalExercisesBack() async throws {
        let user = UUID(), remote = FakeRemote()
        let item = makeWorkout("Push", user: user, exercises: [("Bench", 2)])
        remote.seedWorkout(item.0, exercises: [])               // header arrived, children were lost
        let device = makeDevice(remote: remote, userId: user)
        saveLocally(item, on: device)

        try await device.service.restoreAll(userId: user)
        await device.stack.flushAll()

        XCTAssertEqual(remote.exercises.count, 1)
        XCTAssertEqual(remote.sets.count, 2)
        XCTAssertEqual(device.storage.fetchExercises(workoutId: item.0.id).count, 1, "local copy is kept")
    }

    func testNothingIsRepairedWhenTheFetchFailsPartway() async throws {
        let user = UUID(), remote = FakeRemote()
        for i in 0..<5 {
            let item = makeWorkout("W\(i)", user: user, daysAgo: i + 10, exercises: [("Bench", 1)])
            remote.seedWorkout(item.0, exercises: item.1)
        }
        let device = makeDevice(remote: remote, userId: user, pageSize: 2)
        let localOnly = makeWorkout("Local Only", user: user, exercises: [("Squat", 2)])
        saveLocally(localOnly, on: device)
        remote.readScript = { name, count in
            name == "fetchWorkoutHistoryPage" && count == 1 ? QueueTestError.offline : nil
        }

        do {
            try await device.service.restoreAll(userId: user)
            XCTFail("expected the failed page to fail the restore")
        } catch {}

        let types = await device.queuedTypes()
        XCTAssertTrue(types.isEmpty, "a partial fetch must not look like 'missing in the cloud': \(types)")
        XCTAssertNil(device.service.lastSuccessfulRestore(userId: user))
        XCTAssertFalse(device.service.isRunning)

        remote.readScript = nil                                  // back online: the retry completes and repairs
        let summary = try await device.service.restoreAll(userId: user)
        XCTAssertEqual(summary.repairedWorkouts, 1)
        XCTAssertNotNil(device.service.lastSuccessfulRestore(userId: user))
    }

    // MARK: - User change, schedule, timeout

    func testRestoreStopsWhenTheUserChangesMidway() async throws {
        let user = UUID(), remote = FakeRemote()
        for i in 0..<6 {
            let item = makeWorkout("W\(i)", user: user, daysAgo: i, exercises: [("Bench", 1)])
            remote.seedWorkout(item.0, exercises: item.1)
        }
        let device = makeDevice(remote: remote, userId: user, pageSize: 2)
        let signedIn = device.signedIn
        remote.onRead = { name, count in
            if name == "fetchWorkoutHistoryPage" && count == 1 { signedIn.value = UUID() }
        }
        do {
            try await device.service.restoreAll(userId: user)
            XCTFail("expected userChanged")
        } catch let error as RestoreError {
            XCTAssertEqual(error, .userChanged)
        }
        XCTAssertEqual(localWorkoutTypes(device).count, 2, "only the first page was applied")
        let types = await device.queuedTypes()
        XCTAssertTrue(types.isEmpty)
        XCTAssertNil(device.service.lastSuccessfulRestore(userId: user))
    }

    func testRestoreIsDueOnlyEverySixHours() async throws {
        let user = UUID(), remote = FakeRemote()
        let clock = TestBox(Date())
        let stack = OutboxTestStack(userId: user, remote: remote)
        let service = SyncRestoreService(
            remote: remote, storage: stack.storage, queue: stack.queue,
            prRepository: PRRepository(localStorage: stack.storage, offlineQueueManager: stack.queue),
            currentUserId: { user },
            defaults: UserDefaults(suiteName: "restore-\(UUID().uuidString)") ?? .standard,
            now: { clock.value }
        )
        XCTAssertTrue(service.isRestoreDue(userId: user))
        try await service.restoreAll(userId: user)
        XCTAssertFalse(service.isRestoreDue(userId: user))
        clock.value = clock.value.addingTimeInterval(5 * 3600)
        XCTAssertFalse(service.isRestoreDue(userId: user))
        clock.value = clock.value.addingTimeInterval(2 * 3600)
        XCTAssertTrue(service.isRestoreDue(userId: user))
        XCTAssertTrue(service.isRestoreDue(userId: UUID()), "per user")
    }

    func testDeadlineThrowsWhenTheOperationIsTooSlow() async {
        do {
            _ = try await SyncRestoreService.withDeadline(0.05) {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return 1
            }
            XCTFail("expected timeout")
        } catch let error as RestoreError {
            XCTAssertEqual(error, .timedOut)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    // MARK: - Onboarding decision

    func testExistingCloudProfileSkipsOnboardingAndIsSavedLocally() async throws {
        let user = UUID(), remote = FakeRemote()
        remote.seedProfile(makeProfile(user))
        let device = makeDevice(remote: remote, userId: user)
        let lookup = await device.service.lookUpAccountProfile(userId: user)
        XCTAssertEqual(lookup, .existing)
        XCTAssertEqual(device.storage.fetchProfile(userId: user)?.avoidExercises, ["Behind Neck Press"])
        let types = await device.queuedTypes()
        XCTAssertTrue(types.isEmpty)
    }

    func testNoCloudProfileMeansOnboarding() async {
        let user = UUID()
        let device = makeDevice(remote: FakeRemote(), userId: user)
        let lookup = await device.service.lookUpAccountProfile(userId: user)
        XCTAssertEqual(lookup, .new)
        XCTAssertNil(device.storage.fetchProfile(userId: user))
    }

    func testOfflineLookupIsUnreachableNotNew() async {
        let user = UUID(), remote = FakeRemote()
        remote.readScript = { _, _ in QueueTestError.offline }
        let device = makeDevice(remote: remote, userId: user)
        let lookup = await device.service.lookUpAccountProfile(userId: user)
        XCTAssertEqual(lookup, .unreachable)
    }

    func testSettingUpAsNewNeverOverwritesAnExistingCloudProfile() async {
        let user = UUID(), remote = FakeRemote()
        remote.seedProfile(makeProfile(user, name: "Original"))
        let device = makeDevice(remote: remote, userId: user)
        var saved: [UserProfile] = []
        let fresh = makeProfile(user, name: "Fresh Onboarding")

        let result = await device.service.saveNewProfileUnlessAccountHasOne(fresh) { saved.append($0) }

        XCTAssertEqual(result, .adoptedExisting)
        XCTAssertTrue(saved.isEmpty, "the new profile must not be saved or uploaded")
        XCTAssertEqual(device.storage.fetchProfile(userId: user)?.displayName, "Original")
        let types = await device.queuedTypes()
        XCTAssertFalse(types.contains(.upsertProfile))
    }

    func testSettingUpAsNewSavesWhenTheAccountReallyHasNoProfile() async {
        let user = UUID()
        let device = makeDevice(remote: FakeRemote(), userId: user)
        var saved: [UserProfile] = []
        let result = await device.service.saveNewProfileUnlessAccountHasOne(makeProfile(user, name: "New")) { saved.append($0) }
        XCTAssertEqual(result, .saved)
        XCTAssertEqual(saved.first?.displayName, "New")
    }

    func testSettingUpAsNewWhileOfflineSavesNothing() async {
        let user = UUID(), remote = FakeRemote()
        remote.readScript = { _, _ in QueueTestError.offline }
        let device = makeDevice(remote: remote, userId: user)
        var saved: [UserProfile] = []
        let result = await device.service.saveNewProfileUnlessAccountHasOne(makeProfile(user)) { saved.append($0) }
        XCTAssertEqual(result, .couldNotVerify)
        XCTAssertTrue(saved.isEmpty)
    }

    // MARK: - First reconciliation (existing install, local is authoritative)

    func testExistingInstallKeepsAndUploadsLocalEditsAndPrunesCloudOnlyChildren() async throws {
        let user = UUID(), remote = FakeRemote()
        // Local: the user edited this workout in History (3 sets, new weights, new name).
        var local = makeWorkout("Edited Locally", user: user, exercises: [("Bench", 3)])
        let device = makeDevice(remote: remote, userId: user)
        saveLocally(local, on: device)
        device.storage.saveProfile(makeProfile(user, name: "Local Name"))

        // Cloud: the stale pre-edit copy, plus an exercise and a set the user had removed locally.
        var stale = local.0
        stale.workoutType = "Stale Cloud"
        let staleSets = local.1[0].1.prefix(2).map { set -> WorkoutSet in var s = set; s.weightLbs = 50; return s }
        let cloudOnlyExercise = Exercise.create(workoutId: stale.id, name: "Cloud Only", muscleGroup: "Chest", orderIndex: 5,
                                                targetSets: 1, targetReps: "8", targetRir: nil, restSeconds: 60, coachNote: nil)
        let cloudOnlySet = WorkoutSet.create(exerciseId: cloudOnlyExercise.id, setNumber: 1, weightLbs: 10, reps: 5, rir: nil)
        remote.seedWorkout(stale, exercises: [(local.1[0].0, Array(staleSets)), (cloudOnlyExercise, [cloudOnlySet])])
        remote.seedProfile(makeProfile(user, name: "Cloud Name"))
        local.0.workoutType = "Edited Locally"

        let summary = try await device.service.restoreAll(userId: user)

        XCTAssertTrue(summary.reconciled)
        XCTAssertEqual(summary.reconciledWorkouts, 1)
        XCTAssertEqual(device.storage.fetchWorkout(id: local.0.id)?.workoutType, "Edited Locally", "local is kept")
        XCTAssertEqual(device.storage.fetchExercises(workoutId: local.0.id).map(\.name), ["Bench"], "cloud-only exercise is not added")
        XCTAssertEqual(device.storage.fetchSets(exerciseId: local.1[0].0.id).count, 3)
        XCTAssertEqual(device.storage.fetchProfile(userId: user)?.displayName, "Local Name")

        await device.stack.flushAll()
        XCTAssertEqual(remote.workouts[local.0.id]?.workoutType, "Edited Locally")
        XCTAssertEqual(remote.sets.values.filter { $0.exerciseId == local.1[0].0.id }.count, 3)
        XCTAssertTrue(remote.sets.values.filter { $0.exerciseId == local.1[0].0.id }.allSatisfy { $0.weightLbs >= 100 })
        XCTAssertNil(remote.exercises[cloudOnlyExercise.id], "cloud-only exercise is deleted")
        XCTAssertNil(remote.sets[cloudOnlySet.id])
        XCTAssertTrue(remote.tombstones.contains("exercise:\(cloudOnlyExercise.id.uuidString)"))
        XCTAssertTrue(remote.tombstones.contains("set:\(cloudOnlySet.id.uuidString)"))
        let cloudProfile = try await remote.fetchProfile(userId: user)
        XCTAssertEqual(cloudProfile?.displayName, "Local Name")
        XCTAssertTrue(device.service.isFirstReconciliationDone(userId: user))
    }

    func testReconciliationStillAddsWorkoutsFromOtherDevices() async throws {
        let user = UUID(), remote = FakeRemote()
        let device = makeDevice(remote: remote, userId: user)
        saveLocally(makeWorkout("Mine", user: user, exercises: [("Bench", 2)]), on: device)
        let theirs = makeWorkout("From Phone B", user: user, daysAgo: 3, exercises: [("Row", 2)])
        let gone = makeWorkout("Deleted Elsewhere", user: user, daysAgo: 4, exercises: [("Row", 2)])
        remote.seedWorkout(theirs.0, exercises: theirs.1)
        remote.seedWorkout(gone.0, exercises: gone.1)
        remote.seedTombstone(.workout, gone.0.id)

        try await device.service.restoreAll(userId: user)

        XCTAssertEqual(localWorkoutTypes(device), ["From Phone B", "Mine"])
        XCTAssertEqual(device.storage.fetchExercises(workoutId: theirs.0.id).count, 1)
    }

    func testEmptyLocalWorkoutNeverDeletesCloudChildren() async throws {
        let user = UUID(), remote = FakeRemote()
        let item = makeWorkout("Push", user: user, exercises: [("Bench", 2)])
        remote.seedWorkout(item.0, exercises: item.1)
        let device = makeDevice(remote: remote, userId: user)
        device.storage.saveWorkout(item.0)                       // header only: local copy is empty/damaged

        try await device.service.restoreAll(userId: user)
        await device.stack.flushAll()

        XCTAssertEqual(remote.exercises.count, 1)
        XCTAssertEqual(remote.sets.count, 2)
        XCTAssertTrue(remote.calls.allSatisfy { !$0.hasPrefix("deleteExercise") && !$0.hasPrefix("deleteSet") })
        XCTAssertTrue(remote.tombstones.isEmpty)
        XCTAssertTrue(device.storage.fetchExercises(workoutId: item.0.id).isEmpty, "nothing is added locally either")
    }

    func testFreshInstallUsesRemoteWinsAndMarksReconciliationDone() async throws {
        let user = UUID(), remote = FakeRemote()
        let item = makeWorkout("Cloud", user: user, exercises: [("Bench", 2)])
        remote.seedWorkout(item.0, exercises: item.1)
        let device = makeDevice(remote: remote, userId: user)
        XCTAssertFalse(device.service.isFirstReconciliationDone(userId: user))
        let summary = try await device.service.restoreAll(userId: user)
        XCTAssertFalse(summary.reconciled)
        XCTAssertTrue(device.service.isFirstReconciliationDone(userId: user))
        let types = await device.queuedTypes()
        XCTAssertTrue(types.isEmpty)
    }

    func testRestoredProfileOnAnEmptyDeviceDoesNotCountAsExistingData() async throws {
        let user = UUID(), remote = FakeRemote()
        remote.seedProfile(makeProfile(user))
        let device = makeDevice(remote: remote, userId: user)
        _ = await device.service.lookUpAccountProfile(userId: user)   // blocking path saved the profile
        let summary = try await device.service.restoreAll(userId: user, assumeFreshInstall: true)
        XCTAssertFalse(summary.reconciled)
        let types = await device.queuedTypes()
        XCTAssertTrue(types.isEmpty)
    }

    func testReconciliationIsMarkedDoneOnlyAfterAFullRun_ThenRemoteWinsAgain() async throws {
        let user = UUID(), remote = FakeRemote()
        let item = makeWorkout("Push", user: user, exercises: [("Bench", 2)])
        remote.seedWorkout(item.0, exercises: item.1)
        let device = makeDevice(remote: remote, userId: user)
        saveLocally(item, on: device)
        remote.readScript = { name, _ in name == "fetchRestDays" ? QueueTestError.offline : nil }

        do { try await device.service.restoreAll(userId: user); XCTFail("expected failure") } catch {}
        XCTAssertFalse(device.service.isFirstReconciliationDone(userId: user))

        remote.readScript = nil
        let first = try await device.service.restoreAll(userId: user)
        XCTAssertTrue(first.reconciled)
        XCTAssertTrue(device.service.isFirstReconciliationDone(userId: user))
        await device.stack.flushAll()

        // Normal rules now: a newer cloud copy wins over the (unchanged, non-pending) local one.
        var cloud = item.0
        cloud.workoutType = "Changed on Phone B"
        remote.seedWorkout(cloud, exercises: item.1)
        let second = try await device.service.restoreAll(userId: user)
        XCTAssertFalse(second.reconciled)
        XCTAssertEqual(device.storage.fetchWorkout(id: item.0.id)?.workoutType, "Changed on Phone B")
    }

    // MARK: - Two devices

    func testTwoDevicesConvergeWithoutDuplicatesOrResurrection() async throws {
        let user = UUID(), cloud = FakeRemote()
        let deviceA = makeDevice(remote: cloud, userId: user)
        let deviceB = makeDevice(remote: cloud, userId: user)

        // Phone A logs two older workouts and uploads them; phone B picks them up.
        let older = makeWorkout("Old Pull", user: user, daysAgo: 20, exercises: [("Row", 2)])
        let edited = makeWorkout("Push", user: user, daysAgo: 10, exercises: [("Bench", 2)])
        for item in [older, edited] {
            deviceA.workouts.importWorkout(item.0, exercises: item.1.map(\.0),
                                           sets: Dictionary(uniqueKeysWithValues: item.1.map { ($0.0.id, $0.1) }))
        }
        await deviceA.stack.flushAll()
        try await deviceA.service.restoreAll(userId: user)       // A's one-time reconciliation (nothing differs)
        try await deviceB.service.restoreAll(userId: user)
        XCTAssertEqual(localWorkoutTypes(deviceB), ["Old Pull", "Push"])

        // A goes offline and logs a new workout (queued only).
        let fresh = makeWorkout("Legs", user: user, daysAgo: 0, exercises: [("Squat", 3)])
        deviceA.workouts.importWorkout(fresh.0, exercises: fresh.1.map(\.0),
                                       sets: Dictionary(uniqueKeysWithValues: fresh.1.map { ($0.0.id, $0.1) }))

        // B, online, deletes the old workout and renames the other.
        let oldOnB = try XCTUnwrap(deviceB.storage.fetchWorkout(id: older.0.id))
        deviceB.workouts.deleteWorkout(Workout(from: oldOnB))
        var rename = Workout(from: try XCTUnwrap(deviceB.storage.fetchWorkout(id: edited.0.id)))
        rename.workoutType = "Push (edited on B)"
        deviceB.workouts.updateWorkout(rename)
        await deviceB.stack.flushAll()

        // Both reconnect: flush, then restore.
        await deviceA.stack.flushAll()
        try await deviceA.service.restoreAll(userId: user)
        try await deviceB.service.restoreAll(userId: user)
        await deviceA.stack.flushAll()
        await deviceB.stack.flushAll()

        let expected = ["Legs", "Push (edited on B)"]
        XCTAssertEqual(localWorkoutTypes(deviceA), expected, "A sees B's delete and edit")
        XCTAssertEqual(localWorkoutTypes(deviceB), expected, "B sees A's workout")
        XCTAssertEqual(Set(cloud.workouts.values.map(\.workoutType)), Set(expected), "nothing was resurrected in the cloud")
        for device in [deviceA, deviceB] {
            XCTAssertEqual(device.storage.fetchExercises(workoutId: fresh.0.id).count, 1, "no duplicate exercises")
            let squat = try XCTUnwrap(device.storage.fetchExercises(workoutId: fresh.0.id).first)
            XCTAssertEqual(device.storage.fetchSets(exerciseId: try XCTUnwrap(squat.id)).count, 3, "no duplicate sets")
        }
    }
}
