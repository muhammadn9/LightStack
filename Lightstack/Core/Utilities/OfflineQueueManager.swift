import Foundation
import os

// MARK: - Queue Operation Type

/// All write operations that can be deferred when offline.
enum QueuedOperationType: String, Codable {
    case insertWorkout
    case updateWorkout
    case deleteWorkout
    case deleteSet
    case deleteExercise
    case deleteExercises
    case insertExercises
    case insertSet
    case renameExercises
    case upsertProfile
    case insertPersonalRecord
    case deletePersonalRecords
    case upsertContextSummary
    case deleteContextSummaries
    case insertMonthPlan
    case insertPlannedSessions
    case updatePlannedSession
    case deleteMonthPlan
    case upsertRestDay
    case deleteRestDay
    case insertTombstone
}

/// Entity names stored in `sync_tombstones.entity`.
enum TombstoneEntity: String, Codable {
    case workout
    case exercise
    case set
    case personalRecord = "personal_record"
    case monthPlan = "month_plan"
    case plannedSession = "planned_session"
    case restDay = "rest_day"
}

/// Payload for `.insertTombstone`: these records were deleted on this device.
struct TombstonePayload: Codable {
    /// Signed-in user at enqueue time. nil only if nobody was signed in; the
    /// operation's adopted owner is used at upload time then.
    var userId: UUID?
    let entity: TombstoneEntity
    let recordIds: [UUID]
    let deletedAt: Date
}

/// Payload for `.deleteMonthPlan`.
struct DeleteMonthPlanPayload: Codable {
    let planId: UUID
}

/// Payload for `.deleteRestDay`: the remote row is matched by (user, day); `id` is the local id.
struct DeleteRestDayPayload: Codable {
    let id: UUID
    let date: Date
}

/// Payload for `.deletePersonalRecords`: removes the cloud PR rows of one exercise name, except
/// `keepId`, that were created on or before `cutoff`. The cutoff keeps a PR queued later safe.
struct DeletePersonalRecordsPayload: Codable {
    let exerciseName: String
    let keepId: UUID?
    let cutoff: Date
}

/// Payload for `.deleteExercise` (delete a single exercise).
struct DeleteExercisePayload: Codable {
    let exerciseId: UUID
}

/// Payload for `.renameExercises` (set the name of specific exercise rows).
struct RenameExercisesPayload: Codable {
    let ids: [UUID]
    let name: String
}

/// Payload for `.deleteContextSummaries`: AI summaries stored under workout-type names that were merged away.
struct DeleteContextSummariesPayload: Codable {
    let workoutTypes: [String]
}

/// Payload for `.deleteExercises` (delete every exercise of a workout).
struct DeleteExercisesPayload: Codable {
    let workoutId: UUID
}

// MARK: - Remote Writing Seam

/// The exact remote write methods the offline queue replays.
/// `SupabaseService` conforms; tests supply a scriptable fake.
protocol RemoteWriting: Sendable {
    func insertWorkout(_ workout: Workout) async throws
    func updateWorkout(_ workout: Workout) async throws
    func deleteWorkout(workoutId: UUID) async throws
    func deleteSet(setId: UUID) async throws
    func deleteExercise(id: UUID) async throws
    func deleteExercises(workoutId: UUID) async throws
    func insertExercises(_ exercises: [Exercise]) async throws
    func insertSet(_ workoutSet: WorkoutSet) async throws
    func updateExerciseNames(ids: [UUID], name: String) async throws
    func upsertProfile(_ profile: UserProfile) async throws
    func insertPersonalRecord(_ record: PersonalRecord) async throws
    func deletePersonalRecords(userId: UUID, exerciseName: String, keepId: UUID?, createdOnOrBefore: Date) async throws
    func upsertContextSummary(_ summary: AIContextSummary) async throws
    func deleteContextSummaries(userId: UUID, workoutTypes: [String]) async throws
    func insertMonthPlan(_ plan: MonthPlan) async throws
    func insertPlannedSessions(_ sessions: [PlannedSession]) async throws
    func updatePlannedSession(_ session: PlannedSession) async throws
    func deleteMonthPlan(planId: UUID) async throws
    func upsertRestDay(_ restDay: RestDay) async throws
    func deleteRestDay(userId: UUID, date: Date) async throws
    func insertTombstones(userId: UUID, entity: String, recordIds: [UUID], deletedAt: Date) async throws
}

extension SupabaseService: RemoteWriting, @unchecked Sendable {}

// MARK: - Local parent lookup

/// Lets the queue ask the local store whether a parent row (workout, exercise) exists on this device,
/// to repair child operations whose parent never reached the cloud.
protocol LocalParentLookup: Sendable {
    func workout(id: UUID) async -> Workout?
    func exercise(id: UUID) async -> Exercise?
}

/// Core Data backed lookup (reads on the main actor).
final class StorageParentLookup: LocalParentLookup, @unchecked Sendable {
    private let storage: LocalStorageService
    init(storage: LocalStorageService) { self.storage = storage }

    func workout(id: UUID) async -> Workout? {
        await MainActor.run { storage.fetchWorkout(id: id).map { Workout(from: $0) } }
    }

    func exercise(id: UUID) async -> Exercise? {
        await MainActor.run { storage.exerciseEntities(ids: [id])[id].map { Exercise(from: $0) } }
    }
}

// MARK: - Queued Operation

/// A single write operation held in the offline queue.
/// Payload is JSON-encoded so it survives process termination.
struct QueuedOperation: Codable, Identifiable {
    let id: String
    let type: QueuedOperationType
    var payload: Data
    var enqueuedAt: Date
    /// Causal order, assigned synchronously at the call site (see `OutboxSequencer`).
    /// 0 for legacy entries that predate it; those keep their stored position order.
    var sequence: Int64
    /// Identifies the single record an upsert-type operation writes, so a newer
    /// payload for the same record can replace a pending one. nil = never coalesced.
    var recordKey: String?
    /// User who made the change. nil only for legacy entries (adopted by the next signed-in user).
    var ownerUserId: UUID?
    var attempts: Int
    /// How many times this operation was dead-lettered; grows the wait before it is revived again.
    var deadLetterCount: Int = 0
    var lastErrorCode: String?
    var lastErrorMessage: String?
    var nextAttemptAt: Date?

    init(
        type: QueuedOperationType,
        payload: Data,
        ownerUserId: UUID? = nil,
        enqueuedAt: Date = Date(),
        sequence: Int64 = 0,
        recordKey: String? = nil
    ) {
        self.id = UUID().uuidString
        self.type = type
        self.payload = payload
        self.enqueuedAt = enqueuedAt
        self.sequence = sequence
        self.recordKey = recordKey
        self.ownerUserId = ownerUserId
        self.attempts = 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, payload, enqueuedAt, ownerUserId, attempts, sequence, recordKey, deadLetterCount
        case lastErrorCode, lastErrorMessage, nextAttemptAt
    }

