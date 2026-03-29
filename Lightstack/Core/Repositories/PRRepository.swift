import Foundation

/// Coordinates local + remote personal record data access.
/// Detects new PRs during set logging and stores them.
final class PRRepository {

    private let localStorage: LocalStorageService
    private let supabaseService: SupabaseService
    private let offlineQueueManager: OfflineQueueManager

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
    func checkAndRecordPR(
        userId: UUID,
        exerciseName: String,
        weightLbs: Double,
        reps: Int,
        workoutId: UUID?
    ) -> PersonalRecord? {
        // Calculate estimated 1RM using Brzycki formula
        let newE1RM = weightLbs * (1 + Double(reps) / 30)

        // Fetch existing PR for this exercise
        let existingPR = fetchPR(userId: userId, exerciseName: exerciseName)
        let existingE1RM = existingPR?.estimatedOneRepMax ?? 0

        // Check if new set beats existing PR
        guard newE1RM > existingE1RM else {
            return nil
        }

        // Create new PR record
        let pr = PersonalRecord.create(
            userId: userId,
            exerciseName: exerciseName,
            weightLbs: weightLbs,
            reps: reps,
            workoutId: workoutId
        )

        // Save locally
        localStorage.savePersonalRecord(pr)

        // Sync to Supabase, queue on failure
        Task {
            do {
                try await supabaseService.insertPersonalRecord(pr)
            } catch {
                offlineQueueManager.enqueue(.insertPersonalRecord, payload: pr)
            }
        }

        return pr
    }
}
