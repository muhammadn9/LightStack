import Foundation

// MARK: - Queue Operation Type

/// All write operations that can be deferred when offline.
enum QueuedOperationType: String, Codable {
    case insertWorkout
    case updateWorkout
    case insertExercises
    case insertSet
    case upsertProfile
    case insertPersonalRecord
    case upsertContextSummary
    case insertMonthPlan
    case insertPlannedSessions
    case updatePlannedSession
}

// MARK: - Queued Operation

/// A single write operation held in the offline queue.
/// Payload is JSON-encoded so it survives process termination.
struct QueuedOperation: Codable, Identifiable {
    let id: String
    let type: QueuedOperationType
    let payload: Data
    var attempts: Int
    let enqueuedAt: Date

    init(type: QueuedOperationType, payload: Data) {
        self.id = UUID().uuidString
        self.type = type
        self.payload = payload
        self.attempts = 0
        self.enqueuedAt = Date()
    }
}

// MARK: - OfflineQueueManager

/// Queues writes when the device is offline.
/// Declared as an actor so all queue read-modify-write operations are
/// serialized — preventing concurrent enqueues from racing and silently
/// dropping operations.
/// Uses local_id (device UUID) to prevent duplicate inserts on retry.
actor OfflineQueueManager {

    private let queueKey = "lightstack_offline_queue_v1"
    private let maxAttempts = 5
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let supabaseService: SupabaseService

    init(supabaseService: SupabaseService) {
        self.supabaseService = supabaseService
    }

    // MARK: - Public Interface

    var pendingCount: Int { loadQueue().count }

    /// Encode and append an operation to the persistent queue.
    func enqueue<T: Encodable>(_ type: QueuedOperationType, payload: T) {
        guard let data = try? encoder.encode(payload) else { return }
        var current = loadQueue()
        current.append(QueuedOperation(type: type, payload: data))
        saveQueue(current)
    }

    /// Remove all queued operations.
    /// Called on sign-out to prevent a future session from flushing
    /// stale operations under the wrong user's JWT.
    func clearQueue() {
        saveQueue([])
    }

    /// Flush all pending operations to Supabase in FK-dependency order.
    /// Unknown operation types are processed last rather than dropped.
    /// Failed operations are re-queued up to maxAttempts times.
    /// Data is always safe in Core Data regardless of queue state.
    func flush() async {
        let current = loadQueue()
        guard !current.isEmpty else { return }

        // Ordered by FK dependency: parents before children.
        // Any type NOT in this list is sorted to the end — never silently dropped.
        let order: [QueuedOperationType] = [
            .insertWorkout, .updateWorkout,
            .insertExercises, .insertSet,
            .upsertProfile, .insertPersonalRecord,
            .upsertContextSummary,
            .insertMonthPlan, .insertPlannedSessions, .updatePlannedSession
        ]
        let sorted = current.sorted { a, b in
            let ai = order.firstIndex(of: a.type) ?? order.count
            let bi = order.firstIndex(of: b.type) ?? order.count
            return ai < bi
        }

        var failed: [QueuedOperation] = []
        for var op in sorted {
            do {
                try await execute(op)
            } catch {
                op.attempts += 1
                if op.attempts < maxAttempts {
                    failed.append(op)
                }
                // Exceeded maxAttempts: data lives in Core Data — silently drop
            }
        }

        saveQueue(failed)
    }

    // MARK: - Execute

    private func execute(_ op: QueuedOperation) async throws {
        switch op.type {
        case .insertWorkout:
            let model = try decoder.decode(Workout.self, from: op.payload)
            try await supabaseService.insertWorkout(model)
        case .updateWorkout:
            let model = try decoder.decode(Workout.self, from: op.payload)
            try await supabaseService.updateWorkout(model)
        case .insertExercises:
            let models = try decoder.decode([Exercise].self, from: op.payload)
            try await supabaseService.insertExercises(models)
        case .insertSet:
            let model = try decoder.decode(WorkoutSet.self, from: op.payload)
            try await supabaseService.insertSet(model)
        case .upsertProfile:
            let model = try decoder.decode(UserProfile.self, from: op.payload)
            try await supabaseService.upsertProfile(model)
        case .insertPersonalRecord:
            let model = try decoder.decode(PersonalRecord.self, from: op.payload)
            try await supabaseService.insertPersonalRecord(model)
        case .upsertContextSummary:
            let model = try decoder.decode(AIContextSummary.self, from: op.payload)
            try await supabaseService.upsertContextSummary(model)
        case .insertMonthPlan:
            let model = try decoder.decode(MonthPlan.self, from: op.payload)
            try await supabaseService.insertMonthPlan(model)
        case .insertPlannedSessions:
            let models = try decoder.decode([PlannedSession].self, from: op.payload)
            try await supabaseService.insertPlannedSessions(models)
        case .updatePlannedSession:
            let model = try decoder.decode(PlannedSession.self, from: op.payload)
            try await supabaseService.updatePlannedSession(model)
        }
    }

    // MARK: - Persistence

    private func loadQueue() -> [QueuedOperation] {
        guard let data = UserDefaults.standard.data(forKey: queueKey),
              let ops = try? decoder.decode([QueuedOperation].self, from: data) else {
            return []
        }
        return ops
    }

    private func saveQueue(_ ops: [QueuedOperation]) {
        guard let data = try? encoder.encode(ops) else { return }
        UserDefaults.standard.set(data, forKey: queueKey)
    }
}
