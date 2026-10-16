import Foundation

/// Coordinates local + remote personal record data access.
/// Detects new PRs during set logging and stores them.
final class PRRepository {

    private let localStorage: LocalStorageService
    private let offlineQueueManager: OfflineQueueManager
    /// Serializes the fetch-compare-write block so concurrent set logs
    /// for the same exercise cannot both read the same baseline and both
    /// create duplicate PR records.
    private let prLock = NSLock()

    init(
        localStorage: LocalStorageService,
        offlineQueueManager: OfflineQueueManager
    ) {
        self.localStorage = localStorage
        self.offlineQueueManager = offlineQueueManager
    }

    // MARK: - Fetch

    func fetchAllPRs(userId: UUID) -> [PersonalRecord] {
        localStorage.fetchPersonalRecords(userId: userId)
            .map { PersonalRecord(from: $0) }
    }

    func fetchPR(userId: UUID, exerciseName: String) -> PersonalRecord? {
        guard let cdEntity = localStorage.fetchPersonalRecord(userId: userId, exerciseName: exerciseName) else {
            return nil
        }
        return PersonalRecord(from: cdEntity)
    }

    // MARK: - PR Detection

    /// Check if a new set beats the existing PR for this exercise.
    /// Returns the new PersonalRecord if it's a PR, nil otherwise.
    /// Uses NSLock to prevent concurrent set logs from both passing
    /// the same e1RM threshold and creating duplicate PR records.
    func checkAndRecordPR(
        userId: UUID,
        exerciseName: String,
        weightLbs: Double,
        reps: Int,
        workoutId: UUID?
    ) -> PersonalRecord? {
        guard reps > 0, weightLbs > 0 else { return nil }

        var newPR: PersonalRecord?

        // Lock covers the read-compare-write sequence atomically
        prLock.lock()
        defer { prLock.unlock() }

        // Calculate estimated 1RM using Epley formula: weight × (1 + reps/30)
        let newE1RM = weightLbs * (1 + Double(reps) / 30)

        let existingPR = fetchPR(userId: userId, exerciseName: exerciseName)
        let existingE1RM = existingPR?.estimatedOneRepMax ?? 0

        guard newE1RM > existingE1RM else { return nil }

        let pr = PersonalRecord.create(
            userId: userId,
            exerciseName: exerciseName,
            weightLbs: weightLbs,
            reps: reps,
            workoutId: workoutId
        )
        localStorage.savePersonalRecord(pr)
        newPR = pr

        // The cloud PR log is append-only: new records are queued, never deleted remotely.
        // `submit` is synchronous and non-blocking (no network I/O under the lock).
        offlineQueueManager.submit(.insertPersonalRecord, payload: pr, recordKey: pr.id.uuidString)

        return newPR
    }

    // MARK: - Full Repair

    /// Rebuilds every PR from the sets that remain in local storage. Covers both
    /// stale PRs (their sets were removed) and missing ones. Idempotent.
    func recalculateAllPRs(userId: UUID) {
        var names = localStorage.fetchExerciseNamesWithSets(userId: userId)
        for pr in localStorage.fetchPersonalRecords(userId: userId) {
            if let name = pr.exerciseName { names.insert(name) }
        }
        for name in names {
            recalculatePR(userId: userId, exerciseName: name)
        }
    }

    // MARK: - Recalculation after deletion

    /// Rebuilds the local PR for an exercise from all remaining sets (the old local row is
    /// replaced). Cloud PRs are an append-only log: a changed result is queued as one more
    /// record, and nothing is ever deleted remotely. An unchanged result queues nothing.
    /// Call this for each exercise in a workout that is being deleted.
    func recalculatePR(userId: UUID, exerciseName: String) {
        prLock.lock()
        defer { prLock.unlock() }

        let existing = localStorage.fetchPersonalRecords(userId: userId)
            .filter { $0.exerciseName == exerciseName }

        // Re-derive the best set from remaining data
        let sets = localStorage.fetchAllSetsForExerciseName(userId: userId, exerciseName: exerciseName)

        // Pick the set with the highest estimated 1RM (Epley formula)
        var bestSet: CDWorkoutSet?
        var bestE1RM: Double = 0
        for set in sets {
            let reps = Int(set.reps)
            let weight = set.weightLbs
            guard reps > 0, weight > 0 else { continue }
            let e1rm = weight * (1 + Double(reps) / 30)
            if e1rm > bestE1RM {
                bestE1RM = e1rm
                bestSet = set
            }
        }

        guard let best = bestSet else {
            // No lifts left: drop the stale local PR (cloud log keeps its history).
            if !existing.isEmpty {
                localStorage.deletePersonalRecord(userId: userId, exerciseName: exerciseName)
            }
            return
        }

        var pr = PersonalRecord.create(
            userId: userId,
            exerciseName: exerciseName,
            weightLbs: best.weightLbs,
            reps: Int(best.reps),
            workoutId: best.exercise?.workout?.id
        )
        // Date the PR by when the set was lifted, not when it was recalculated —
        // imports would otherwise all show the import day.
        if let lifted = best.exercise?.workout?.date ?? best.recordedAt {
            pr.dateAchieved = lifted
        }

        if existing.count == 1, let current = existing.first,
           current.weightLbs == pr.weightLbs, Int(current.reps) == pr.reps,
           current.workoutId == pr.workoutId,
           let achieved = current.dateAchieved, abs(achieved.timeIntervalSince(pr.dateAchieved)) < 1 {
            return
        }

        localStorage.deletePersonalRecord(userId: userId, exerciseName: exerciseName)
        localStorage.savePersonalRecord(pr)
        offlineQueueManager.submit(.insertPersonalRecord, payload: pr, recordKey: pr.id.uuidString)
    }
}