    /// Decodes legacy entries that lack the newer fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(QueuedOperationType.self, forKey: .type)
        payload = try c.decode(Data.self, forKey: .payload)
        enqueuedAt = try c.decodeIfPresent(Date.self, forKey: .enqueuedAt) ?? Date()
        sequence = try c.decodeIfPresent(Int64.self, forKey: .sequence) ?? 0
        recordKey = try c.decodeIfPresent(String.self, forKey: .recordKey)
        ownerUserId = try c.decodeIfPresent(UUID.self, forKey: .ownerUserId)
        attempts = try c.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        deadLetterCount = try c.decodeIfPresent(Int.self, forKey: .deadLetterCount) ?? 0
        lastErrorCode = try c.decodeIfPresent(String.self, forKey: .lastErrorCode)
        lastErrorMessage = try c.decodeIfPresent(String.self, forKey: .lastErrorMessage)
        nextAttemptAt = try c.decodeIfPresent(Date.self, forKey: .nextAttemptAt)
    }
}

// MARK: - Sequencing helpers

/// Hands out strictly increasing operation numbers. Called synchronously at the
/// call site, before any async hop, so the number reflects the order in which the
/// app made its changes no matter how the follow-up tasks are scheduled.
final class OutboxSequencer: @unchecked Sendable {
    private let lock = NSLock()
    private var last: Int64
    /// Every number <= floor has arrived (or was dropped) in the queue.
    private var floor: Int64
    private var arrived = Set<Int64>()

    init(seed: Int64 = 0) { last = seed; floor = seed }

    /// The queue has seen this number (stored, coalesced, superseded or abandoned).
    func markArrived(_ value: Int64) {
        lock.lock(); defer { lock.unlock() }
        guard value > floor else { return }
        arrived.insert(value)
        while arrived.remove(floor + 1) != nil { floor += 1 }
    }

    /// Highest S such that every issued number <= S has arrived. Operations above it may
    /// still have an earlier (parent) write on its way, so they must wait.
    var contiguousPrefix: Int64 {
        lock.lock(); defer { lock.unlock() }
        return floor
    }

    func next() -> Int64 {
        lock.lock(); defer { lock.unlock() }
        last += 1
        return last
    }
}

/// Counts in-flight `submit` hops so tests can wait until everything has reached the queue.
final class SubmitTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func begin() { lock.lock(); inFlight += 1; lock.unlock() }

    func end() {
        lock.lock()
        inFlight -= 1
        let ready = inFlight == 0 ? waiters : []
        if inFlight == 0 { waiters = [] }
        lock.unlock()
        ready.forEach { $0.resume() }
    }

    func waitUntilIdle() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock()
            if inFlight == 0 {
                lock.unlock()
                c.resume()
            } else {
                waiters.append(c)
                lock.unlock()
            }
        }
    }
}

// MARK: - OfflineQueueManager

