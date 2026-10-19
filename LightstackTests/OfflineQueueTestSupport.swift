import Foundation
@testable import Lightstack
import Supabase

/// Mutable box so tests can change the "signed-in user" or the clock mid-test.
final class TestBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}

/// Scriptable fake for the queue's remote writes.
final class FakeRemote: RemoteWriting, RemoteReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    private var _gateArmed = false
    private var _suspended: CheckedContinuation<Void, Never>?

    /// Return an error to fail a call. Args: op type, 0-based index of this call overall.
    var script: (@Sendable (QueuedOperationType, Int) -> Error?)?
    /// Runs on every call before the script (e.g. to switch the signed-in user).
    var onCall: (@Sendable (Int) -> Void)?
    /// Like the exercises/sets RLS policies: a child whose parent row isn't in the "cloud" is refused with 42501.
    var enforceParentRLS = false

    var calls: [String] { lock.lock(); defer { lock.unlock() }; return _calls }
    var isSuspended: Bool { lock.lock(); defer { lock.unlock() }; return _suspended != nil }

    /// The next call suspends until `release()`.
    func armSuspension() { lock.lock(); _gateArmed = true; lock.unlock() }

    func release() {
        lock.lock()
        let c = _suspended
        _suspended = nil
        lock.unlock()
        c?.resume()
    }

    private func record(_ type: QueuedOperationType, _ label: String) async throws {
        lock.lock()
        let index = _calls.count
        _calls.append("\(type.rawValue):\(label)")
        let shouldSuspend = _gateArmed
        _gateArmed = false
        lock.unlock()

        onCall?(index)
        if shouldSuspend {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                lock.lock(); _suspended = c; lock.unlock()
            }
        }
        if let error = script?(type, index) { throw error }
    }

    // MARK: - Simulated server state (upsert semantics: one row per id)

    private var _workouts: [UUID: Workout] = [:]
    private var _exercises: [UUID: Exercise] = [:]
    private var _sets: [UUID: WorkoutSet] = [:]
    private var _personalRecords: [UUID: PersonalRecord] = [:]
    private var _monthPlans: [UUID: MonthPlan] = [:]
    private var _plannedSessions: [UUID: PlannedSession] = [:]
    private var _restDays: [UUID: RestDay] = [:]
    private var _tombstones: [String] = []
    private var _profiles: [UUID: UserProfile] = [:]
    private var _summaries: [String: AIContextSummary] = [:]
    private var _readLog: [String] = []
    /// Fails a read. Args: read name ("fetchProfile", "fetchWorkoutHistoryPage", ...), 0-based count of that read so far.
    var readScript: (@Sendable (String, Int) -> Error?)?
    /// Runs before every read (e.g. to switch the signed-in user). Args: read name, count of that read so far.
    var onRead: (@Sendable (String, Int) -> Void)?
    private var _renames: [(ids: [UUID], name: String)] = []

    var workouts: [UUID: Workout] { locked { _workouts } }
    var exercises: [UUID: Exercise] { locked { _exercises } }
    var sets: [UUID: WorkoutSet] { locked { _sets } }
    var personalRecords: [UUID: PersonalRecord] { locked { _personalRecords } }
    var monthPlans: [UUID: MonthPlan] { locked { _monthPlans } }
    var plannedSessions: [UUID: PlannedSession] { locked { _plannedSessions } }
    var restDays: [UUID: RestDay] { locked { _restDays } }
    /// "entity:recordId" for every tombstone written.
    var tombstones: [String] { locked { _tombstones } }
    var renames: [(ids: [UUID], name: String)] { locked { _renames } }

    private func locked<R>(_ body: () -> R) -> R { lock.lock(); defer { lock.unlock() }; return body() }

    func insertWorkout(_ workout: Workout) async throws {
        try await record(.insertWorkout, workout.workoutType)
        locked { _workouts[workout.id] = workout }
    }
    func updateWorkout(_ workout: Workout) async throws {
        try await record(.updateWorkout, workout.workoutType)
        locked { if _workouts[workout.id] != nil { _workouts[workout.id] = workout } }
    }
    func deleteWorkout(workoutId: UUID) async throws {
        try await record(.deleteWorkout, "")
        locked {
            _workouts[workoutId] = nil
            let exIds = _exercises.values.filter { $0.workoutId == workoutId }.map(\.id)
            exIds.forEach { _exercises[$0] = nil }
            _sets = _sets.filter { !exIds.contains($0.value.exerciseId) }
        }
    }
    func deleteSet(setId: UUID) async throws {
        try await record(.deleteSet, "")
        locked { _sets[setId] = nil }
    }
    func deleteExercise(id: UUID) async throws {
        try await record(.deleteExercise, "")
        locked {
            _exercises[id] = nil
            _sets = _sets.filter { $0.value.exerciseId != id }
        }
    }
    func deleteExercises(workoutId: UUID) async throws {
        try await record(.deleteExercises, "")
        locked {
            let exIds = _exercises.values.filter { $0.workoutId == workoutId }.map(\.id)
            exIds.forEach { _exercises[$0] = nil }
            _sets = _sets.filter { !exIds.contains($0.value.exerciseId) }
        }
    }
    func insertExercises(_ exercises: [Exercise]) async throws {
        try await record(.insertExercises, exercises.first?.name ?? "")
        if enforceParentRLS, locked({ exercises.contains { _workouts[$0.workoutId] == nil } }) {
            throw QueueTestError.postgres("42501")
        }
        locked { exercises.forEach { _exercises[$0.id] = $0 } }
    }
    func insertSet(_ workoutSet: WorkoutSet) async throws {
        try await record(.insertSet, "")
        if enforceParentRLS, locked({ _exercises[workoutSet.exerciseId] == nil }) {
            throw QueueTestError.postgres("42501")
        }
        locked { _sets[workoutSet.id] = workoutSet }
    }
    func updateExerciseNames(ids: [UUID], name: String) async throws {
        try await record(.renameExercises, name)
        locked { _renames.append((ids, name)) }
    }
    func upsertProfile(_ profile: UserProfile) async throws {
        try await record(.upsertProfile, "")
        locked { _profiles[profile.userId] = profile }
    }
    func insertPersonalRecord(_ record: PersonalRecord) async throws {
        try await self.record(.insertPersonalRecord, "")
        locked { _personalRecords[record.id] = record }
    }
    func upsertContextSummary(_ summary: AIContextSummary) async throws {
        try await record(.upsertContextSummary, "")
        locked { _summaries["\(summary.userId)|\(summary.workoutType)"] = summary }
    }
    func insertMonthPlan(_ plan: MonthPlan) async throws {
        try await record(.insertMonthPlan, "")
        locked { _monthPlans[plan.id] = plan }
    }
    func insertPlannedSessions(_ sessions: [PlannedSession]) async throws {
        try await record(.insertPlannedSessions, "")
        locked { sessions.forEach { _plannedSessions[$0.id] = $0 } }
    }
    func updatePlannedSession(_ session: PlannedSession) async throws {
        try await record(.updatePlannedSession, "")
        locked { _plannedSessions[session.id] = session }
    }
    func deleteMonthPlan(planId: UUID) async throws {
        try await record(.deleteMonthPlan, "")
        locked {
            _monthPlans[planId] = nil
            _plannedSessions = _plannedSessions.filter { $0.value.monthPlanId != planId }
        }
    }
    func upsertRestDay(_ restDay: RestDay) async throws {
        try await record(.upsertRestDay, "")
        locked { _restDays[restDay.id] = restDay }
    }
    func deleteRestDay(userId: UUID, date: Date) async throws {
        try await record(.deleteRestDay, "")
        let day = RestDay.dayString(date)
        locked { _restDays = _restDays.filter { !($0.value.userId == userId && RestDay.dayString($0.value.date) == day) } }
    }
    func insertTombstones(userId: UUID, entity: String, recordIds: [UUID], deletedAt: Date) async throws {
        try await record(.insertTombstone, entity)
        locked {
            for id in recordIds where !_tombstones.contains("\(entity):\(id.uuidString)") {
                _tombstones.append("\(entity):\(id.uuidString)")
            }
        }
    }
}

