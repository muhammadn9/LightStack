import Foundation
import os

extension Notification.Name {
    /// Posted on the main thread after a restore changed local data, so open screens can reload.
    static let syncRestoreDidChangeLocalData = Notification.Name("syncRestoreDidChangeLocalData")
}

enum RestoreError: Error, Equatable {
    case userChanged
    case alreadyRunning
    case timedOut
    case notSignedIn
}

/// What a restore did (for logs, tests and the sync docs).
struct RestoreSummary: Equatable {
    var profileApplied = false
    var workoutsApplied = 0
    var workoutsSkippedPending = 0
    var workoutsSkippedActive = 0
    /// Remote workouts with no worked exercise: not restored, and not deleted remotely.
    var workoutsSkippedEmpty = 0
    var restDaysApplied = 0
    var contextSummariesApplied = 0
    var planApplied = false
    /// Local rows removed because a tombstone says they were deleted elsewhere.
    var localRecordsDeleted = 0
    var repairedWorkouts = 0
    var repairedRestDays = 0
    var nutritionApplied = 0
    var repairedNutrition = 0
    /// First-reconciliation mode (local data is authoritative) was used.
    var reconciled = false
    /// Local workouts whose differing parts were queued for upload in that mode.
    var reconciledWorkouts = 0
    /// Cloud-only exercises and sets of a local workout that were queued for deletion (with tombstones).
    var remoteChildrenDeleted = 0
}

enum RemoteProfileOutcome {
    /// Saved locally (nothing queued).
    case applied(UserProfile)
    /// A cloud profile exists but this device has an unuploaded profile change, which wins.
    case keptLocal
    /// No profile in the cloud.
    case none
}

/// Downloads the user's cloud data into the local store: the missing half of sync.
///
/// Rules (see docs/SYNC_DESIGN.md "Restore"):
///  - Applying cloud data NEVER queues an upload; only the repair step (below) does.
///  - Tombstoned records are deleted locally and never restored.
///  - A record with an unuploaded local change is skipped: local pending changes win.
///  - Otherwise the cloud wins, by id.
///  - The workout being logged right now is never touched.
///  - Workouts with nothing worked in them are not restored (and not deleted in the cloud).
///  - Personal records are recomputed from the sets, locally only.
///  - After a COMPLETE fetch, local workouts and rest days the cloud lacks are queued for upload.
@MainActor
final class SyncRestoreService {

    static let restoreInterval: TimeInterval = 6 * 60 * 60
    nonisolated static let profileTimeout: TimeInterval = 15

    private static let logger = Logger(subsystem: "org.lightstack.app", category: "SyncRestore")

    private let remote: RemoteReading
    private let storage: LocalStorageService
    private let queue: OfflineQueueManager
    private let prRepository: PRRepository
    private let currentUserId: () -> UUID?
    private let activeWorkoutIds: () -> Set<UUID>
    private let defaults: UserDefaults
    private let now: () -> Date
    private let pageSize: Int
    private(set) var isRunning = false