/// Durable queue of writes that couldn't reach Supabase yet.
///
/// - State lives in memory and is mirrored to JSON files in `directory` (atomic writes).
/// - Flushing is single-flight; operations are removed/updated by id only, so anything
///   enqueued while a flush is awaiting the network is never overwritten.
/// - Operations are tagged with the signed-in user and only replayed for that user.
/// - Failures are classified (`SyncErrorClassifier`): transient/dependency errors back off
///   and retry forever, permanent ones go to a dead-letter list, auth errors pause the pass.
actor OfflineQueueManager {

    static let legacyDefaultsKey = "lightstack_offline_queue_v1"
    static let migrationDoneKey = "lightstack_offline_queue_v1_migrated"

    private static let logger = Logger(subsystem: "org.lightstack.app", category: "OfflineQueue")

    private let remote: RemoteWriting
    private let directory: URL
    private let now: @Sendable () -> Date
    private let ownerProvider: @Sendable () async -> UUID?
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Assigns causal order synchronously at the call site; see `submit`.
    nonisolated let sequencer: OutboxSequencer
    private nonisolated let submitTracker = SubmitTracker()
    /// Upload right after a write is queued (off in tests and UI tests that must stay offline).
    private let autoFlush: Bool
    private let localLookup: LocalParentLookup?
    /// Operation being uploaded right now; never coalesced into (its payload is already read).
    private var executingId: String?

    private var queue: [QueuedOperation] = []
    private var failed: [QueuedOperation] = []
    private var loaded = false
    private var isFlushing = false
    private var needsAnotherPass = false
    private var unsavedOutcomes = 0

    /// Stop a pass after this many consecutive transient failures (likely offline).
    private let transientStreakLimit = 3
    /// Persist at most every N flush outcomes (replays are idempotent, see SyncErrorClassifier).
    private let saveEvery = 25

    private var queueURL: URL { directory.appendingPathComponent("queue.json") }
    private var failedURL: URL { directory.appendingPathComponent("failed.json") }

    init(
        remote: RemoteWriting,
        directory: URL,
        now: @escaping @Sendable () -> Date = { Date() },
        ownerProvider: @escaping @Sendable () async -> UUID?,
        defaults: UserDefaults = .standard,
        autoFlush: Bool = true,
        localLookup: LocalParentLookup? = nil
    ) {
        self.localLookup = localLookup
        self.remote = remote
        self.directory = directory
        self.now = now
        self.ownerProvider = ownerProvider
        self.defaults = defaults
        self.autoFlush = autoFlush
        self.sequencer = OutboxSequencer(seed: Self.persistedMaxSequence(in: directory))
    }

    /// Highest sequence already on disk, so numbers keep increasing across launches.
    private static func persistedMaxSequence(in directory: URL) -> Int64 {
        var best: Int64 = 0
        for name in ["queue.json", "failed.json"] {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { continue }
            let (ops, _) = decodeLossy(data)
            best = max(best, ops.map(\.sequence).max() ?? 0)
        }
        return best
    }

    /// `Application Support/OfflineQueue` (or a separate folder in UI-test mode).
    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        var name = "OfflineQueue"
        #if DEBUG
        if UITestMode.isActive { name = "OfflineQueue-UITests" }
        #endif
        return base.appendingPathComponent(name, isDirectory: true)
    }

    // MARK: - Public Interface

    /// Operations waiting to upload for the current user.
    var pendingCount: Int {
        get async {
            loadIfNeeded()
            let owner = await ownerProvider()
            return queue.filter { Self.belongs($0, to: owner) }.count
        }
    }

    /// Dead-lettered operations for the current user.
    var failedCount: Int {
        get async {
            loadIfNeeded()
            let owner = await ownerProvider()
            return failed.filter { Self.belongs($0, to: owner) }.count
        }
    }

    // MARK: - Submitting writes (call-site API)

    /// Queue a write from synchronous code. The causal sequence number is taken
    /// right here, before any task hop, so the order the app made its changes in
    /// is what the queue replays. The write is then queued (and uploaded, when
    /// `autoFlush`) in the background.
    ///
    /// - Parameter recordKey: identifies the one record an upsert writes; a pending
    ///   operation of the same type and key is replaced by this newer payload.
    nonisolated func submit<T: Encodable>(_ type: QueuedOperationType, payload: T, recordKey: String? = nil) {
        guard let data = try? JSONEncoder().encode(payload) else {
            Self.logger.error("submit failed to encode payload for \(type.rawValue, privacy: .public)")
            return
        }
        let sequence = sequencer.next()
        launch { await $0.enqueueEncoded(type, data: data, recordKey: recordKey, sequence: sequence) }
    }

    /// "Delete all exercises of a workout" (part of a workout replace); supersedes
    /// earlier-sequenced queued inserts for that workout. See `enqueueDeleteExercises`.
    nonisolated func submitDeleteExercises(workoutId: UUID) {
        let sequence = sequencer.next()
        launch { await $0.enqueueDeleteExercises(workoutId: workoutId, sequence: sequence) }
    }

    /// Delete the AI summaries stored under these workout types (a workout-type merge). Pending
    /// earlier-sequenced upserts for the same types are dropped so they cannot recreate the rows.
    nonisolated func submitDeleteContextSummaries(types: [String]) {
        guard !types.isEmpty else { return }
        let sequence = sequencer.next()
        launch { await $0.enqueueDeleteContextSummaries(types: types, sequence: sequence) }
    }

    /// Record that these rows were deleted (uploaded to `sync_tombstones`, sorted after the deletes).
    nonisolated func submitTombstones(_ entity: TombstoneEntity, ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let sequence = sequencer.next()
        let deletedAt = now()
        launch { await $0.enqueueTombstone(entity: entity, ids: ids, deletedAt: deletedAt, sequence: sequence) }
    }

    /// Wait until every `submit*` call made so far has reached the queue (tests).
    func waitForSubmissions() async {
        await submitTracker.waitUntilIdle()
    }

    private nonisolated func launch(_ work: @escaping @Sendable (OfflineQueueManager) async -> Void) {
        submitTracker.begin()
        let tracker = submitTracker
        Task {
            await work(self)
            tracker.end()
        }
    }

    /// Upload promptly after a write. Single-flight: if a flush is running it just
    /// runs another pass, so bursts of writes coalesce.
    func flushSoon() async {
        guard autoFlush else { return }
        await flush()
    }

    // MARK: - Enqueue

    /// Encode and append an operation to the persistent queue.
    func enqueue<T: Encodable>(_ type: QueuedOperationType, payload: T, recordKey: String? = nil) async {
        let data: Data
        do {
            data = try encoder.encode(payload)
        } catch {
            Self.logger.error("enqueue failed to encode payload for \(type.rawValue, privacy: .public)")
            return
        }
        await enqueueEncoded(type, data: data, recordKey: recordKey, sequence: sequencer.next(), flush: false)
    }

    func enqueueEncoded(
        _ type: QueuedOperationType, data: Data, recordKey: String?, sequence: Int64, flush: Bool = true
    ) async {
        let owner = await ownerProvider()
        loadIfNeeded()
        if type == .upsertContextSummary, let model = try? decoder.decode(AIContextSummary.self, from: data) {
            // A fresh summary for a type revives it: a still-queued delete must not wipe it.
            removePendingSummaryDeletes(of: model.workoutType, owner: owner, before: sequence)
        }
        append(type, data: data, recordKey: recordKey, sequence: sequence, owner: owner)
        saveQueue()
        if flush { await flushSoon() }
    }

    private func removePendingSummaryDeletes(of workoutType: String, owner: UUID?, before sequence: Int64) {
        var updated: [QueuedOperation] = []
        for var op in queue {
            guard op.type == .deleteContextSummaries, op.ownerUserId == owner, op.id != executingId,
                  op.sequence < sequence,
                  let model = try? decoder.decode(DeleteContextSummariesPayload.self, from: op.payload),
                  model.workoutTypes.contains(workoutType) else { updated.append(op); continue }
            let kept = model.workoutTypes.filter { $0 != workoutType }
            if kept.isEmpty { continue }
            if let data = try? encoder.encode(DeleteContextSummariesPayload(workoutTypes: kept)) { op.payload = data }
            updated.append(op)
        }
        if updated.count != queue.count || zip(updated, queue).contains(where: { $0.payload != $1.payload }) { queue = updated }
    }

    private func enqueueDeleteContextSummaries(types: [String], sequence: Int64) async {
        let owner = await ownerProvider()
        loadIfNeeded()
        let doomed = Set(types)
        // Earlier-sequenced upserts for these types would resurrect the rows: drop them.
        queue.removeAll { op in
            guard op.type == .upsertContextSummary, op.ownerUserId == owner, op.id != executingId,
                  op.sequence < sequence,
                  let model = try? decoder.decode(AIContextSummary.self, from: op.payload) else { return false }
            return doomed.contains(model.workoutType)
        }
        if let data = try? encoder.encode(DeleteContextSummariesPayload(workoutTypes: types)) {
            append(.deleteContextSummaries, data: data, recordKey: nil, sequence: sequence, owner: owner)
        } else {
            sequencer.markArrived(sequence)
        }
        saveQueue()
        await flushSoon()
    }

    /// Adds the operation, or swaps the payload of a pending one for the same record
    /// (the higher sequence wins). Deletes and inserts are never merged: only an
    /// operation of the same type can absorb it.
    private func append(_ type: QueuedOperationType, data: Data, recordKey: String?, sequence: Int64, owner: UUID?) {
        defer { sequencer.markArrived(sequence) }
        if let key = recordKey,
           let idx = queue.firstIndex(where: {
               $0.type == type && $0.recordKey == key && $0.ownerUserId == owner && $0.id != executingId
           }) {
            if sequence >= queue[idx].sequence {
                queue[idx].payload = data
                queue[idx].sequence = sequence
                queue[idx].enqueuedAt = now()
                // The new payload may fix whatever failed before, so make it due again.
                queue[idx].attempts = 0
                queue[idx].nextAttemptAt = nil
                queue[idx].lastErrorCode = nil
                queue[idx].lastErrorMessage = nil
            }
            return
        }
        queue.append(QueuedOperation(
            type: type, payload: data, ownerUserId: owner, enqueuedAt: now(),
            sequence: sequence, recordKey: recordKey
        ))
    }

    private func enqueueTombstone(entity: TombstoneEntity, ids: [UUID], deletedAt: Date, sequence: Int64) async {
        let owner = await ownerProvider()
        let payload = TombstonePayload(userId: owner, entity: entity, recordIds: ids, deletedAt: deletedAt)
        guard let data = try? encoder.encode(payload) else {
            Self.logger.error("enqueueTombstone failed to encode payload")
            sequencer.markArrived(sequence)   // never block later writes on a lost one
            await flushSoon()
            return
        }
        loadIfNeeded()
        append(.insertTombstone, data: data, recordKey: nil, sequence: sequence, owner: owner)
        saveQueue()
        await flushSoon()
    }

    /// Queue "delete all exercises of a workout" (part of a workout replace).
    /// Still-queued inserts for that workout's exercises/sets, and earlier
    /// deleteExercises for it, are superseded by this replace and are dropped
    /// (only those sequenced BEFORE it: newer inserts are the replacement content).
    /// Without this, flush() would re-insert the old exercises (inserts run after
    /// deleteExercises) alongside the new ones.
    func enqueueDeleteExercises(workoutId: UUID, sequence: Int64? = nil) async {
        let seq = sequence ?? sequencer.next()
        let data: Data
        do {
            data = try encoder.encode(DeleteExercisesPayload(workoutId: workoutId))
        } catch {
            Self.logger.error("enqueueDeleteExercises failed to encode payload")
            sequencer.markArrived(seq)
            await flushSoon()
            return
        }
        let owner = await ownerProvider()
        loadIfNeeded()

        var staleExerciseIds = Set<UUID>()
        queue.removeAll { op in
            guard op.sequence < seq, op.id != executingId else { return false }
            switch op.type {
            case .insertExercises:
                guard let models = try? decoder.decode([Exercise].self, from: op.payload),
                      models.contains(where: { $0.workoutId == workoutId }) else { return false }
                models.forEach { staleExerciseIds.insert($0.id) }
                return true
            case .deleteExercises:
                guard let model = try? decoder.decode(DeleteExercisesPayload.self, from: op.payload) else { return false }
                return model.workoutId == workoutId
            default:
                return false
            }
        }
        queue.removeAll { op in
            guard op.type == .insertSet, op.sequence < seq, op.id != executingId,
                  let model = try? decoder.decode(WorkoutSet.self, from: op.payload) else { return false }
            return staleExerciseIds.contains(model.exerciseId)
        }
        append(.deleteExercises, data: data, recordKey: nil, sequence: seq, owner: owner)
        saveQueue()
        await flushSoon()
    }

    /// Remove all queued operations and the dead-letter list. Tests/debug only;
    /// NOT called on sign-out (unsynced changes must survive).
    func clearQueue() {
        loadIfNeeded()
        queue = []
        failed = []
        saveQueue()
        saveFailed()
    }

    /// Move the current user's dead-lettered operations back into the queue.
    func retryFailed() async {
        loadIfNeeded()
        let owner = await ownerProvider()
        var revived: [QueuedOperation] = []
        failed.removeAll { op in
            guard Self.belongs(op, to: owner) else { return false }
            var copy = op
            copy.attempts = 0
            copy.nextAttemptAt = nil
            copy.lastErrorCode = nil
            copy.lastErrorMessage = nil
            if copy.ownerUserId == nil { copy.ownerUserId = owner }
            revived.append(copy)
            return true
        }
        guard !revived.isEmpty else { return }
        queue.append(contentsOf: revived)
        saveQueue()
        saveFailed()
        Self.logger.info("retryFailed revived \(revived.count) operations")
    }

    /// Wait before a dead-lettered operation is tried again: 1 minute, 1 hour, then 24 hours (cap).
    static func revivalDelay(deadLetterCount: Int) -> TimeInterval {
        let schedule: [TimeInterval] = [60, 3600, 86_400]
        return schedule[min(max(deadLetterCount, 1), schedule.count) - 1]
    }

    /// Moves the current user's dead-lettered operations whose revival time has come back into the
    /// queue (call once per launch and on sign-in). Nothing is ever dropped: an operation the server
    /// still refuses returns to the dead-letter list with a longer wait. Revived operations keep their
    /// causal sequence, so they upload parent-first like any others.
    @discardableResult
    func reviveDueFailedOperations() async -> Int {
        loadIfNeeded()
        guard let owner = await ownerProvider() else { return 0 }
        let current = now()
        var revived: [QueuedOperation] = []
        failed.removeAll { op in
            guard Self.belongs(op, to: owner), op.nextAttemptAt.map({ $0 <= current }) ?? true else { return false }
            var copy = op
            copy.attempts = 0
            copy.nextAttemptAt = nil
            if copy.ownerUserId == nil { copy.ownerUserId = owner }
            revived.append(copy)
            return true
        }
        guard !revived.isEmpty else { return 0 }
        queue.append(contentsOf: revived)
        saveQueue()
        saveFailed()
        Self.logger.info("revived \(revived.count) dead-lettered operations")
        return revived.count
    }

    // MARK: - Dependency resolver

    private enum ParentStatus { case ok, orphan }

    /// Error codes that mean "the parent row isn't in the cloud" for a child write.
    private static let parentMissingCodes: Set<String> = ["42501", "23503", "http.403"]

    /// Repairs child operations (exercises, sets, renames) whose parent never reached the cloud:
    ///  a. parent has a queued or dead-lettered operation: nothing to do (type order uploads it first);
    ///  b. parent exists locally: its upsert is queued (workout, exercise, then the set), and a
    ///     dead-lettered child is revived at once;
    ///  c. parent does not exist locally, or is tombstoned: the child is an orphan and is removed
    ///     for good (queue or dead-letter list). Only counts are logged.
    /// Only operations that already failed with a parent-missing error (or sit in the dead-letter list)
    /// are examined. Repeats until stable so a set -> exercise -> workout chain resolves in one call.
    /// - Parameter tombstoned: cloud tombstones known to the caller (restore); queued tombstones are always honoured.
    @discardableResult
    func resolveDependencies(tombstoned: [TombstoneEntity: Set<UUID>] = [:]) async -> Int {
        guard let lookup = localLookup else { return 0 }
        loadIfNeeded()
        guard let owner = await ownerProvider() else { return 0 }

        var createdIds = Set<String>()
        var queuedWorkouts = Set<UUID>()
        var queuedExercises = Set<UUID>()
        var orphanedExercises = Set<UUID>()
        var workoutCache: [UUID: Workout?] = [:]
        var exerciseCache: [UUID: Exercise?] = [:]
        var orphans = 0, parentsQueued = 0, revived = 0
        let dec = JSONDecoder()

        func isEligible(_ op: QueuedOperation, failedList: Bool) -> Bool {
            guard SyncErrorClassifier.parentCheckedTypes.contains(op.type), op.type != .deleteExercise,
                  op.type != .deleteExercises, op.type != .deleteSet else { return false }
            if failedList || createdIds.contains(op.id) { return true }
            return op.lastErrorCode.map { Self.parentMissingCodes.contains($0) } ?? false
        }

        for _ in 0..<6 {
            var changed = false
            let index = pendingChangeIndex(for: owner)

            func workoutStatus(_ id: UUID) async -> ParentStatus {
                if tombstoned[.workout]?.contains(id) == true || index.hasPendingTombstone(.workout, id) { return .orphan }
                if queuedWorkouts.contains(id) { return .ok }
                if index.headerWorkouts.contains(id) {
                    if promoteFailedParents(workoutId: id, exerciseId: nil) { revived += 1; changed = true }
                    return .ok
                }
                let local: Workout?
                if let cached = workoutCache[id] { local = cached } else {
                    local = await lookup.workout(id: id); workoutCache[id] = .some(local)
                }
                guard let workout = local, let data = try? encoder.encode(workout) else { return .orphan }
                append(.insertWorkout, data: data, recordKey: id.uuidString, sequence: sequencer.next(), owner: owner)
                queuedWorkouts.insert(id)
                parentsQueued += 1
                changed = true
                return .ok
            }

            func exerciseStatus(_ id: UUID) async -> ParentStatus {
                if orphanedExercises.contains(id) { return .orphan }
                if tombstoned[.exercise]?.contains(id) == true || index.hasPendingTombstone(.exercise, id) { return .orphan }
                if queuedExercises.contains(id) { return .ok }
                if index.insertedExercises.contains(id) {
                    if promoteFailedParents(workoutId: nil, exerciseId: id) { revived += 1; changed = true }
                    return .ok
                }
                let local: Exercise?
                if let cached = exerciseCache[id] { local = cached } else {
                    local = await lookup.exercise(id: id); exerciseCache[id] = .some(local)
                }
                guard let exercise = local, let data = try? encoder.encode([exercise]) else { return .orphan }
                append(.insertExercises, data: data, recordKey: nil, sequence: sequencer.next(), owner: owner)
                if let last = queue.last { createdIds.insert(last.id) }
                queuedExercises.insert(id)
                parentsQueued += 1
                changed = true
                return .ok
            }

            // Exercises before sets, so a set sees whether its exercise was just dropped.
            let snapshot = (queue.map { ($0, false) } + failed.map { ($0, true) })
                .sorted { ($0.0.type == .insertExercises ? 0 : 1) < ($1.0.type == .insertExercises ? 0 : 1) }
            for (op, inFailed) in snapshot where Self.belongs(op, to: owner) && isEligible(op, failedList: inFailed) {
                guard op.id != executingId else { continue }
                var keptPayload: Data?
                var droppedAny = false
                var remove = false

                switch op.type {
                case .insertExercises:
                    guard let models = try? dec.decode([Exercise].self, from: op.payload) else { continue }
                    var kept: [Exercise] = []
                    for model in models {
                        if await workoutStatus(model.workoutId) == .ok { kept.append(model) } else { droppedAny = true }
                    }
                    orphans += models.count - kept.count
                    let keptIds = Set(kept.map(\.id))
                    models.filter { !keptIds.contains($0.id) }.forEach { orphanedExercises.insert($0.id) }
                    if kept.isEmpty { remove = true } else if droppedAny { keptPayload = try? encoder.encode(kept) }
                case .insertSet:
                    guard let model = try? dec.decode(WorkoutSet.self, from: op.payload) else { continue }
                    if await exerciseStatus(model.exerciseId) != .ok { remove = true; orphans += 1 }
                case .renameExercises:
                    guard let model = try? dec.decode(RenameExercisesPayload.self, from: op.payload) else { continue }
                    var kept: [UUID] = []
                    for id in model.ids {
                        if await exerciseStatus(id) == .ok { kept.append(id) } else { droppedAny = true }
                    }
                    orphans += model.ids.count - kept.count
                    if kept.isEmpty { remove = true }
                    else if droppedAny { keptPayload = try? encoder.encode(RenameExercisesPayload(ids: kept, name: model.name)) }
                default:
                    continue
                }

                if remove || keptPayload != nil || inFailed {
                    changed = true
                    // Take it out of wherever it sits, then (unless orphaned) put it back live.
                    queue.removeAll { $0.id == op.id }
                    failed.removeAll { $0.id == op.id }
                    if !remove {
                        var live = op
                        if let data = keptPayload { live.payload = data }
                        live.attempts = 0
                        live.nextAttemptAt = nil
                        queue.append(live)
                        createdIds.insert(live.id)
                        if inFailed { revived += 1 }
                    }
                } else if keptPayload == nil {
                    // Parent chain is queued; make the child due right away so it follows it.
                    if let i = queue.firstIndex(where: { $0.id == op.id }), queue[i].nextAttemptAt != nil {
                        queue[i].nextAttemptAt = nil
                        changed = true
                    }
                }
            }
            if !changed { break }
        }

        if orphans + parentsQueued + revived > 0 {
            saveQueue()
            saveFailed()
            Self.logger.info("resolved dependencies: parentsQueued=\(parentsQueued) orphansDropped=\(orphans) revived=\(revived)")
        }
        return orphans
    }

    /// A parent whose own operation is dead-lettered must be live again for its children to succeed.
    private func promoteFailedParents(workoutId: UUID?, exerciseId: UUID?) -> Bool {
        let dec = JSONDecoder()
        var moved: [String] = []
        for op in failed {
            switch op.type {
            case .insertWorkout, .updateWorkout:
                if let id = workoutId, let m = try? dec.decode(Workout.self, from: op.payload), m.id == id { moved.append(op.id) }
            case .insertExercises:
                if let id = exerciseId, let ms = try? dec.decode([Exercise].self, from: op.payload), ms.contains(where: { $0.id == id }) {
                    moved.append(op.id)
                }
            default: break
            }
        }
        guard !moved.isEmpty else { return false }
        for id in moved {
            guard let i = failed.firstIndex(where: { $0.id == id }) else { continue }
            var op = failed.remove(at: i)
            op.attempts = 0
            op.nextAttemptAt = nil
            queue.append(op)
        }
        return true
    }

    /// Snapshot of the dead-letter list (for tests/debug UI).
    func failedOperations() -> [QueuedOperation] {
        loadIfNeeded()
        return failed
    }

    /// Snapshot of the queue (for tests/debug UI).
    func queuedOperations() -> [QueuedOperation] {
        loadIfNeeded()
        return queue
    }

    /// Records another device deleted (restore found their tombstones).
    struct DeletedRecords {
        var workouts = Set<UUID>()
        var exercises = Set<UUID>()
        var sets = Set<UUID>()
        var monthPlans = Set<UUID>()
        var plannedSessions = Set<UUID>()
        var restDays = Set<UUID>()
    }

    /// Drops the owner's pending UPSERT operations for records that were deleted elsewhere, so they
    /// cannot recreate a stray cloud row. Deletes and tombstones stay queued. Batched payloads
    /// (exercises, planned sessions) lose only the deleted members. Returns operations dropped or trimmed.
    @discardableResult
    func discardPendingUpserts(for owner: UUID, deleted: DeletedRecords) -> Int {
        loadIfNeeded()
        var changed = 0
        var deletedExercises = deleted.exercises
        var keep: [QueuedOperation] = []

        // Exercises first: sets of a dropped exercise go with it.
        var pass: [QueuedOperation] = []
        for var op in queue {
            guard op.ownerUserId == owner, op.id != executingId else { pass.append(op); continue }
            if op.type == .insertExercises, let models = try? decoder.decode([Exercise].self, from: op.payload) {
                let kept = models.filter { !deleted.exercises.contains($0.id) && !deleted.workouts.contains($0.workoutId) }
                models.filter { !kept.map(\.id).contains($0.id) }.forEach { deletedExercises.insert($0.id) }
                if kept.count != models.count {
                    changed += 1
                    if kept.isEmpty { continue }
                    if let data = try? encoder.encode(kept) { op.payload = data }
                }
            }
            pass.append(op)
        }
        for var op in pass {
            guard op.ownerUserId == owner, op.id != executingId else { keep.append(op); continue }
            switch op.type {
            case .insertWorkout, .updateWorkout:
                if let m = try? decoder.decode(Workout.self, from: op.payload), deleted.workouts.contains(m.id) { changed += 1; continue }
            case .insertSet:
                if let m = try? decoder.decode(WorkoutSet.self, from: op.payload),
                   deleted.sets.contains(m.id) || deletedExercises.contains(m.exerciseId) { changed += 1; continue }
            case .renameExercises:
                if let m = try? decoder.decode(RenameExercisesPayload.self, from: op.payload) {
                    let kept = m.ids.filter { !deletedExercises.contains($0) }
                    if kept.count != m.ids.count {
                        changed += 1
                        if kept.isEmpty { continue }
                        if let data = try? encoder.encode(RenameExercisesPayload(ids: kept, name: m.name)) { op.payload = data }
                    }
                }
            case .insertMonthPlan:
                if let m = try? decoder.decode(MonthPlan.self, from: op.payload), deleted.monthPlans.contains(m.id) { changed += 1; continue }
            case .insertPlannedSessions:
                if let models = try? decoder.decode([PlannedSession].self, from: op.payload) {
                    let kept = models.filter { !deleted.plannedSessions.contains($0.id) && !deleted.monthPlans.contains($0.monthPlanId) }
                    if kept.count != models.count {
                        changed += 1
                        if kept.isEmpty { continue }
                        if let data = try? encoder.encode(kept) { op.payload = data }
                    }
                }
            case .updatePlannedSession:
                if let m = try? decoder.decode(PlannedSession.self, from: op.payload),
                   deleted.plannedSessions.contains(m.id) || deleted.monthPlans.contains(m.monthPlanId) { changed += 1; continue }
            case .upsertRestDay:
                if let m = try? decoder.decode(RestDay.self, from: op.payload), deleted.restDays.contains(m.id) { changed += 1; continue }
            default:
                break
            }
            keep.append(op)
        }
        if changed > 0 {
            queue = keep
            saveQueue()
            Self.logger.info("discarded \(changed) pending upserts for records deleted elsewhere")
        }
        return changed
    }

    /// Which records the user's still-unuploaded operations (queued or dead-lettered) touch.
    /// A restore must not overwrite those records with older cloud copies.
    /// Call `waitForSubmissions()` first so writes made a moment ago are included.
    func pendingChangeIndex(for owner: UUID) -> PendingChangeIndex {
        loadIfNeeded()
        var index = PendingChangeIndex()
        for op in queue + failed where Self.belongs(op, to: owner) {
            index.absorb(op)
        }
        return index
    }

    // MARK: - Flush

    /// Upload pending operations for the signed-in user in FK-dependency order.
    /// Single-flight: a request made while a flush is running makes it loop once more.
    func flush() async {
        loadIfNeeded()
        if isFlushing {
            needsAnotherPass = true
            return
        }
        isFlushing = true
        defer { isFlushing = false }

        await resolveDependencies()
        repeat {
            needsAnotherPass = false
            let shouldContinue = await runPass()
            if !shouldContinue { break }
        } while needsAnotherPass
        savePendingChanges()
    }

    /// Returns false when the pass was cut short (auth, owner change, offline) and
    /// looping again right away would be pointless.
    private func runPass() async -> Bool {
        guard let owner = await ownerProvider() else {
            Self.logger.info("flush skipped: no signed-in user")
            return false
        }
        adoptLegacyOperations(for: owner)

        let startNow = now()
        // Only the contiguous arrived prefix: a later write (e.g. a child) must not run
        // while an earlier one (its parent) is still on its way to the queue.
        let prefix = sequencer.contiguousPrefix
        let eligible = queue.filter { op in
            op.ownerUserId == owner && (op.sequence == 0 || op.sequence <= prefix)
                && (op.nextAttemptAt.map { $0 <= startNow } ?? true)
        }
        let ordered = Self.fkOrdered(eligible)
        let seenIds = Set(ordered.map(\.id))
        guard !ordered.isEmpty else { return true }

        Self.logger.info("flush pass start: \(ordered.count) due of \(self.queue.count) queued")

        var succeeded = 0, retrying = 0, deadLettered = 0
        var transientStreak = 0
        var stopped = false

        for snapshotOp in ordered {
            // The owner can change mid-pass (sign-out / account switch).
            guard await ownerProvider() == owner else {
                Self.logger.info("flush stopped: signed-in user changed")
                stopped = true
                break
            }
            // Might have been superseded (enqueueDeleteExercises) or cleared meanwhile.
            guard let current = queue.first(where: { $0.id == snapshotOp.id }) else { continue }

            executingId = current.id
            defer { executingId = nil }
            do {
                try await execute(current)
                removeFromQueue(id: current.id)
                succeeded += 1
                transientStreak = 0
            } catch {
                let cls = SyncErrorClassifier.classify(error, opType: current.type)
                let code = SyncErrorClassifier.errorCode(for: error)
                Self.logger.info("op \(current.type.rawValue, privacy: .public) failed: \(String(describing: cls), privacy: .public) code=\(code, privacy: .public)")
                switch cls {
                case .alreadyApplied:
                    removeFromQueue(id: current.id)
                    succeeded += 1
                    transientStreak = 0
                case .auth:
                    stopped = true
                case .permanent:
                    deadLetter(id: current.id, code: code, message: SyncErrorClassifier.errorMessage(for: error))
                    deadLettered += 1
                    transientStreak = 0
                case .transient, .dependency:
                    scheduleRetry(id: current.id, code: code, message: SyncErrorClassifier.errorMessage(for: error),
                                  dependency: cls == .dependency)
                    retrying += 1
                    if cls == .transient { transientStreak += 1 }
                    if transientStreak >= transientStreakLimit { stopped = true }
                }
            }
            if stopped { break }
            if unsavedOutcomes >= saveEvery { savePendingChanges() }
        }

        savePendingChanges()
        Self.logger.info("flush pass end: ok=\(succeeded) retrying=\(retrying) failed=\(deadLettered) stopped=\(stopped)")

        if stopped { return false }
        // Anything enqueued during the pass that was due and not yet handled -> go again.
        let checkNow = now()
        let latePrefix = sequencer.contiguousPrefix
        let late = queue.contains { op in
            op.ownerUserId == owner && !seenIds.contains(op.id)
                && (op.sequence == 0 || op.sequence <= latePrefix)
                && (op.nextAttemptAt.map { $0 <= checkNow } ?? true)
        }
        if late { needsAnotherPass = true }
        return true
    }

    // MARK: - State mutation (by id, never from a stale snapshot)

    private func removeFromQueue(id: String) {
        queue.removeAll { $0.id == id }
        unsavedOutcomes += 1
    }

    private func scheduleRetry(id: String, code: String, message: String, dependency: Bool = false) {
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[idx].attempts += 1
        queue[idx].lastErrorCode = code
        queue[idx].lastErrorMessage = message
        let delay = Self.backoff(attempts: queue[idx].attempts, dependency: dependency)
        queue[idx].nextAttemptAt = now().addingTimeInterval(delay)
        unsavedOutcomes += 1
        // A missing parent usually shows up within seconds: look again soon.
        if dependency, autoFlush, delay <= Self.fastRetryDelays.max() ?? 0 {
            let nanos = UInt64(delay * 1_000_000_000) + 100_000_000
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: nanos)
                await self?.flush()
            }
        }
    }

    private func deadLetter(id: String, code: String, message: String) {
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }
        var op = queue.remove(at: idx)
        op.attempts += 1
        op.lastErrorCode = code
        op.lastErrorMessage = message
        // Next automatic revival (see reviveDueFailedOperations); the operation stays in failed.json until then.
        op.deadLetterCount += 1
        op.nextAttemptAt = now().addingTimeInterval(Self.revivalDelay(deadLetterCount: op.deadLetterCount))
        failed.append(op)
        saveFailed()
        unsavedOutcomes += 1
    }

    private func adoptLegacyOperations(for owner: UUID) {
        var changed = false
        for i in queue.indices where queue[i].ownerUserId == nil {
            queue[i].ownerUserId = owner
            changed = true
        }
        for i in failed.indices where failed[i].ownerUserId == nil {
            failed[i].ownerUserId = owner
            changed = true
        }
        if changed { saveQueue(); saveFailed() }
    }

    /// Exponential backoff: 10s, 20s, 40s ... capped at 1h.
    /// Quick retries for a foreign-key failure (parent likely just late): 2s, 2s, 5s.
    static let fastRetryDelays: [TimeInterval] = [2, 2, 5]

    static func backoff(attempts: Int, dependency: Bool = false) -> TimeInterval {
        if dependency, attempts >= 1, attempts <= fastRetryDelays.count { return fastRetryDelays[attempts - 1] }
        return min(pow(2, Double(min(max(attempts, 0), 20))) * 5, 3600)
    }

    private static func belongs(_ op: QueuedOperation, to owner: UUID?) -> Bool {
        guard let owner else { return false }
        return op.ownerUserId == nil || op.ownerUserId == owner
    }

    // MARK: - Ordering

    /// Parents before children; deleteExercises before inserts; deletes (then their
    /// tombstones) last; within a kind by causal `sequence`, then stored position (which
    /// keeps legacy entries, all sequence 0, in their original FIFO order).
    /// Unknown types sort to the end, never dropped.
    static func fkOrdered(_ ops: [QueuedOperation]) -> [QueuedOperation] {
        let order: [QueuedOperationType] = [
            .insertWorkout, .updateWorkout,
            // deleteExercises is a "clear before re-insert" step of a workout replace, so it
            // must run after updateWorkout but BEFORE insertExercises/insertSet. If it sat with
            // the other deletes (last) it would wipe the freshly inserted exercises.
            // enqueueDeleteExercises() drops superseded inserts so repeated replaces don't duplicate.
            .deleteExercises,
            .insertExercises, .insertSet,
            .renameExercises,
            .upsertProfile, .insertPersonalRecord,
            .upsertContextSummary,
            // After the upsert, so a summary that was merged away is deleted last.
            .deleteContextSummaries,
            .insertMonthPlan, .insertPlannedSessions, .updatePlannedSession,
            .upsertRestDay,
            // Delete operations should be last, tombstones after the deletes they record.
            .deleteWorkout, .deleteSet, .deleteExercise, .deleteMonthPlan, .deleteRestDay,
            .deletePersonalRecords,
            .insertTombstone
        ]
        var rank: [QueuedOperationType: Int] = [:]
        for (i, t) in order.enumerated() { rank[t] = i }
        return ops.enumerated().sorted { a, b in
            let ai = rank[a.element.type] ?? order.count
            let bi = rank[b.element.type] ?? order.count
            if ai != bi { return ai < bi }
            if a.element.sequence != b.element.sequence { return a.element.sequence < b.element.sequence }
            return a.offset < b.offset
        }.map(\.element)
    }

    // MARK: - Execute

    private func execute(_ op: QueuedOperation) async throws {
        switch op.type {
        case .insertWorkout:
            let model = try decoder.decode(Workout.self, from: op.payload)
            try await remote.insertWorkout(model)
        case .updateWorkout:
            let model = try decoder.decode(Workout.self, from: op.payload)
            try await remote.updateWorkout(model)
        case .insertExercises:
            let models = try decoder.decode([Exercise].self, from: op.payload)
            try await remote.insertExercises(models)
        case .insertSet:
            let model = try decoder.decode(WorkoutSet.self, from: op.payload)
            try await remote.insertSet(model)
        case .upsertProfile:
            let model = try decoder.decode(UserProfile.self, from: op.payload)
            try await remote.upsertProfile(model)
        case .insertPersonalRecord:
            let model = try decoder.decode(PersonalRecord.self, from: op.payload)
            try await remote.insertPersonalRecord(model)
        case .deletePersonalRecords:
            let model = try decoder.decode(DeletePersonalRecordsPayload.self, from: op.payload)
            guard let userId = op.ownerUserId else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "PR delete without user"))
            }
            try await remote.deletePersonalRecords(
                userId: userId, exerciseName: model.exerciseName, keepId: model.keepId, createdOnOrBefore: model.cutoff
            )
        case .upsertContextSummary:
            let model = try decoder.decode(AIContextSummary.self, from: op.payload)
            try await remote.upsertContextSummary(model)
        case .insertMonthPlan:
            let model = try decoder.decode(MonthPlan.self, from: op.payload)
            try await remote.insertMonthPlan(model)
        case .insertPlannedSessions:
            let models = try decoder.decode([PlannedSession].self, from: op.payload)
            try await remote.insertPlannedSessions(models)
        case .updatePlannedSession:
            let model = try decoder.decode(PlannedSession.self, from: op.payload)
            try await remote.updatePlannedSession(model)
        case .deleteWorkout:
            let model = try decoder.decode(Workout.self, from: op.payload)
            try await remote.deleteWorkout(workoutId: model.id)
        case .deleteSet:
            let model = try decoder.decode(WorkoutSet.self, from: op.payload)
            try await remote.deleteSet(setId: model.id)
        case .deleteExercise:
            let model = try decoder.decode(DeleteExercisePayload.self, from: op.payload)
            try await remote.deleteExercise(id: model.exerciseId)
        case .deleteExercises:
            let model = try decoder.decode(DeleteExercisesPayload.self, from: op.payload)
            try await remote.deleteExercises(workoutId: model.workoutId)
        case .renameExercises:
            let model = try decoder.decode(RenameExercisesPayload.self, from: op.payload)
            try await remote.updateExerciseNames(ids: model.ids, name: model.name)
        case .deleteContextSummaries:
            let model = try decoder.decode(DeleteContextSummariesPayload.self, from: op.payload)
            guard let userId = op.ownerUserId else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "summary delete without user"))
            }
            try await remote.deleteContextSummaries(userId: userId, workoutTypes: model.workoutTypes)
        case .deleteMonthPlan:
            let model = try decoder.decode(DeleteMonthPlanPayload.self, from: op.payload)
            try await remote.deleteMonthPlan(planId: model.planId)
        case .upsertRestDay:
            let model = try decoder.decode(RestDay.self, from: op.payload)
            try await remote.upsertRestDay(model)
        case .deleteRestDay:
            let model = try decoder.decode(DeleteRestDayPayload.self, from: op.payload)
            guard let userId = op.ownerUserId else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "rest day delete without user"))
            }
            try await remote.deleteRestDay(userId: userId, date: model.date)
        case .insertTombstone:
            let model = try decoder.decode(TombstonePayload.self, from: op.payload)
            guard let userId = model.userId ?? op.ownerUserId else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "tombstone without user"))
            }
            try await remote.insertTombstones(
                userId: userId, entity: model.entity.rawValue, recordIds: model.recordIds, deletedAt: model.deletedAt
            )
        }
    }

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let queueExists = FileManager.default.fileExists(atPath: queueURL.path)
        queue = readOperations(at: queueURL, label: "queue")
        failed = readOperations(at: failedURL, label: "failed")

        // One-time import of the old UserDefaults queue (key left in place for one release).
        if !queueExists, !defaults.bool(forKey: Self.migrationDoneKey) {
            if let legacy = defaults.data(forKey: Self.legacyDefaultsKey) {
                let (ops, _) = Self.decodeLossy(legacy)
                if !ops.isEmpty {
                    queue.append(contentsOf: ops)
                    saveQueue()
                    Self.logger.info("migrated \(ops.count) legacy operations")
                }
            }
        }
        if !defaults.bool(forKey: Self.migrationDoneKey) {
            defaults.set(true, forKey: Self.migrationDoneKey)
        }
    }

    private func readOperations(at url: URL, label: String) -> [QueuedOperation] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let data = try? Data(contentsOf: url) else {
            Self.logger.error("could not read \(label, privacy: .public) file")
            return []
        }
        if let ops = try? decoder.decode([QueuedOperation].self, from: data) { return ops }

        // Corrupt: keep the original aside (never delete), salvage what we can.
        Self.logger.error("\(label, privacy: .public) file is corrupt; moving aside")
        let stamp = Int(now().timeIntervalSince1970)
        var aside = directory.appendingPathComponent("\(label).corrupt-\(stamp).json")
        if FileManager.default.fileExists(atPath: aside.path) {
            aside = directory.appendingPathComponent("\(label).corrupt-\(stamp)-\(UUID().uuidString.prefix(6)).json")
        }
        do {
            try FileManager.default.moveItem(at: url, to: aside)
        } catch {
            Self.logger.error("could not move corrupt \(label, privacy: .public) file aside")
        }
        let (recovered, _) = Self.decodeLossy(data)
        Self.logger.info("recovered \(recovered.count) operations from corrupt \(label, privacy: .public) file")
        if !recovered.isEmpty, let out = try? encoder.encode(recovered) {
            try? out.write(to: url, options: .atomic)
        }
        return recovered
    }

    /// Decode element by element so one bad entry doesn't lose the rest.
    static func decodeLossy(_ data: Data) -> ([QueuedOperation], Int) {
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return ([], 0) }
        let decoder = JSONDecoder()
        var ops: [QueuedOperation] = []
        var bad = 0
        for element in array {
            guard JSONSerialization.isValidJSONObject(element),
                  let elementData = try? JSONSerialization.data(withJSONObject: element),
                  let op = try? decoder.decode(QueuedOperation.self, from: elementData) else {
                bad += 1
                continue
            }
            ops.append(op)
        }
        return (ops, bad)
    }

    private func savePendingChanges() {
        guard unsavedOutcomes > 0 else { return }
        saveQueue()
    }

    private func saveQueue() {
        unsavedOutcomes = 0
        write(queue, to: queueURL, label: "queue")
    }

    private func saveFailed() {
        write(failed, to: failedURL, label: "failed")
    }

    private func write(_ ops: [QueuedOperation], to url: URL, label: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(ops)
            try data.write(to: url, options: .atomic)
        } catch {
            Self.logger.error("failed to persist \(label, privacy: .public) (\(ops.count) ops)")
        }
    }
}

