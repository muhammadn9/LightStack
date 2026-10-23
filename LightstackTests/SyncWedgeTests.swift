import XCTest
@testable import Lightstack

/// Regression tests for the "is_per_arm NOT NULL" sync wedge (bulk exercise insert 400, sets 403).
final class SyncWedgeTests: XCTestCase {

    private func exercise(_ name: String, workoutId: UUID = UUID(), perArm: Bool) -> Exercise {
        Exercise(id: UUID(), workoutId: workoutId, localId: nil, name: name, muscleGroup: "Back", orderIndex: 0,
                 targetSets: 3, targetReps: "8", targetRir: nil, restSeconds: nil, coachNote: nil,
                 syncStatus: .pending, isPerArm: perArm)
    }

    private func set(for exerciseId: UUID) -> WorkoutSet {
        WorkoutSet(id: UUID(), exerciseId: exerciseId, localId: nil, setNumber: 1, weightLbs: 100, reps: 8,
                   rir: 2, userFeedback: nil, isPR: false, syncStatus: .pending, recordedAt: Date())
    }

    func testMixedBatchAlwaysEncodesIsPerArm() throws {
        let batch = [exercise("Row", perArm: false), exercise("Curl", perArm: true)]
        let data = try JSONEncoder().encode(batch)
        let rows = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0]["is_per_arm"] as? Bool, false)
        XCTAssertEqual(rows[1]["is_per_arm"] as? Bool, true)
    }

    func testLegacyQueuedPayloadWithoutKeyIsNormalisedOnReplay() throws {
        // Exactly what an old build queued: no is_per_arm key.
        var legacy = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode([exercise("Row", perArm: false)])) as? [[String: Any]])
        legacy[0].removeValue(forKey: "is_per_arm")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        XCTAssertNil(legacy[0]["is_per_arm"])

        // Replay decodes then re-encodes (see OfflineQueueManager.execute).
        let models = try JSONDecoder().decode([Exercise].self, from: legacyData)
        let resent = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(models)) as? [[String: Any]])
        XCTAssertEqual(resent.first?["is_per_arm"] as? Bool, false)
    }

    func testRefusedParentSurfacesAsFailedAndChildrenWait() async {
        let remote = FakeRemote()
        // Parent refused with a not-null violation; the first set is refused like RLS does without a parent row.
        remote.script = { type, i in
            if type == .insertExercises && i == 0 { return QueueTestError.postgres("23502") }
            if type == .insertSet && i == 1 { return QueueTestError.postgres("42501") }
            return nil
        }
        let userId = UUID()
        let clock = TestBox(Date(timeIntervalSince1970: 1_800_000_000))
        let queue = OfflineQueueManager(
            remote: remote, directory: makeTempDirectory(), now: { clock.value }, ownerProvider: { userId },
            defaults: UserDefaults(suiteName: "wedge-\(UUID().uuidString)") ?? .standard, autoFlush: false)
        let ex = exercise("Row", perArm: false)
        await queue.enqueue(.insertExercises, payload: [ex])
        await queue.enqueue(.insertSet, payload: set(for: ex.id))

        await queue.flush()
        await queue.flush()
        await queue.flush()
        // One refused try (parent missing), then it waits instead of hammering 403s.
        XCTAssertEqual(remote.calls.filter { $0.hasPrefix("insertSet") }.count, 1, "children must wait, not hammer")
        XCTAssertEqual(remote.calls.filter { $0.hasPrefix("insertExercises") }.count, 1)

        let snap = await queue.snapshot()
        XCTAssertEqual(snap.failed, 1)
        XCTAssertEqual(snap.pending, 1)
        let status = BackupStatus.derive(pending: snap.pending, failed: snap.failed, isFlushing: false,
                                         signedOut: false, lastSuccessfulFlush: nil)
        XCTAssertEqual(status, .failed(count: 1))
        let details = await queue.failedSummaries()
        XCTAssertEqual(details.first?.code, "23502")

        // "Back up now": revive the parent; the set then follows.
        clock.value = clock.value.addingTimeInterval(2 * 3600)   // past the set's backoff
        await queue.retryFailed()
        await queue.flush()
        for _ in 0..<3 where await queue.pendingCount > 0 {
            await queue.flush()
        }
        XCTAssertEqual(remote.calls.filter { $0.hasPrefix("insertSet") }.count, 2)
        let after = await queue.snapshot()
        XCTAssertEqual(after.pending + after.failed, 0)
    }
}