// MARK: - Reads (restore)

extension FakeRemote {
    /// Names of every read made so far, in order ("fetchWorkoutHistoryPage", ...).
    var readLog: [String] { lock.lock(); defer { lock.unlock() }; return _readLog }

    private func read(_ name: String) async throws {
        lock.lock()
        let count = _readLog.filter { $0 == name }.count
        _readLog.append(name)
        lock.unlock()
        onRead?(name, count)
        if let error = readScript?(name, count) { throw error }
    }

    func seedProfile(_ profile: UserProfile) { lock.lock(); _profiles[profile.userId] = profile; lock.unlock() }
    func seedWorkout(_ workout: Workout, exercises: [(Exercise, [WorkoutSet])] = []) {
        lock.lock()
        _workouts[workout.id] = workout
        for (exercise, sets) in exercises {
            _exercises[exercise.id] = exercise
            sets.forEach { _sets[$0.id] = $0 }
        }
        lock.unlock()
    }
    func seedRestDay(_ day: RestDay) { lock.lock(); _restDays[day.id] = day; lock.unlock() }
    func seedTombstone(_ entity: TombstoneEntity, _ id: UUID) {
        lock.lock(); _tombstones.append("\(entity.rawValue):\(id.uuidString)"); lock.unlock()
    }
    func seedPlan(_ plan: MonthPlan, sessions: [PlannedSession]) {
        lock.lock()
        _monthPlans[plan.id] = plan
        sessions.forEach { _plannedSessions[$0.id] = $0 }
        lock.unlock()
    }
    func seedSummary(_ summary: AIContextSummary) {
        lock.lock(); _summaries["\(summary.userId)|\(summary.workoutType)"] = summary; lock.unlock()
    }