// MARK: - Pending change index

/// The set of records that have an unuploaded operation, for restore's "local pending changes win".
struct PendingChangeIndex {
    /// Workouts with a header operation, or an operation on their exercise list.
    var workouts = Set<UUID>()
    /// Workouts with an operation on the workout row itself (insert, update or delete).
    var headerWorkouts = Set<UUID>()
    /// Exercises with a pending insert (so a child set's parent is on its way).
    var insertedExercises = Set<UUID>()
    var exercises = Set<UUID>()
    var sets = Set<UUID>()
    /// Exercises that have an unuploaded set operation.
    var setExerciseIds = Set<UUID>()
    var profile = false
    var contextTypes = Set<String>()
    /// Workout types whose AI summaries have an unuploaded delete (restore must not bring them back).
    var deletedContextTypes = Set<String>()
    var monthPlans = Set<UUID>()
    var plannedSessions = Set<UUID>()
    var restDayIds = Set<UUID>()
    /// `yyyy-MM-dd` of rest days with an unuploaded add or remove.
    var restDayDays = Set<String>()
    /// Tombstones queued here but not yet uploaded.
    var tombstones: [TombstoneEntity: Set<UUID>] = [:]

    /// A workout is dirty when any operation touches it, its exercises or their sets.
    func isWorkoutDirty(workoutId: UUID, exerciseIds: Set<UUID>, setIds: Set<UUID>) -> Bool {
        workouts.contains(workoutId)
            || !exerciseIds.isDisjoint(with: exercises)
            || !exerciseIds.isDisjoint(with: setExerciseIds)
            || !setIds.isDisjoint(with: sets)
    }

