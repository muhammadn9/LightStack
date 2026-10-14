import XCTest
import Supabase
@testable import Lightstack

final class OfflineQueueManagerTests: XCTestCase {

    private var dir: URL!
    private var remote: FakeRemote!
    private var owner: TestBox<UUID?>!
    private var clock: TestBox<Date>!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let userA = UUID()
    private let userB = UUID()

    override func setUp() {
        super.setUp()
        dir = makeTempDirectory()
        remote = FakeRemote()
        owner = TestBox(userA)
        clock = TestBox(Date(timeIntervalSince1970: 1_800_000_000))
        suiteName = "oq-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeManager(directory: URL? = nil, remote: RemoteWriting? = nil) -> OfflineQueueManager {
        let ownerBox = owner!
        let clockBox = clock!
        return OfflineQueueManager(
            remote: remote ?? self.remote,
            directory: directory ?? dir,
            now: { clockBox.value },
            ownerProvider: { ownerBox.value },
            defaults: defaults
        )
    }

    private func waitUntil(_ what: String, _ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for \(what)")
    }

    private func enqueueWorkouts(_ m: OfflineQueueManager, _ labels: [String]) async {
        for l in labels { await m.enqueue(.insertWorkout, payload: makeTestWorkout(l)) }
    }

    // (1) offline enqueue persists
    func testEnqueueWhileOfflinePersists() async {
        let m = makeManager()
        await enqueueWorkouts(m, ["a", "b"])
        let pending = await m.pendingCount
        XCTAssertEqual(pending, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("queue.json").path))
        let stamped = await m.queuedOperations().allSatisfy { $0.ownerUserId == userA }
        XCTAssertTrue(stamped)
    }

    // (2) restart restores
    func testQueueRestoredAfterRestart() async {
        let m1 = makeManager()
        await enqueueWorkouts(m1, ["a", "b", "c"])
        let m2 = makeManager()
        let pending = await m2.pendingCount
        XCTAssertEqual(pending, 3)
    }

    // (3) reconnect + flush empties queue
    func testFlushSuccessEmptiesQueue() async {
        let m = makeManager()
        await enqueueWorkouts(m, ["a", "b"])
        await m.flush()
        let pending = await m.pendingCount
        XCTAssertEqual(pending, 0)
        XCTAssertEqual(remote.calls, ["insertWorkout:a", "insertWorkout:b"])
        let m2 = makeManager()
        let restored = await m2.pendingCount
        XCTAssertEqual(restored, 0)
    }

    // (4) transient failures back off and never drop
    func testTransientFailuresBackOffAndNeverDrop() async {
        remote.script = { _, _ in QueueTestError.offline }
        let m = makeManager()
        await enqueueWorkouts(m, ["a"])
        var lastNext = Date.distantPast
        for round in 1...12 {
            await m.flush()
            let ops = await m.queuedOperations()
            XCTAssertEqual(ops.count, 1, "op dropped in round \(round)")
            XCTAssertEqual(ops.first?.attempts, round)
            let next = try? XCTUnwrap(ops.first?.nextAttemptAt)
            XCTAssertNotNil(next)
            if let next {
                XCTAssertEqual(next.timeIntervalSince(clock.value), OfflineQueueManager.backoff(attempts: round))
                XCTAssertGreaterThanOrEqual(next, lastNext.addingTimeInterval(0))
                lastNext = next
            }
            clock.value = clock.value.addingTimeInterval(2 * 3600) // past any backoff
        }
        XCTAssertEqual(remote.calls.count, 12)
    }

    func testNotDueOperationIsSkipped() async {
        remote.script = { _, i in i == 0 ? QueueTestError.offline : nil }
        let m = makeManager()
        await enqueueWorkouts(m, ["a"])
        await m.flush()
        await m.flush() // backoff not elapsed
        XCTAssertEqual(remote.calls.count, 1)
        clock.value = clock.value.addingTimeInterval(11)
        await m.flush()
        XCTAssertEqual(remote.calls.count, 2)
        let pending = await m.pendingCount
        XCTAssertEqual(pending, 0)
    }

    // (5) permanent -> dead letter; retryFailed restores
    func testPermanentFailureMovesToDeadLetterAndRetryRestores() async {
        remote.script = { _, i in i == 0 ? QueueTestError.postgres("23514") : nil }
        let m = makeManager()
        await enqueueWorkouts(m, ["bad", "good"])
        await m.flush()
        let pending = await m.pendingCount
        let failedCount = await m.failedCount
        XCTAssertEqual(pending, 0)
        XCTAssertEqual(failedCount, 1)
        let dead = await m.failedOperations()
        XCTAssertEqual(dead.first?.lastErrorCode, "23514")
        XCTAssertNotNil(dead.first?.lastErrorMessage)

        // dead letters survive restart and are never retried automatically
        let m2 = makeManager()
        await m2.flush()
        XCTAssertEqual(remote.calls.count, 2)
        let failedAfterRestart = await m2.failedCount
        XCTAssertEqual(failedAfterRestart, 1)

        await m2.retryFailed()
        let revived = await m2.pendingCount
        XCTAssertEqual(revived, 1)
        await m2.flush()
        XCTAssertEqual(remote.calls.last, "insertWorkout:bad")
        let left = await m2.pendingCount
        XCTAssertEqual(left, 0)
    }

    // (6) enqueue during an active flush is not lost
    func testEnqueueDuringActiveFlushIsNotLost() async {
        remote.script = { _, i in i == 1 ? QueueTestError.offline : nil }
        let m = makeManager()
        await enqueueWorkouts(m, ["A"])
        remote.armSuspension()
        let flushTask = Task { await m.flush() }
        await waitUntil("flush to suspend inside execute") { remote.isSuspended }

        await enqueueWorkouts(m, ["B"]) // arrives while the flush awaits the network
        remote.release()
        await flushTask.value

        // B must have been picked up (it fails transiently in this script) and must still be queued.
        XCTAssertEqual(remote.calls, ["insertWorkout:A", "insertWorkout:B"])
        let ops = await m.queuedOperations()
        XCTAssertEqual(ops.count, 1)
        XCTAssertEqual(ops.first?.attempts, 1)
        let restored = await makeManager().pendingCount
        XCTAssertEqual(restored, 1)
    }

    // (7) simultaneous flushes execute each op once
    func testSimultaneousFlushesExecuteEachOpOnce() async {
        let m = makeManager()
        await enqueueWorkouts(m, ["a", "b", "c"])
        remote.armSuspension()
        let t1 = Task { await m.flush() }
        await waitUntil("first flush to suspend") { remote.isSuspended }
        let t2 = Task { await m.flush() }
        let t3 = Task { await m.flush() }
        await t2.value
        await t3.value
        remote.release()
        await t1.value
        XCTAssertEqual(remote.calls.sorted(), ["insertWorkout:a", "insertWorkout:b", "insertWorkout:c"])
        let pending = await m.pendingCount
        XCTAssertEqual(pending, 0)
    }

    // (8) interrupted flush resumes after restart
    func testInterruptedFlushResumesWithoutLoss() async {
        remote.script = { _, i in i == 3 ? QueueTestError.postgres("PGRST301") : nil } // auth stop after 3 ok
        let m1 = makeManager()
        await enqueueWorkouts(m1, ["1", "2", "3", "4", "5", "6"])
        await m1.flush()
        let afterPartial = await m1.pendingCount
        XCTAssertEqual(afterPartial, 3)

        let remote2 = FakeRemote()
        let m2 = makeManager(remote: remote2) // "restart"
        let restored = await m2.pendingCount
        XCTAssertEqual(restored, 3)
        await m2.flush()
        XCTAssertEqual(remote2.calls, ["insertWorkout:4", "insertWorkout:5", "insertWorkout:6"])
        let left = await m2.pendingCount
        XCTAssertEqual(left, 0)
    }

    func testAuthErrorStopsPassWithoutTouchingOperations() async {
        remote.script = { _, _ in QueueTestError.postgres("PGRST301") }
        let m = makeManager()
        await enqueueWorkouts(m, ["a", "b"])
        await m.flush()
        XCTAssertEqual(remote.calls.count, 1)
        let ops = await m.queuedOperations()
        XCTAssertEqual(ops.map(\.attempts), [0, 0])
        XCTAssertTrue(ops.allSatisfy { $0.nextAttemptAt == nil && $0.lastErrorCode == nil })
    }

    // (9) account isolation
    func testAccountSwitchingAndSignOutKeepOperations() async {
        let m = makeManager()
        await enqueueWorkouts(m, ["a1", "a2"])

        owner.value = nil // signed out: nothing runs, nothing is cleared
        await m.flush()
        XCTAssertTrue(remote.calls.isEmpty)
        let storedWhileSignedOut = await m.queuedOperations().count
        XCTAssertEqual(storedWhileSignedOut, 2)

        owner.value = userB
        await m.flush()
        XCTAssertTrue(remote.calls.isEmpty, "user B must not upload user A's changes")
        let bPending = await m.pendingCount
        XCTAssertEqual(bPending, 0)
        let stillStored = await m.queuedOperations().count
        XCTAssertEqual(stillStored, 2)

        owner.value = userA
        await m.flush()
        XCTAssertEqual(remote.calls, ["insertWorkout:a1", "insertWorkout:a2"])
    }

    func testOwnerChangeMidPassStopsThePass() async {
        let ownerBox = owner!, userB = userB
        remote.onCall = { index in if index == 0 { ownerBox.value = userB } }
        let m = makeManager()
        await enqueueWorkouts(m, ["a", "b", "c"])
        await m.flush()
        XCTAssertEqual(remote.calls.count, 1)
        let remaining = await m.queuedOperations().count
        XCTAssertEqual(remaining, 2)
    }

    func testLegacyOperationsAreAdoptedByCurrentUser() async throws {
        let op = QueuedOperation(type: .insertWorkout, payload: try JSONEncoder().encode(makeTestWorkout("legacy")))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode([op]).write(to: dir.appendingPathComponent("queue.json"))
        let m = makeManager()
        await m.flush()
        XCTAssertEqual(remote.calls, ["insertWorkout:legacy"])
    }

    // (10) duplicate replay
    func testDuplicateKeyOnInsertIsTreatedAsSuccess() async {
        remote.script = { _, _ in QueueTestError.postgres("23505") }
        let m = makeManager()
        await enqueueWorkouts(m, ["a"])
        await m.flush()
        let pending = await m.pendingCount
        let failedCount = await m.failedCount
        XCTAssertEqual(pending, 0)
        XCTAssertEqual(failedCount, 0)
    }

    func testForeignKeyViolationBacksOffInsteadOfDeadLettering() async {
        remote.script = { _, _ in QueueTestError.postgres("23503") }
        let m = makeManager()
        await enqueueWorkouts(m, ["a"])
        await m.flush()
        let pending = await m.pendingCount
        let failedCount = await m.failedCount
        XCTAssertEqual(pending, 1)
        XCTAssertEqual(failedCount, 0)
    }

    // (11) large queue
    func testLargeQueueRoundTripsAndFlushesInOrder() async {
        let m = makeManager()
        let start = Date()
        let labels = (0..<2000).map { String(format: "w%04d", $0) }
        await enqueueWorkouts(m, labels)
        let restored = await makeManager().pendingCount
        XCTAssertEqual(restored, 2000)
        await m.flush()
        XCTAssertEqual(remote.calls, labels.map { "insertWorkout:\($0)" })
        let left = await m.pendingCount
        XCTAssertEqual(left, 0)
        XCTAssertLessThan(Date().timeIntervalSince(start), 60)
    }

    // (12) corruption + migration
    func testCorruptFileIsMovedAsideAndValidEntriesRecovered() async throws {
        let good1 = QueuedOperation(type: .insertWorkout, payload: try JSONEncoder().encode(makeTestWorkout("g1")), ownerUserId: userA)
        let good2 = QueuedOperation(type: .insertWorkout, payload: try JSONEncoder().encode(makeTestWorkout("g2")), ownerUserId: userA)
        let encoder = JSONEncoder()
        let g1 = try JSONSerialization.jsonObject(with: encoder.encode(good1))
        let g2 = try JSONSerialization.jsonObject(with: encoder.encode(good2))
        let mixed = try JSONSerialization.data(withJSONObject: [g1, ["bogus": 1], g2])
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try mixed.write(to: dir.appendingPathComponent("queue.json"))

        let m = makeManager()
        let pending = await m.pendingCount
        XCTAssertEqual(pending, 2)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("queue.corrupt-") }, "original must be kept aside: \(files)")
        let m2 = makeManager()
        let again = await m2.pendingCount
        XCTAssertEqual(again, 2)
    }

    func testGarbageFileIsKeptAsideAndQueueStartsEmpty() async throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json at all".utf8).write(to: dir.appendingPathComponent("queue.json"))
        let m = makeManager()
        let pending = await m.pendingCount
        XCTAssertEqual(pending, 0)
        await enqueueWorkouts(m, ["x"])
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("queue.corrupt-") })
    }

    func testLegacyUserDefaultsQueueMigratesOnce() async throws {
        let payload = try JSONEncoder().encode(makeTestWorkout("old"))
        let legacy: [[String: Any]] = [[
            "id": UUID().uuidString, "type": "insertWorkout",
            "payload": payload.base64EncodedString(), "attempts": 2, "enqueuedAt": 700_000_000.0
        ]]
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: OfflineQueueManager.legacyDefaultsKey)

        let m = makeManager()
        let pending = await m.pendingCount
        XCTAssertEqual(pending, 1)
        XCTAssertNotNil(defaults.data(forKey: OfflineQueueManager.legacyDefaultsKey), "legacy key stays for one release")
        XCTAssertTrue(defaults.bool(forKey: OfflineQueueManager.migrationDoneKey))
        await m.flush()
        XCTAssertEqual(remote.calls, ["insertWorkout:old"])

        // Fresh directory but migration already done: must not re-import.
        let m2 = makeManager(directory: makeTempDirectory())
        let none = await m2.pendingCount
        XCTAssertEqual(none, 0)
    }

    // (13) ordering
    func testFlushOrdersParentsBeforeChildrenAndDeletesLast() async {
        let wid = UUID(), other = UUID()
        let ex = Exercise.create(workoutId: wid, name: "Squat", muscleGroup: "Legs", orderIndex: 0,
                                 targetSets: 1, targetReps: "5", targetRir: nil, restSeconds: 90, coachNote: nil)
        let set = WorkoutSet.create(exerciseId: ex.id, setNumber: 1, weightLbs: 100, reps: 5, rir: nil)
        let m = makeManager()
        await m.enqueue(.deleteWorkout, payload: makeTestWorkout("del"))
        await m.enqueue(.insertSet, payload: set)
        await m.enqueue(.insertExercises, payload: [ex])
        await m.enqueue(.updateWorkout, payload: makeTestWorkout("upd"))
        await m.enqueueDeleteExercises(workoutId: other)
        await m.enqueue(.insertWorkout, payload: makeTestWorkout("w1"))
        await m.enqueue(.insertWorkout, payload: makeTestWorkout("w2"))
        await m.flush()
        XCTAssertEqual(remote.calls, [
            "insertWorkout:w1", "insertWorkout:w2", "updateWorkout:upd",
            "deleteExercises:", "insertExercises:Squat", "insertSet:", "deleteWorkout:"
        ])
    }

    func testEnqueueDeleteExercisesSupersedesQueuedInserts() async {
        let wid = UUID()
        let ex = Exercise.create(workoutId: wid, name: "Squat", muscleGroup: "Legs", orderIndex: 0,
                                 targetSets: 1, targetReps: "5", targetRir: nil, restSeconds: 90, coachNote: nil)
        let m = makeManager()
        await m.enqueue(.insertExercises, payload: [ex])
        await m.enqueueDeleteExercises(workoutId: wid)
        let types = await m.queuedOperations().map(\.type)
        XCTAssertEqual(types, [.deleteExercises])
    }

    func testEnqueueDeleteExercisesDuringFlushKeepsNewOperation() async {
        let m = makeManager()
        await enqueueWorkouts(m, ["A"])
        remote.armSuspension()
        let t = Task { await m.flush() }
        await waitUntil("suspend") { remote.isSuspended }
        await m.enqueueDeleteExercises(workoutId: UUID())
        remote.release()
        await t.value
        XCTAssertEqual(remote.calls, ["insertWorkout:A", "deleteExercises:"])
        let pending = await m.pendingCount
        XCTAssertEqual(pending, 0)
    }

    // (14) partial remote success
    func testPartialSuccessRemovesOnlySucceededOps() async {
        remote.script = { _, i in i == 2 ? QueueTestError.offline : nil }
        let m = makeManager()
        await enqueueWorkouts(m, ["a", "b", "c", "d"])
        await m.flush()
        let ops = await m.queuedOperations()
        XCTAssertEqual(ops.count, 1) // a, b, d succeeded; only c (transient failure) remains
        XCTAssertEqual(ops.first?.attempts, 1)
        let restored = await makeManager().pendingCount
        XCTAssertEqual(restored, 1)
    }

    func testCreatedOperationsDecodeLegacyJSONWithoutNewFields() throws {
        let json = """
        {"id":"x","type":"insertSet","payload":"e30=","attempts":3,"enqueuedAt":700000000}
        """
        let op = try JSONDecoder().decode(QueuedOperation.self, from: Data(json.utf8))
        XCTAssertEqual(op.attempts, 3)
        XCTAssertNil(op.ownerUserId)
        XCTAssertNil(op.nextAttemptAt)
    }
}
