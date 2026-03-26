import Foundation

/// Local representation of the planned_sessions table.
struct PlannedSession {
    let id: UUID
    let monthPlanId: UUID
    let userId: UUID
    var plannedDate: Date
    var workoutType: String
    var focusNote: String?
    var isRestDay: Bool
    var completed: Bool
    var workoutId: UUID?

    // TODO: Phase 2 — Add Core Data / Supabase mapping methods
}
