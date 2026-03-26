import Foundation

/// Local representation of the month_plans table.
struct MonthPlan {
    let id: UUID
    let userId: UUID
    var title: String?
    var targetGoal: String?
    var startDate: Date
    var endDate: Date
    var aiOverview: String?
    var createdAt: Date

    // TODO: Phase 2 — Add Core Data / Supabase mapping methods
}
