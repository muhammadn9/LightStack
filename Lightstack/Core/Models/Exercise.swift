import Foundation

/// Local representation of the exercises table.
struct Exercise {
    let id: UUID
    let workoutId: UUID
    var localId: String?
    var name: String
    var muscleGroup: String
    var orderIndex: Int
    var targetSets: Int?
    var targetReps: String?
    var targetRir: String?
    var restSeconds: Int?
    var coachNote: String?
    var syncStatus: SyncStatus

    // TODO: Phase 0 — Add Core Data / Supabase mapping methods
}