    func hasPendingTombstone(_ entity: TombstoneEntity, _ id: UUID) -> Bool {
        tombstones[entity]?.contains(id) ?? false
    }

    fileprivate mutating func absorb(_ op: QueuedOperation) {
        let decoder = JSONDecoder()
        switch op.type {
        case .insertWorkout, .updateWorkout, .deleteWorkout:
            if let model = try? decoder.decode(Workout.self, from: op.payload) {
                workouts.insert(model.id)
                headerWorkouts.insert(model.id)
            }
        case .insertExercises:
            if let models = try? decoder.decode([Exercise].self, from: op.payload) {
                for model in models {
                    exercises.insert(model.id)
                    insertedExercises.insert(model.id)
                    workouts.insert(model.workoutId)
                }
            }
        case .deleteExercise:
            if let model = try? decoder.decode(DeleteExercisePayload.self, from: op.payload) { exercises.insert(model.exerciseId) }
        case .deleteExercises:
            if let model = try? decoder.decode(DeleteExercisesPayload.self, from: op.payload) { workouts.insert(model.workoutId) }
        case .renameExercises:
            if let model = try? decoder.decode(RenameExercisesPayload.self, from: op.payload) { model.ids.forEach { exercises.insert($0) } }
        case .insertSet, .deleteSet:
            if let model = try? decoder.decode(WorkoutSet.self, from: op.payload) {
                sets.insert(model.id)
                setExerciseIds.insert(model.exerciseId)
            }
        case .upsertProfile:
            profile = true
        case .upsertContextSummary:
            if let model = try? decoder.decode(AIContextSummary.self, from: op.payload) { contextTypes.insert(model.workoutType) }
        case .deleteContextSummaries:
            if let model = try? decoder.decode(DeleteContextSummariesPayload.self, from: op.payload) {
                deletedContextTypes.formUnion(model.workoutTypes)
            }
        case .insertMonthPlan:
            if let model = try? decoder.decode(MonthPlan.self, from: op.payload) { monthPlans.insert(model.id) }
        case .deleteMonthPlan:
            if let model = try? decoder.decode(DeleteMonthPlanPayload.self, from: op.payload) { monthPlans.insert(model.planId) }
        case .insertPlannedSessions:
            if let models = try? decoder.decode([PlannedSession].self, from: op.payload) {
                models.forEach { plannedSessions.insert($0.id) }
            }
        case .updatePlannedSession:
            if let model = try? decoder.decode(PlannedSession.self, from: op.payload) { plannedSessions.insert(model.id) }
        case .upsertRestDay:
            if let model = try? decoder.decode(RestDay.self, from: op.payload) {
                restDayIds.insert(model.id)
                restDayDays.insert(RestDay.dayString(model.date))
            }
        case .deleteRestDay:
            if let model = try? decoder.decode(DeleteRestDayPayload.self, from: op.payload) {
                restDayIds.insert(model.id)
                restDayDays.insert(RestDay.dayString(model.date))
            }
        case .insertTombstone:
            if let model = try? decoder.decode(TombstonePayload.self, from: op.payload) {
                tombstones[model.entity, default: []].formUnion(model.recordIds)
            }
        case .insertPersonalRecord, .deletePersonalRecords:
            break   // the cloud PR log is never restored
        }
    }
}
