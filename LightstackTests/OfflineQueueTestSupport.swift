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

    func insertWorkout(_ workout: Workout) async throws { try await record(.insertWorkout, workout.workoutType) }
    func updateWorkout(_ workout: Workout) async throws { try await record(.updateWorkout, workout.workoutType) }
    func deleteWorkout(workoutId: UUID) async throws { try await record(.deleteWorkout, "") }
    func deleteSet(setId: UUID) async throws { try await record(.deleteSet, "") }
    func deleteExercise(id: UUID) async throws { try await record(.deleteExercise, "") }
    func deleteExercises(workoutId: UUID) async throws { try await record(.deleteExercises, "") }
    func insertExercises(_ exercises: [Exercise]) async throws { try await record(.insertExercises, exercises.first?.name ?? "") }
    func insertSet(_ workoutSet: WorkoutSet) async throws { try await record(.insertSet, "") }
    func updateExerciseNames(ids: [UUID], name: String) async throws { try await record(.renameExercises, name) }
    func upsertProfile(_ profile: UserProfile) async throws { try await record(.upsertProfile, "") }
    func insertPersonalRecord(_ record: PersonalRecord) async throws { try await self.record(.insertPersonalRecord, "") }
    func upsertContextSummary(_ summary: AIContextSummary) async throws { try await record(.upsertContextSummary, "") }
    func insertMonthPlan(_ plan: MonthPlan) async throws { try await record(.insertMonthPlan, "") }
    func insertPlannedSessions(_ sessions: [PlannedSession]) async throws { try await record(.insertPlannedSessions, "") }
    func updatePlannedSession(_ session: PlannedSession) async throws { try await record(.updatePlannedSession, "") }
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