    init(
        remote: RemoteReading,
        storage: LocalStorageService,
        queue: OfflineQueueManager,
        prRepository: PRRepository,
        currentUserId: @escaping () -> UUID?,
        activeWorkoutIds: @escaping () -> Set<UUID> = { [] },
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() },
        pageSize: Int = 100
    ) {
        self.remote = remote
        self.storage = storage
        self.queue = queue
        self.prRepository = prRepository
        self.currentUserId = currentUserId
        self.activeWorkoutIds = activeWorkoutIds
        self.defaults = defaults
        self.now = now
        self.pageSize = max(1, pageSize)
    }

    // MARK: - Schedule

    private func lastRestoreKey(_ userId: UUID) -> String { "lightstack.lastSuccessfulRestore.\(userId.uuidString)" }

    func lastSuccessfulRestore(userId: UUID) -> Date? {
        defaults.object(forKey: lastRestoreKey(userId)) as? Date
    }

    /// True when no restore succeeded for this user in the last 6 hours.
    func isRestoreDue(userId: UUID) -> Bool {
        guard let last = lastSuccessfulRestore(userId: userId) else { return true }
        return now().timeIntervalSince(last) >= Self.restoreInterval
    }

    private func reconciledKey(_ userId: UUID) -> String { "lightstack.firstReconciliationDone.\(userId.uuidString)" }

    /// Whether the one-time local-authoritative reconciliation has completed for this user on this device.
    func isFirstReconciliationDone(userId: UUID) -> Bool { defaults.bool(forKey: reconciledKey(userId)) }

    private func localHasData(userId: UUID) -> Bool {
        storage.fetchProfile(userId: userId) != nil
            || !storage.fetchRecentWorkouts(userId: userId, limit: 1).isEmpty
            || !storage.fetchRestDays(userId: userId).isEmpty
            || !storage.fetchAllFoodEntries(userId: userId).isEmpty
            || !storage.fetchNutritionTargets(userId: userId).isEmpty
            || !storage.fetchFoods(userId: userId).isEmpty
    }

    func forgetLastRestore(userId: UUID) {
        defaults.removeObject(forKey: lastRestoreKey(userId))
    }

    // MARK: - Profile (first step, also used by onboarding)

    /// Fetches the cloud profile and saves it locally (no upload). Throws if the cloud can't
    /// be reached within `timeout` seconds.
    func restoreProfile(userId: UUID, timeout: TimeInterval = SyncRestoreService.profileTimeout) async throws -> RemoteProfileOutcome {
        try ensureUser(userId)
        let reader = remote
        let fetched = try await Self.withDeadline(timeout) { try await reader.fetchProfile(userId: userId) }
        try ensureUser(userId)
        guard let profile = fetched, profile.userId == userId else { return .none }
        let pending = try await pendingChanges(userId)
        if pending.profile { return .keptLocal }
        storage.saveProfile(profile)
        return .applied(profile)
    }

    // MARK: - Onboarding decision

    enum AccountLookup: Equatable {
        /// The account has a profile (now saved locally): skip onboarding.
        case existing
        /// Reachable, and the account has no profile: onboard.
        case new
        /// Could not ask (offline / timeout): the caller must not guess.
        case unreachable
        /// The user signed out or changed meanwhile.
        case cancelled
    }

    /// Looks for the account's cloud profile (saving it locally when found).
    func lookUpAccountProfile(userId: UUID) async -> AccountLookup {
        do {
            switch try await restoreProfile(userId: userId) {
            case .applied, .keptLocal: return .existing
            case .none: return .new
            }
        } catch RestoreError.userChanged {
            return .cancelled
        } catch RestoreError.notSignedIn {
            return .cancelled
        } catch is CancellationError {
            return .cancelled
        } catch {
            Self.logger.info("account lookup failed: \(String(describing: error), privacy: .public)")
            return .unreachable
        }
    }

    enum NewProfileResult: Equatable { case saved, adoptedExisting, couldNotVerify }

    /// Onboarding's last step: `save` runs only when the cloud has no profile for the account,
    /// so a new device can never overwrite an existing cloud profile. If the cloud can't be
    /// asked, nothing is saved.
    func saveNewProfileUnlessAccountHasOne(
        _ profile: UserProfile, save: (UserProfile) -> Void
    ) async -> NewProfileResult {
        switch await lookUpAccountProfile(userId: profile.userId) {
        case .existing:
            return .adoptedExisting
        case .new:
            save(profile)
            return .saved
        case .unreachable, .cancelled:
            return .couldNotVerify
        }
    }

    // MARK: - Full restore

    @discardableResult
    /// - Parameter assumeFreshInstall: the caller just saved the cloud profile on an empty device, so
    ///   the local store must not be mistaken for an existing install's data.
    func restoreAll(userId: UUID, assumeFreshInstall: Bool = false) async throws -> RestoreSummary {
        guard !isRunning else { throw RestoreError.alreadyRunning }
        isRunning = true
        defer { isRunning = false }
        try ensureUser(userId)

        let started = now()
        var summary = RestoreSummary()
        // First reconciliation: an existing install may hold edits the old queue lost, so until one
        // complete run has finished, local data is authoritative (see docs/SYNC_DESIGN.md).
        let reconcile = !assumeFreshInstall && !isFirstReconciliationDone(userId: userId) && localHasData(userId: userId)
        summary.reconciled = reconcile

        // 1. Deletions first, so nothing below can bring a deleted record back.
        let tombstones = TombstoneSet(try await remote.fetchTombstones(userId: userId))
        try ensureUser(userId)
        await discardPendingUpserts(tombstones, userId: userId)
        try ensureUser(userId)
        summary.localRecordsDeleted = applyTombstones(tombstones, userId: userId)

        // 2. Profile.
        if reconcile, let localProfile = storage.fetchProfile(userId: userId) {
            let pending = try await pendingChanges(userId)
            if !pending.profile {
                queue.submit(.upsertProfile, payload: UserProfile(from: localProfile), recordKey: userId.uuidString)
            }
        } else if case .applied = try await restoreProfile(userId: userId) {
            summary.profileApplied = true
        }

        // 3. History, page by page.
        var remoteWorkoutIds = Set<UUID>()
        var remoteWithoutWork = Set<UUID>()
        var reconciledIds = Set<UUID>()
        var offset = 0
        while true {
            try Task.checkCancellation()
            let page = try await remote.fetchWorkoutHistoryPage(userId: userId, offset: offset, limit: pageSize)
            try ensureUser(userId)
            let pending = try await pendingChanges(userId)
            applyHistoryPage(page, userId: userId, tombstones: tombstones, pending: pending, reconcile: reconcile,
                             remoteIds: &remoteWorkoutIds, remoteWithoutWork: &remoteWithoutWork,
                             reconciledIds: &reconciledIds, summary: &summary)
            offset += page.count
            if page.count < pageSize { break }
            await Task.yield()
        }
        // From here on the cloud history is known completely (every page arrived).

        // 4. Rest days.
        let remoteRestDays = try await remote.fetchRestDays(userId: userId)
        try ensureUser(userId)
        let restPending = try await pendingChanges(userId)
        summary.restDaysApplied = applyRestDays(remoteRestDays, userId: userId, tombstones: tombstones, pending: restPending, reconcile: reconcile)

        // 4b. Nutrition: targets, foods, then diary entries page by page.
        let remoteNutrition = try await restoreNutrition(userId: userId, tombstones: tombstones, reconcile: reconcile, summary: &summary)

        // 5. Context summaries.
        let summaries = try await remote.fetchContextSummaries(userId: userId)
        try ensureUser(userId)
        let summaryPending = try await pendingChanges(userId)
        summary.contextSummariesApplied = applyContextSummaries(summaries, userId: userId, pending: summaryPending, reconcile: reconcile)

        // 6. Active month plan and its sessions.
        if let plan = try await remote.fetchActiveMonthPlan(userId: userId) {
            let sessions = try await remote.fetchPlannedSessions(monthPlanId: plan.id)
            try ensureUser(userId)
            let planPending = try await pendingChanges(userId)
            summary.planApplied = applyPlan(plan, sessions: sessions, userId: userId, tombstones: tombstones, pending: planPending, reconcile: reconcile)
        }

        // 7. PRs from the sets that are now local. Local rows only: nothing is queued.
        prRepository.recalculateAllPRs(userId: userId, uploadChanges: false)

        // 8. Repair: send up what the cloud is missing (only after every fetch above succeeded).
        try ensureUser(userId)
        try await repairUploads(
            userId: userId, tombstones: tombstones, remoteWorkoutIds: remoteWorkoutIds,
            remoteWithoutWork: remoteWithoutWork,
            alreadyReconciled: reconciledIds,
            remoteRestDays: Set(remoteRestDays.map { RestDay.dayString($0.date) }),
            remoteNutrition: remoteNutrition,
            summary: &summary
        )

        defaults.set(started, forKey: lastRestoreKey(userId))
        defaults.set(true, forKey: reconciledKey(userId))   // only reached after a complete run
        Self.logger.info("""
            restore done: workouts=\(summary.workoutsApplied) pendingSkipped=\(summary.workoutsSkippedPending) \
            activeSkipped=\(summary.workoutsSkippedActive) emptySkipped=\(summary.workoutsSkippedEmpty) \
            deleted=\(summary.localRecordsDeleted) repairedWorkouts=\(summary.repairedWorkouts) \
            repairedRestDays=\(summary.repairedRestDays) reconciled=\(summary.reconciled) \
            reconciledWorkouts=\(summary.reconciledWorkouts) remoteChildrenDeleted=\(summary.remoteChildrenDeleted)
            """)
        if summary != RestoreSummary() {
            NotificationCenter.default.post(name: .syncRestoreDidChangeLocalData, object: nil)
        }
        return summary
    }

    // MARK: - Guards

    private func ensureUser(_ userId: UUID) throws {
        guard let current = currentUserId() else { throw RestoreError.notSignedIn }
        guard current == userId else { throw RestoreError.userChanged }
    }

    /// Everything the user changed locally and has not uploaded yet (writes made a moment ago included).
    private func pendingChanges(_ userId: UUID) async throws -> PendingChangeIndex {
        await queue.waitForSubmissions()
        let index = await queue.pendingChangeIndex(for: userId)
        try ensureUser(userId)
        return index
    }

    nonisolated static func withDeadline<T: Sendable>(
        _ seconds: TimeInterval, _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                throw RestoreError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw RestoreError.timedOut }
            return first
        }
    }

    // MARK: - Tombstones

    struct TombstoneSet {
        private var byEntity: [String: Set<UUID>] = [:]
        init(_ tombstones: [RemoteTombstone]) {
            for t in tombstones { byEntity[t.entity, default: []].insert(t.recordId) }
        }
        func ids(_ entity: TombstoneEntity) -> Set<UUID> { byEntity[entity.rawValue] ?? [] }
        func contains(_ entity: TombstoneEntity, _ id: UUID) -> Bool { byEntity[entity.rawValue]?.contains(id) ?? false }
        var all: [TombstoneEntity: Set<UUID>] {
            var result: [TombstoneEntity: Set<UUID>] = [:]
            for (key, ids) in byEntity { if let entity = TombstoneEntity(rawValue: key) { result[entity] = ids } }
            return result
        }
    }

    /// A tombstone beats a pending upsert for the same record: drop those queued upserts (deletes and
    /// tombstones stay) so they can't recreate a stray cloud row. The active workout is left alone.
    private func discardPendingUpserts(_ tombstones: TombstoneSet, userId: UUID) async {
        await queue.waitForSubmissions()
        var deleted = OfflineQueueManager.DeletedRecords()
        deleted.workouts = tombstones.ids(.workout).subtracting(activeWorkoutIds())
        deleted.exercises = tombstones.ids(.exercise)
        deleted.sets = tombstones.ids(.set)
        deleted.monthPlans = tombstones.ids(.monthPlan)
        deleted.plannedSessions = tombstones.ids(.plannedSession)
        deleted.restDays = tombstones.ids(.restDay)
        deleted.nutritionTargets = tombstones.ids(.nutritionTarget)
        deleted.foods = tombstones.ids(.food)
        deleted.foodEntries = tombstones.ids(.foodEntry)
        await queue.discardPendingUpserts(for: userId, deleted: deleted)
    }

    /// Deletes local rows that a tombstone says are gone. Returns how many rows were removed.
    private func applyTombstones(_ tombstones: TombstoneSet, userId: UUID) -> Int {
        let active = activeWorkoutIds()
        var removed = 0
        removed += storage.deleteWorkouts(ids: tombstones.ids(.workout).subtracting(active))
        removed += storage.deleteExercises(ids: tombstones.ids(.exercise))
        removed += storage.deleteSets(ids: tombstones.ids(.set))
        removed += storage.deleteMonthPlans(ids: tombstones.ids(.monthPlan))
        removed += storage.deletePlannedSessions(ids: tombstones.ids(.plannedSession))
        removed += storage.deleteRestDays(ids: tombstones.ids(.restDay), userId: userId).count
        removed += storage.deleteNutritionTargets(ids: tombstones.ids(.nutritionTarget))
        removed += storage.deleteFoodEntries(ids: tombstones.ids(.foodEntry))
        let deletedFoods = tombstones.ids(.food)
        if !deletedFoods.isEmpty {
            // The cloud nulls the reference when a food goes; mirror that locally (no upload).
            _ = storage.detachFoodEntries(foodIds: deletedFoods, userId: userId)
            removed += storage.deleteFoods(ids: deletedFoods)
        }
        return removed
    }

    // MARK: - History

    private func applyHistoryPage(
        _ page: [RemoteWorkoutRecord],
        userId: UUID,
        tombstones: TombstoneSet,
        pending: PendingChangeIndex,
        reconcile: Bool,
        remoteIds: inout Set<UUID>,
        remoteWithoutWork: inout Set<UUID>,
        reconciledIds: inout Set<UUID>,
        summary: inout RestoreSummary
    ) {
        let active = activeWorkoutIds()
        var batch: [LocalStorageService.RestoredWorkout] = []
        let localEntities = reconcile ? storage.workoutEntities(ids: page.map(\.workout.id)) : [:]

        for record in page {
            let workout = record.workout
            guard workout.userId == userId else { continue }
            remoteIds.insert(workout.id)
            if tombstones.contains(.workout, workout.id) { continue }

            // Local-authoritative: a workout that exists here is never overwritten or extended.
            if let local = localEntities[workout.id] {
                reconciledIds.insert(workout.id)
                if active.contains(workout.id) {
                    summary.workoutsSkippedActive += 1
                } else {
                    reconcileWorkout(record, local: local, tombstones: tombstones, pending: pending, summary: &summary)
                }
                continue
            }

            // Worked exercises only: an exercise with no sets was never done.
            var exercises: [(exercise: Exercise, sets: [WorkoutSet])] = []
            for entry in record.exercises where !tombstones.contains(.exercise, entry.exercise.id) {
                let sets = entry.sets.filter { !tombstones.contains(.set, $0.id) }
                if !sets.isEmpty { exercises.append((entry.exercise, sets)) }
            }
            if exercises.isEmpty {
                remoteWithoutWork.insert(workout.id)
                summary.workoutsSkippedEmpty += 1
                continue
            }
            if active.contains(workout.id) {
                summary.workoutsSkippedActive += 1
                continue
            }

            var exerciseIds = Set(record.exercises.map(\.exercise.id))
            let setIds = Set(record.exercises.flatMap { $0.sets.map(\.id) })
            if !pending.setExerciseIds.isEmpty {
                exerciseIds.formUnion(storage.fetchExercises(workoutId: workout.id).compactMap(\.id))
            }
            if pending.isWorkoutDirty(workoutId: workout.id, exerciseIds: exerciseIds, setIds: setIds) {
                summary.workoutsSkippedPending += 1
                continue
            }
            batch.append((workout, exercises))
        }

        storage.restoreWorkouts(batch)
        summary.workoutsApplied += batch.count
    }

    // MARK: - Rest days, summaries, plan

    private func applyRestDays(
        _ days: [RestDay], userId: UUID, tombstones: TombstoneSet, pending: PendingChangeIndex, reconcile: Bool
    ) -> Int {
        var toApply: [RestDay] = []
        for day in days where day.userId == userId {
            if tombstones.contains(.restDay, day.id) { continue }
            let key = RestDay.dayString(day.date)
            if pending.restDayIds.contains(day.id) || pending.restDayDays.contains(key) { continue }
            if reconcile {
                let start = day.date.startOfDay
                if let local = storage.fetchRestDays(userId: userId, in: start...start).first {
                    // Same day on both sides: keep local; if the cloud row differs, upload the local one.
                    let localDay = RestDay(from: local)
                    if localDay.id != day.id {
                        queue.submit(.upsertRestDay, payload: localDay, recordKey: localDay.id.uuidString)
                    }
                    continue
                }
            }
            toApply.append(day)
        }
        storage.restoreRestDays(toApply)
        return toApply.count
    }

    // MARK: - Nutrition

    /// Ids the cloud holds, known only after every nutrition fetch succeeded.
    struct RemoteNutritionIds {
        var targets = Set<UUID>()
        var foods = Set<UUID>()
        var entries = Set<UUID>()
    }

    /// Applies one kind of nutrition record. Tombstoned and pending-change records are skipped (local wins).
    /// In first-reconciliation mode a record that exists locally is kept and, if it differs, queued for upload.
    private func applyNutritionRecords<R: Equatable>(
        _ records: [R], id: (R) -> UUID, owner: (R) -> UUID, userId: UUID,
        isTombstoned: (UUID) -> Bool, isPending: (UUID) -> Bool, reconcile: Bool,
        local: (UUID) -> R?, queueUpload: (R) -> Void, save: ([R]) -> Void
    ) -> Int {
        var toApply: [R] = []
        for record in records where owner(record) == userId {
            let recordId = id(record)
            if isTombstoned(recordId) || isPending(recordId) { continue }
            if reconcile, let existing = local(recordId) {
                if existing != record { queueUpload(existing) }
                continue
            }
            toApply.append(record)
        }
        save(toApply)
        return toApply.count
    }

    private func restoreNutrition(
        userId: UUID, tombstones: TombstoneSet, reconcile: Bool, summary: inout RestoreSummary
    ) async throws -> RemoteNutritionIds {
        var ids = RemoteNutritionIds()

        let targets = try await remote.fetchNutritionTargets(userId: userId)
        try ensureUser(userId)
        var pending = try await pendingChanges(userId)
        ids.targets = Set(targets.map(\.id))
        summary.nutritionApplied += applyNutritionRecords(
            targets, id: { $0.id }, owner: { $0.userId }, userId: userId,
            isTombstoned: { tombstones.contains(.nutritionTarget, $0) }, isPending: { pending.nutritionTargets.contains($0) },
            reconcile: reconcile, local: { self.storage.fetchNutritionTarget(id: $0) },
            queueUpload: { self.queue.submit(.upsertNutritionTarget, payload: $0, recordKey: $0.id.uuidString) },
            save: { self.storage.restoreNutritionTargets($0) }
        )

        let foods = try await remote.fetchFoods(userId: userId)
        try ensureUser(userId)
        pending = try await pendingChanges(userId)
        ids.foods = Set(foods.map(\.id))
        summary.nutritionApplied += applyNutritionRecords(
            foods, id: { $0.id }, owner: { $0.userId }, userId: userId,
            isTombstoned: { tombstones.contains(.food, $0) }, isPending: { pending.foods.contains($0) },
            reconcile: reconcile, local: { self.storage.fetchFood(id: $0) },
            queueUpload: { self.queue.submit(.upsertFood, payload: $0, recordKey: $0.id.uuidString) },
            save: { self.storage.restoreFoods($0) }
        )

        var offset = 0
        while true {
            try Task.checkCancellation()
            let page = try await remote.fetchFoodEntriesPage(userId: userId, offset: offset, limit: pageSize)
            try ensureUser(userId)
            pending = try await pendingChanges(userId)
            page.forEach { ids.entries.insert($0.id) }
            // An entry whose food was deleted elsewhere keeps its snapshot but loses the link.
            let cleaned: [FoodEntry] = page.map { entry in
                var entry = entry
                if let foodId = entry.foodId, tombstones.contains(.food, foodId) { entry.foodId = nil }
                return entry
            }
            summary.nutritionApplied += applyNutritionRecords(
                cleaned, id: { $0.id }, owner: { $0.userId }, userId: userId,
                isTombstoned: { tombstones.contains(.foodEntry, $0) }, isPending: { pending.foodEntries.contains($0) },
                reconcile: reconcile, local: { self.storage.fetchFoodEntry(id: $0) },
                queueUpload: { self.queue.submit(.upsertFoodEntry, payload: $0, recordKey: $0.id.uuidString) },
                save: { self.storage.restoreFoodEntries($0) }
            )
            offset += page.count
            if page.count < pageSize { break }
            await Task.yield()
        }
        return ids
    }

    private func applyContextSummaries(
        _ summaries: [AIContextSummary], userId: UUID, pending: PendingChangeIndex, reconcile: Bool
    ) -> Int {
        var applied = 0
        storage.performBatch {
            for summary in summaries where summary.userId == userId && !pending.contextTypes.contains(summary.workoutType)
                && !pending.deletedContextTypes.contains(summary.workoutType) {
                if reconcile, let local = storage.fetchContextSummary(userId: userId, workoutType: summary.workoutType) {
                    let localSummary = AIContextSummary(from: local)
                    if localSummary.summaryText != summary.summaryText || localSummary.sessionsCovered != summary.sessionsCovered {
                        queue.submit(.upsertContextSummary, payload: localSummary,
                                     recordKey: "\(userId.uuidString)|\(summary.workoutType)")
                    }
                    continue
                }
                storage.saveContextSummary(summary)
                applied += 1
            }
        }
        return applied
    }

    private func applyPlan(
        _ plan: MonthPlan, sessions: [PlannedSession], userId: UUID,
        tombstones: TombstoneSet, pending: PendingChangeIndex, reconcile: Bool
    ) -> Bool {
        if reconcile && storage.fetchMonthPlan(id: plan.id) != nil { return false }   // local plan is kept
        guard plan.userId == userId,
              !tombstones.contains(.monthPlan, plan.id),
              !pending.monthPlans.contains(plan.id) else { return false }
        storage.performBatch {
            storage.saveMonthPlan(plan)
            let wanted = sessions.filter {
                $0.userId == userId && !tombstones.contains(.plannedSession, $0.id) && !pending.plannedSessions.contains($0.id)
            }
            storage.savePlannedSessions(wanted, monthPlanId: plan.id)
        }
        return true
    }

    // MARK: - First reconciliation (local-authoritative)

    private static func sameHeader(_ a: Workout, _ b: Workout) -> Bool {
        a.workoutType == b.workoutType && a.durationMinutes == b.durationMinutes && a.energyLevel == b.energyLevel
            && a.timeAvailableMinutes == b.timeAvailableMinutes && a.userNote == b.userNote
            && a.setupNote == b.setupNote && a.aiProgressionNote == b.aiProgressionNote
            && a.plannedSessionId == b.plannedSessionId && RemoteDate.dayString(a.date) == RemoteDate.dayString(b.date)
    }

    private static func sameExercise(_ a: Exercise, _ b: Exercise) -> Bool {
        a.workoutId == b.workoutId && a.name == b.name && a.muscleGroup == b.muscleGroup && a.orderIndex == b.orderIndex
            && a.targetSets == b.targetSets && a.targetReps == b.targetReps && a.targetRir == b.targetRir
            && a.restSeconds == b.restSeconds && a.coachNote == b.coachNote && a.supersetGroupId == b.supersetGroupId && a.isPerArm == b.isPerArm
    }

    private static func sameSet(_ a: WorkoutSet, _ b: WorkoutSet) -> Bool {
        a.exerciseId == b.exerciseId && a.setNumber == b.setNumber && a.weightLbs == b.weightLbs && a.reps == b.reps
            && a.rir == b.rir && a.userFeedback == b.userFeedback && a.isPR == b.isPR
            && a.durationSeconds == b.durationSeconds && a.distanceMiles == b.distanceMiles
            && a.inclineLevel == b.inclineLevel
    }

    /// A workout that exists on both sides: nothing local is changed. Whatever differs is queued as
    /// the local version (upserts). Cloud-only children are deleted (with tombstones) only when the
    /// local copy has worked exercises, so an empty or damaged local copy can never wipe the cloud.
    private func reconcileWorkout(
        _ record: RemoteWorkoutRecord, local: CDWorkout, tombstones: TombstoneSet,
        pending: PendingChangeIndex, summary: inout RestoreSummary
    ) {
        guard let workoutId = local.id else { return }
        let localWorkout = Workout(from: local)

        var localExercises: [Exercise] = []
        var localSetsByExercise: [UUID: [WorkoutSet]] = [:]
        for entity in storage.fetchExercises(workoutId: workoutId) {
            let exercise = Exercise(from: entity)
            localExercises.append(exercise)
            localSetsByExercise[exercise.id] = storage.fetchSets(exerciseId: exercise.id).map { WorkoutSet(from: $0) }
        }

        let remoteExercises = record.exercises.filter { !tombstones.contains(.exercise, $0.exercise.id) }
        var remoteSets: [UUID: WorkoutSet] = [:]
        for entry in remoteExercises {
            for set in entry.sets where !tombstones.contains(.set, set.id) { remoteSets[set.id] = set }
        }

        let allExerciseIds = Set(localExercises.map(\.id)).union(remoteExercises.map(\.exercise.id))
        let allSetIds = Set(localSetsByExercise.values.flatMap { $0.map(\.id) }).union(remoteSets.keys)
        if pending.isWorkoutDirty(workoutId: workoutId, exerciseIds: allExerciseIds, setIds: allSetIds) {
            summary.workoutsSkippedPending += 1
            return
        }

        var changed = false
        if !Self.sameHeader(localWorkout, record.workout) {
            queue.submit(.insertWorkout, payload: localWorkout, recordKey: workoutId.uuidString)
            changed = true
        }

        let workedLocal = localExercises.filter { !(localSetsByExercise[$0.id] ?? []).isEmpty }
        if !workedLocal.isEmpty {
            let remoteExerciseById = Dictionary(remoteExercises.map { ($0.exercise.id, $0.exercise) }, uniquingKeysWith: { a, _ in a })
            let exercisesToUpload = workedLocal.filter {
                guard let theirs = remoteExerciseById[$0.id] else { return true }
                return !Self.sameExercise($0, theirs)
            }
            let setsToUpload = workedLocal.flatMap { localSetsByExercise[$0.id] ?? [] }.filter {
                guard let theirs = remoteSets[$0.id] else { return true }
                return !Self.sameSet($0, theirs)
            }
            if !exercisesToUpload.isEmpty { queue.submit(.insertExercises, payload: exercisesToUpload) }
            for set in setsToUpload { queue.submit(.insertSet, payload: set, recordKey: set.id.uuidString) }
            changed = changed || !exercisesToUpload.isEmpty || !setsToUpload.isEmpty

            // Cloud-only children are gone locally (deleted before tombstones existed).
            let localExerciseIds = Set(localExercises.map(\.id))
            let localSetIds = Set(localSetsByExercise.values.flatMap { $0.map(\.id) })
            var deletedExercises: [UUID] = []
            var deletedSets: [UUID] = []
            for entry in remoteExercises {
                if !localExerciseIds.contains(entry.exercise.id) {
                    queue.submit(.deleteExercise, payload: DeleteExercisePayload(exerciseId: entry.exercise.id))
                    deletedExercises.append(entry.exercise.id)
                    deletedSets.append(contentsOf: entry.sets.map(\.id).filter { !tombstones.contains(.set, $0) })
                } else {
                    for set in entry.sets where !localSetIds.contains(set.id) && !tombstones.contains(.set, set.id) {
                        queue.submit(.deleteSet, payload: set)
                        deletedSets.append(set.id)
                    }
                }
            }
            queue.submitTombstones(.exercise, ids: deletedExercises)
            queue.submitTombstones(.set, ids: deletedSets)
            if !deletedExercises.isEmpty || !deletedSets.isEmpty {
                summary.remoteChildrenDeleted += deletedExercises.count + deletedSets.count
                changed = true
            }
        }
        if changed { summary.reconciledWorkouts += 1 }
    }

    // MARK: - Repair upload

    /// Queues local workouts (with exercises and sets) and rest days the cloud does not have,
    /// so rows an old queue lost reach the cloud. Skips anything tombstoned, anything with an
    /// unuploaded change of its own, the active workout, empty workouts and setless exercises.
    /// A cloud workout that has nothing worked in it gets the local exercises and sets only.
    private func repairUploads(
        userId: UUID,
        tombstones: TombstoneSet,
        remoteWorkoutIds: Set<UUID>,
        remoteWithoutWork: Set<UUID>,
        alreadyReconciled: Set<UUID>,
        remoteRestDays: Set<String>,
        remoteNutrition: RemoteNutritionIds,
        summary: inout RestoreSummary
    ) async throws {
        // Child operations whose parent never reached the cloud get their parent queued (or are dropped
        // as orphans) before anything is judged "pending".
        await queue.resolveDependencies(tombstoned: tombstones.all)
        let pending = try await pendingChanges(userId)
        let active = activeWorkoutIds()

        for local in storage.fetchAllWorkouts(userId: userId) {
            guard let workoutId = local.id, !active.contains(workoutId),
                  !alreadyReconciled.contains(workoutId),
                  !tombstones.contains(.workout, workoutId) else { continue }
            let onRemote = remoteWorkoutIds.contains(workoutId)
            if onRemote && !remoteWithoutWork.contains(workoutId) { continue }

            var exercises: [Exercise] = []
            var sets: [WorkoutSet] = []
            for entity in storage.fetchExercises(workoutId: workoutId) {
                let exercise = Exercise(from: entity)
                guard !tombstones.contains(.exercise, exercise.id) else { continue }
                let exerciseSets = storage.fetchSets(exerciseId: exercise.id)
                    .map { WorkoutSet(from: $0) }
                    .filter { !tombstones.contains(.set, $0.id) }
                guard !exerciseSets.isEmpty else { continue }
                exercises.append(exercise)
                sets.append(contentsOf: exerciseSets)
            }
            guard !exercises.isEmpty else { continue }
            if pending.isWorkoutDirty(workoutId: workoutId, exerciseIds: Set(exercises.map(\.id)), setIds: Set(sets.map(\.id))) {
                // Only its children are pending (their parent row never uploaded): queue the workout row itself.
                if !onRemote && !pending.headerWorkouts.contains(workoutId) {
                    let workout = Workout(from: local)
                    queue.submit(.insertWorkout, payload: workout, recordKey: workout.id.uuidString)
                    summary.repairedWorkouts += 1
                }
                continue
            }

            // Parent first; the queue also orders by type.
            if !onRemote {
                let workout = Workout(from: local)
                queue.submit(.insertWorkout, payload: workout, recordKey: workout.id.uuidString)
                summary.repairedWorkouts += 1
            }
            queue.submit(.insertExercises, payload: exercises)
            for set in sets {
                queue.submit(.insertSet, payload: set, recordKey: set.id.uuidString)
            }
        }

        for entity in storage.fetchRestDays(userId: userId) {
            let day = RestDay(from: entity)
            let key = RestDay.dayString(day.date)
            guard !remoteRestDays.contains(key),
                  !tombstones.contains(.restDay, day.id),
                  !pending.restDayIds.contains(day.id),
                  !pending.restDayDays.contains(key) else { continue }
            queue.submit(.upsertRestDay, payload: day, recordKey: day.id.uuidString)
            summary.repairedRestDays += 1
        }

        // Nutrition: parents (targets, foods) are ordered before entries by the queue.
        for target in storage.fetchNutritionTargets(userId: userId)
        where !remoteNutrition.targets.contains(target.id) && !tombstones.contains(.nutritionTarget, target.id)
            && !pending.nutritionTargets.contains(target.id) {
            queue.submit(.upsertNutritionTarget, payload: target, recordKey: target.id.uuidString)
            summary.repairedNutrition += 1
        }
        for food in storage.fetchFoods(userId: userId)
        where !remoteNutrition.foods.contains(food.id) && !tombstones.contains(.food, food.id)
            && !pending.foods.contains(food.id) {
            queue.submit(.upsertFood, payload: food, recordKey: food.id.uuidString)
            summary.repairedNutrition += 1
        }
        for entry in storage.fetchAllFoodEntries(userId: userId)
        where !remoteNutrition.entries.contains(entry.id) && !tombstones.contains(.foodEntry, entry.id)
            && !pending.foodEntries.contains(entry.id) {
            queue.submit(.upsertFoodEntry, payload: entry, recordKey: entry.id.uuidString)
            summary.repairedNutrition += 1
        }
    }
}
