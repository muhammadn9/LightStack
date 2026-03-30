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
}