    func fetchProfile(userId: UUID) async throws -> UserProfile? {
        try await read("fetchProfile")
        lock.lock(); defer { lock.unlock() }
        return _profiles[userId]
    }

    func fetchWorkoutHistoryPage(userId: UUID, offset: Int, limit: Int) async throws -> [RemoteWorkoutRecord] {
        try await read("fetchWorkoutHistoryPage")
        lock.lock(); defer { lock.unlock() }
        let ordered = _workouts.values.filter { $0.userId == userId }
            .sorted { ($0.date, $0.id.uuidString) > ($1.date, $1.id.uuidString) }
        return ordered.dropFirst(offset).prefix(limit).map { workout in
            let exercises = _exercises.values.filter { $0.workoutId == workout.id }.map { exercise in
                (exercise, _sets.values.filter { $0.exerciseId == exercise.id }.sorted { $0.setNumber < $1.setNumber })
            }
            return RemoteWorkoutRecord(workout: workout, exercises: exercises)
        }
    }

    func fetchContextSummaries(userId: UUID) async throws -> [AIContextSummary] {
        try await read("fetchContextSummaries")
        lock.lock(); defer { lock.unlock() }
        return _summaries.values.filter { $0.userId == userId }
    }

    func fetchActiveMonthPlan(userId: UUID) async throws -> MonthPlan? {
        try await read("fetchActiveMonthPlan")
        lock.lock(); defer { lock.unlock() }
        return _monthPlans.values.filter { $0.userId == userId && $0.endDate >= Calendar.current.startOfDay(for: Date()) }
            .max { $0.createdAt < $1.createdAt }
    }

    func fetchPlannedSessions(monthPlanId: UUID) async throws -> [PlannedSession] {
        try await read("fetchPlannedSessions")
        lock.lock(); defer { lock.unlock() }
        return _plannedSessions.values.filter { $0.monthPlanId == monthPlanId }
    }

    func fetchRestDays(userId: UUID) async throws -> [RestDay] {
        try await read("fetchRestDays")
        lock.lock(); defer { lock.unlock() }
        return _restDays.values.filter { $0.userId == userId }
    }

    func fetchTombstones(userId: UUID) async throws -> [RemoteTombstone] {
        try await read("fetchTombstones")
        lock.lock(); defer { lock.unlock() }
        return _tombstones.compactMap { text in
            let parts = text.split(separator: ":")
            guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { return nil }
            return RemoteTombstone(entity: String(parts[0]), recordId: id)
        }
    }
}

enum QueueTestError {
    static let offline: Error = URLError(.notConnectedToInternet)
    static func postgres(_ code: String) -> Error { PostgrestError(code: code, message: "test error") }
}

func makeTempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("oq-test-\(UUID().uuidString)", isDirectory: true)
}

func makeTestWorkout(_ label: String, userId: UUID = UUID()) -> Workout {
    Workout.create(userId: userId, workoutType: label, energyLevel: nil, timeAvailableMinutes: nil)
}

/// A local store plus an outbox over a fake remote, wired the way the app does it
/// (in-memory Core Data, temp queue folder, no automatic uploads).
struct OutboxTestStack {
    let storage: LocalStorageService
    let queue: OfflineQueueManager
    let remote: FakeRemote
    let userId: UUID

    init(autoFlush: Bool = false, userId: UUID = UUID(), remote: FakeRemote = FakeRemote(), resolveDependencies: Bool = false) {
        self.storage = LocalStorageService(inMemory: true)
        self.remote = remote
        self.userId = userId
        self.queue = OfflineQueueManager(
            remote: remote,
            directory: makeTempDirectory(),
            ownerProvider: { userId },
            defaults: UserDefaults(suiteName: "oq-stack-\(UUID().uuidString)") ?? .standard,
            autoFlush: autoFlush,
            localLookup: resolveDependencies ? StorageParentLookup(storage: storage) : nil
        )
    }

    /// Wait for all queued-up `submit` calls, then upload everything (like a flush on reconnect).
    func flushAll() async {
        await queue.waitForSubmissions()
        await queue.flush()
    }
}

enum SupabaseServiceFactory {
    /// A service pointed at a host that never resolves; for repositories that only read through it.
    static func unreachable() -> SupabaseService {
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://example.invalid") ?? URL(fileURLWithPath: "/"),
            supabaseKey: "test"
        )
        return SupabaseService(client: client)
    }
}
