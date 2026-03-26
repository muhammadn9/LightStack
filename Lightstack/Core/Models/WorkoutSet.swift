import Foundation

/// Local representation of the sets table.
/// Named WorkoutSet to avoid collision with Swift's Set type.
struct WorkoutSet {
    let id: UUID
    let exerciseId: UUID
    var localId: String?
    var setNumber: Int
    var weightLbs: Double
    var reps: Int
    var rir: Int
    var userFeedback: String?
    var isPR: Bool
    var syncStatus: SyncStatus
    var recordedAt: Date

    // TODO: Phase 0 — Add Core Data / Supabase mapping methods
}
