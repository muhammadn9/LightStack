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
    case upsertContextSummary
    case insertMonthPlan
    case insertPlannedSessions
    case updatePlannedSession
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
    func upsertContextSummary(_ summary: AIContextSummary) async throws
    func insertMonthPlan(_ plan: MonthPlan) async throws
    func insertPlannedSessions(_ sessions: [PlannedSession]) async throws
    func updatePlannedSession(_ session: PlannedSession) async throws
}

extension SupabaseService: RemoteWriting, @unchecked Sendable {}

// MARK: - Queued Operation

/// A single write operation held in the offline queue.
/// Payload is JSON-encoded so it survives process termination.
struct QueuedOperation: Codable, Identifiable {
    let id: String
    let type: QueuedOperationType
    let payload: Data
    let enqueuedAt: Date
    /// User who made the change. nil only for legacy entries (adopted by the next signed-in user).
    var ownerUserId: UUID?
    var attempts: Int
    var lastErrorCode: String?
    var lastErrorMessage: String?
    var nextAttemptAt: Date?

    init(type: QueuedOperationType, payload: Data, ownerUserId: UUID? = nil, enqueuedAt: Date = Date()) {
        self.id = UUID().uuidString
        self.type = type
        self.payload = payload
        self.enqueuedAt = enqueuedAt
        self.ownerUserId = ownerUserId
        self.attempts = 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, payload, enqueuedAt, ownerUserId, attempts
        case lastErrorCode, lastErrorMessage, nextAttemptAt
    }

    /// Decodes legacy entries that lack the newer fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(QueuedOperationType.self, forKey: .type)
        payload = try c.decode(Data.self, forKey: .payload)
        enqueuedAt = try c.decodeIfPresent(Date.self, forKey: .enqueuedAt) ?? Date()
        ownerUserId = try c.decodeIfPresent(UUID.self, forKey: .ownerUserId)
        attempts = try c.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        lastErrorCode = try c.decodeIfPresent(String.self, forKey: .lastErrorCode)
        lastErrorMessage = try c.decodeIfPresent(String.self, forKey: .lastErrorMessage)
        nextAttemptAt = try c.decodeIfPresent(Date.self, forKey: .nextAttemptAt)
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
        defaults: UserDefaults = .standard
    ) {
        self.remote = remote
        self.directory = directory
        self.now = now
        self.ownerProvider = ownerProvider
        self.defaults = defaults
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

    /// Encode and append an operation to the persistent queue.
    func enqueue<T: Encodable>(_ type: QueuedOperationType, payload: T) async {
        let data: Data
        do {
            data = try encoder.encode(payload)
        } catch {
            Self.logger.error("enqueue failed to encode payload for \(type.rawValue, privacy: .public)")
            return
        }
        let owner = await ownerProvider()
        loadIfNeeded()
        queue.append(QueuedOperation(type: type, payload: data, ownerUserId: owner, enqueuedAt: now()))
        saveQueue()
    }

    /// Queue "delete all exercises of a workout" (part of a workout replace).
    /// Any still-queued inserts for that workout's exercises/sets, and earlier
    /// deleteExercises for it, are superseded by this replace and are dropped.
    /// Without this, flush() would re-insert the old exercises (inserts run after
    /// deleteExercises) alongside the new ones.
    func enqueueDeleteExercises(workoutId: UUID) async {
        let data: Data
        do {
            data = try encoder.encode(DeleteExercisesPayload(workoutId: workoutId))
        } catch {
            Self.logger.error("enqueueDeleteExercises failed to encode payload")
            return
        }
        let owner = await ownerProvider()
        loadIfNeeded()

        var staleExerciseIds = Set<UUID>()
        queue.removeAll { op in
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
            guard op.type == .insertSet,
                  let model = try? decoder.decode(WorkoutSet.self, from: op.payload) else { return false }
            return staleExerciseIds.contains(model.exerciseId)
        }
        queue.append(QueuedOperation(type: .deleteExercises, payload: data, ownerUserId: owner, enqueuedAt: now()))
        saveQueue()
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
        let eligible = queue.filter { op in
            op.ownerUserId == owner && (op.nextAttemptAt.map { $0 <= startNow } ?? true)
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
                    scheduleRetry(id: current.id, code: code, message: SyncErrorClassifier.errorMessage(for: error))
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
        let late = queue.contains { op in
            op.ownerUserId == owner && !seenIds.contains(op.id) && (op.nextAttemptAt.map { $0 <= checkNow } ?? true)
        }
        if late { needsAnotherPass = true }
        return true
    }

    // MARK: - State mutation (by id, never from a stale snapshot)

    private func removeFromQueue(id: String) {
        queue.removeAll { $0.id == id }
        unsavedOutcomes += 1
    }

    private func scheduleRetry(id: String, code: String, message: String) {
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[idx].attempts += 1
        queue[idx].lastErrorCode = code
        queue[idx].lastErrorMessage = message
        queue[idx].nextAttemptAt = now().addingTimeInterval(Self.backoff(attempts: queue[idx].attempts))
        unsavedOutcomes += 1
    }

    private func deadLetter(id: String, code: String, message: String) {
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }
        var op = queue.remove(at: idx)
        op.attempts += 1
        op.lastErrorCode = code
        op.lastErrorMessage = message
        op.nextAttemptAt = nil
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
    static func backoff(attempts: Int) -> TimeInterval {
        min(pow(2, Double(min(max(attempts, 0), 20))) * 5, 3600)
    }

    private static func belongs(_ op: QueuedOperation, to owner: UUID?) -> Bool {
        guard let owner else { return false }
        return op.ownerUserId == nil || op.ownerUserId == owner
    }

    // MARK: - Ordering

    /// Parents before children; deleteExercises before inserts; deletes last;
    /// stable (FIFO) within a kind. Unknown types sort to the end, never dropped.
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
            .insertMonthPlan, .insertPlannedSessions, .updatePlannedSession,
            .deleteWorkout, .deleteSet, .deleteExercise  // Delete operations should be last
        ]
        var rank: [QueuedOperationType: Int] = [:]
        for (i, t) in order.enumerated() { rank[t] = i }
        return ops.enumerated().sorted { a, b in
            let ai = rank[a.element.type] ?? order.count
            let bi = rank[b.element.type] ?? order.count
            return ai != bi ? ai < bi : a.offset < b.offset
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
