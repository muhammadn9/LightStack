import Foundation

/// Local representation of the profiles table.
/// Used as the data transfer object between Core Data and Supabase.
struct UserProfile {
    let id: UUID
    let userId: UUID
    var displayName: String?
    var age: Int?
    var heightInches: Double?
    var weightLbs: Double?
    var trainingAgeMonths: Int?
    var primaryGoals: [String]
    var splitDays: [String]
    var avoidExercises: [String]
    var equipment: [String: Bool]
    var notesToCoach: String?
    var createdAt: Date
    var updatedAt: Date

    // TODO: Phase 0 — Add Core Data / Supabase mapping methods
}
