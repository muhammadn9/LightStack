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
final class FakeRemote: RemoteWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    private var _gateArmed = false
    private var _suspended: CheckedContinuation<Void, Never>?

    /// Return an error to fail a call. Args: op type, 0-based index of this call overall.
    var script: (@Sendable (QueuedOperationType, Int) -> Error?)?
    /// Runs on every call before the script (e.g. to switch the signed-in user).
    var onCall: (@Sendable (Int) -> Void)?

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
        locked { exercises.forEach { _exercises[$0.id] = $0 } }
    }
    func insertSet(_ workoutSet: WorkoutSet) async throws {
        try await record(.insertSet, "")
        locked { _sets[workoutSet.id] = workoutSet }
    }
    func updateExerciseNames(ids: [UUID], name: String) async throws {
        try await record(.renameExercises, name)
        locked { _renames.append((ids, name)) }
    }
    func upsertProfile(_ profile: UserProfile) async throws { try await record(.upsertProfile, "") }
    func insertPersonalRecord(_ record: PersonalRecord) async throws {
        try await self.record(.insertPersonalRecord, "")
        locked { _personalRecords[record.id] = record }
    }
    func upsertContextSummary(_ summary: AIContextSummary) async throws { try await record(.upsertContextSummary, "") }
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

    init(autoFlush: Bool = false, userId: UUID = UUID(), remote: FakeRemote = FakeRemote()) {
        self.storage = LocalStorageService(inMemory: true)
        self.remote = remote
        self.userId = userId
        self.queue = OfflineQueueManager(
            remote: remote,
            directory: makeTempDirectory(),
            ownerProvider: { userId },
            defaults: UserDefaults(suiteName: "oq-stack-\(UUID().uuidString)") ?? .standard,
            autoFlush: autoFlush
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
