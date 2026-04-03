import Foundation

/// Coordinates local + remote personal record data access.
/// Detects new PRs during set logging and stores them.
final class PRRepository {

    private let localStorage: LocalStorageService
    private let supabaseService: SupabaseService
    private let offlineQueueManager: OfflineQueueManager
    /// Serializes the fetch-compare-write block so concurrent set logs
    /// for the same exercise cannot both read the same baseline and both
    /// create duplicate PR records.
    private let prLock = NSLock()

    init(
        localStorage: LocalStorageService,
        supabaseService: SupabaseService,
        offlineQueueManager: OfflineQueueManager
    ) {
        self.localStorage = localStorage
        self.supabaseService = supabaseService
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

        // Supabase sync happens outside the lock — network I/O must never block it
        Task {
            do {
                try await supabaseService.insertPersonalRecord(pr)
            } catch {
                await offlineQueueManager.enqueue(.insertPersonalRecord, payload: pr)
            }
        }

        return newPR
    }

    // MARK: - Orphan Cleanup

    /// Removes any PR entries that no longer have any corresponding sets in the
    /// local workout database. Called on profile load to handle edge cases where
    /// workouts were deleted before per-exercise recalculation was in place.
    func cleanOrphanedPRs(userId: UUID) {
        let allPRs = localStorage.fetchPersonalRecords(userId: userId)
        for pr in allPRs {
            guard let name = pr.exerciseName else { continue }
            let sets = localStorage.fetchAllSetsForExerciseName(userId: userId, exerciseName: name)
            if sets.isEmpty {
                localStorage.deletePersonalRecord(userId: userId, exerciseName: name)
            }
        }
    }

    // MARK: - Recalculation after deletion

    /// Deletes the stored PR for an exercise and rebuilds it from all remaining sets.
    /// Call this for each exercise in a workout that is being deleted.
    func recalculatePR(userId: UUID, exerciseName: String) {
        prLock.lock()
        defer { prLock.unlock() }

        // Remove the stale PR entry
        localStorage.deletePersonalRecord(userId: userId, exerciseName: exerciseName)

        // Re-derive the best set from remaining data
        let sets = localStorage.fetchAllSetsForExerciseName(userId: userId, exerciseName: exerciseName)
        guard !sets.isEmpty else { return }

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

        guard let best = bestSet else { return }

        let pr = PersonalRecord.create(
            userId: userId,
            exerciseName: exerciseName,
            weightLbs: best.weightLbs,
            reps: Int(best.reps),
            workoutId: best.exercise?.workout?.id
        )
        localStorage.savePersonalRecord(pr)
    }
}
