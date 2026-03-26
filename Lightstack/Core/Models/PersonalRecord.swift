import Foundation

/// Local representation of the personal_records table.
struct PersonalRecord {
    let id: UUID
    let userId: UUID
    var exerciseName: String
    var weightLbs: Double
    var reps: Int
    var dateAchieved: Date
    var workoutId: UUID?
    var createdAt: Date

    // TODO: Phase 3 — Add Core Data / Supabase mapping methods
}
