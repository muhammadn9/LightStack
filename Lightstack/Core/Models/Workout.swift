import Foundation

/// Local representation of the workouts table.
struct Workout {
    let id: UUID
    let userId: UUID
    var localId: String?
    var date: Date
    var workoutType: String
    var durationMinutes: Int?
    var energyLevel: Int?
    var timeAvailableMinutes: Int?
    var userNote: String?
    var aiProgressionNote: String?
    var plannedSessionId: UUID?
    var syncStatus: SyncStatus
    var createdAt: Date

    // TODO: Phase 0 — Add Core Data / Supabase mapping methods
}

/// Sync status for offline queue tracking.
enum SyncStatus: String {
    case pending
    case synced
}
