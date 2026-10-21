import Foundation

/// Coordinates local + remote personal record data access.
/// Detects new PRs during set logging and stores them.
///
/// Design: exactly ONE personal record per exercise, the set with the highest estimated 1RM
/// (Epley). A better set replaces the old row locally and queues a cloud delete of the older
/// rows, so the cloud table ends up with one row per exercise too. Names are stored sanitized
/// (markdown such as "**Chest** Bench Press" is stripped).
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

    // MARK: - Names

    /// The name a PR is stored under: markdown and prompt-injection junk stripped.
    static func recordName(for exerciseName: String) -> String {
        let cleaned = InputSanitizer.sanitizeLabel(exerciseName)
        return cleaned.isEmpty ? exerciseName.trimmingCharacters(in: .whitespacesAndNewlines) : cleaned
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
    /// A new PR replaces the exercise's previous row(s) (one record per exercise).
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

        // Lock covers the read-compare-write sequence atomically
        prLock.lock()
        defer { prLock.unlock() }

        let name = Self.recordName(for: exerciseName)

        // Calculate estimated 1RM using Epley formula: weight × (1 + reps/30)
        let newE1RM = weightLbs * (1 + Double(reps) / 30)

        let existing = localStorage.fetchPersonalRecords(userId: userId)
            .filter { $0.exerciseName == name || $0.exerciseName == exerciseName }
        let existingE1RM = existing.map { $0.weightLbs * (1 + Double($0.reps) / 30) }.max() ?? 0

        guard newE1RM > existingE1RM else { return nil }

        let pr = PersonalRecord.create(
            userId: userId,
            exerciseName: name,
            weightLbs: weightLbs,
            reps: reps,
            workoutId: workoutId
        )
        let oldNames = Set(existing.compactMap(\.exerciseName))
        localStorage.deletePersonalRecords(userId: userId, exerciseNames: Array(oldNames))
        localStorage.savePersonalRecord(pr)

        // `submit` is synchronous and non-blocking (no network I/O under the lock).
        offlineQueueManager.submit(.insertPersonalRecord, payload: pr, recordKey: pr.id.uuidString)
        if !oldNames.isEmpty {
            queueCloudDelete(names: oldNames.union([name]), keeping: pr.id)
        }

        return pr
    }

    /// Queues the cloud delete of an exercise's older PR rows (everything created up to now,
    /// except `keeping`). A PR queued afterwards is newer than the cutoff and survives.
    private func queueCloudDelete(names: Set<String>, keeping keepId: UUID?) {
        let cutoff = Date()
        for name in names.sorted() {
            offlineQueueManager.submit(
                .deletePersonalRecords,
                payload: DeletePersonalRecordsPayload(exerciseName: name, keepId: keepId, cutoff: cutoff)
            )
        }
    }

    // MARK: - Full Repair

    /// Rebuilds every PR from the sets that remain in local storage. Covers both
    /// stale PRs (their sets were removed) and missing ones. Idempotent.
    /// `uploadChanges: false` rebuilds the local rows only (restore does this: the cloud PR
    /// log is not read back, so re-queueing would append a full PR set for every restore).
    func recalculateAllPRs(userId: UUID, uploadChanges: Bool = true) {
        let setNames = localStorage.fetchExerciseNamesWithSets(userId: userId)
        var groups: [String: Set<String>] = [:]   // record name -> raw exercise names behind it
        for raw in setNames { groups[Self.recordName(for: raw), default: []].insert(raw) }
        for pr in localStorage.fetchPersonalRecords(userId: userId) {
            if let name = pr.exerciseName { groups[Self.recordName(for: name), default: []].insert(name) }
        }
        for (_, rawNames) in groups {
            recalculatePR(userId: userId, exerciseNames: rawNames, uploadChanges: uploadChanges)
        }
    }

    // MARK: - Recalculation after deletion

    /// Rebuilds the local PR for an exercise from all remaining sets (the old local rows are
    /// replaced by exactly one). A changed result is queued as an insert plus a cloud delete of
    /// the older rows; an unchanged result queues nothing. Call this for each exercise in a
    /// workout that is being deleted.
    func recalculatePR(userId: UUID, exerciseName: String, uploadChanges: Bool = true) {
        recalculatePR(userId: userId, exerciseNames: [exerciseName], uploadChanges: uploadChanges)
    }

    /// `exerciseNames` are spellings (raw set names) that all map to the same record name.
    func recalculatePR(userId: UUID, exerciseNames: Set<String>, uploadChanges: Bool = true) {
        prLock.lock()
        defer { prLock.unlock() }

        guard let first = exerciseNames.sorted().first else { return }
        let name = Self.recordName(for: first)
        var spellings = exerciseNames
        spellings.insert(name)
        let allSpellings = Array(spellings)

        let existing = localStorage.fetchPersonalRecords(userId: userId)
            .filter { row in spellings.contains(row.exerciseName ?? "") }

        // Re-derive the best set from remaining data
        let sets = allSpellings.flatMap { localStorage.fetchAllSetsForExerciseName(userId: userId, exerciseName: $0) }

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
            // No lifts left: drop the stale PR rows locally and in the cloud.
            if !existing.isEmpty {
                let stored = Set(existing.compactMap(\.exerciseName))
                localStorage.deletePersonalRecords(userId: userId, exerciseNames: Array(stored))
                if uploadChanges { queueCloudDelete(names: stored, keeping: nil) }
            }
            return
        }

        var pr = PersonalRecord.create(
            userId: userId,
            exerciseName: name,
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
           current.exerciseName == name,
           current.weightLbs == pr.weightLbs, Int(current.reps) == pr.reps,
           current.workoutId == pr.workoutId,
           let achieved = current.dateAchieved, abs(achieved.timeIntervalSince(pr.dateAchieved)) < 1 {
            return
        }

        let stored = Set(existing.compactMap(\.exerciseName))
        localStorage.deletePersonalRecords(userId: userId, exerciseNames: Array(stored))
        localStorage.savePersonalRecord(pr)
        if uploadChanges {
            offlineQueueManager.submit(.insertPersonalRecord, payload: pr, recordKey: pr.id.uuidString)
            if !stored.isEmpty { queueCloudDelete(names: stored.union([name]), keeping: pr.id) }
        }
    }

    // MARK: - One-time cleanup

    struct CleanupSummary: Equatable {
        var orphansRemoved = 0
        var namesSwept = 0
    }

    /// Cleans existing PR data, locally and in the cloud (through the queue). Idempotent.
    ///  1. Rows whose exercise no longer exists in any logged set (left behind by merges and
    ///     renames) are deleted.
    ///  2. Every remaining exercise is rebuilt: exact duplicates and extra rows collapse into one,
    ///     and junk names ("**Chest** Bench Press") are stored sanitized.
    ///  3. The cloud table is swept per exercise: the kept row is (re)uploaded and every older
    ///     row of that name is deleted, which removes the cloud duplicates too.
    @discardableResult
    func cleanUpRecords(userId: UUID) -> CleanupSummary {
        var summary = CleanupSummary()
        let setNames = localStorage.fetchExerciseNamesWithSets(userId: userId)
        var groups: [String: Set<String>] = [:]
        for raw in setNames { groups[Self.recordName(for: raw), default: []].insert(raw) }

        // 1. Orphans
        var orphanNames = Set<String>()
        for row in localStorage.fetchPersonalRecords(userId: userId) {
            guard let stored = row.exerciseName else { continue }
            if groups[Self.recordName(for: stored)] == nil { orphanNames.insert(stored) }
        }
        if !orphanNames.isEmpty {
            prLock.lock()
            summary.orphansRemoved = localStorage.fetchPersonalRecords(userId: userId)
                .filter { orphanNames.contains($0.exerciseName ?? "") }.count
            localStorage.deletePersonalRecords(userId: userId, exerciseNames: Array(orphanNames))
            queueCloudDelete(names: orphanNames, keeping: nil)
            prLock.unlock()
        }

        // 2. Rebuild each exercise from its sets
        for (_, rawNames) in groups {
            recalculatePR(userId: userId, exerciseNames: rawNames)
        }

        // 3. Cloud sweep
        let cutoff = Date()
        prLock.lock()
        defer { prLock.unlock() }
        for row in localStorage.fetchPersonalRecords(userId: userId) {
            guard let name = row.exerciseName else { continue }
            let pr = PersonalRecord(from: row)
            offlineQueueManager.submit(.insertPersonalRecord, payload: pr, recordKey: pr.id.uuidString)
            offlineQueueManager.submit(
                .deletePersonalRecords,
                payload: DeletePersonalRecordsPayload(exerciseName: name, keepId: pr.id, cutoff: cutoff)
            )
            summary.namesSwept += 1
        }
        return summary
    }
}
