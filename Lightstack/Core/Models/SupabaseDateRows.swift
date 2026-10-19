import Foundation

// Rows sent to Supabase for tables with DATE columns. A DATE is the device-local calendar day
// (`yyyy-MM-dd`), never a full timestamp: Postgres would keep the UTC day of a timestamp and an
// evening workout west of UTC would land on the next day. The queue and Core Data keep their own
// encodings; these are used only for the cloud write.

struct SupabasePersonalRecord: Encodable {
    let id: UUID
    let userId: UUID
    let exerciseName: String
    let weightLbs: Double
    let reps: Int
    let dateAchieved: String
    let workoutId: UUID?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case exerciseName = "exercise_name"
        case weightLbs = "weight_lbs"
        case reps
        case dateAchieved = "date_achieved"
        case workoutId = "workout_id"
        case createdAt = "created_at"
    }
}

struct SupabaseMonthPlan: Encodable {
    let id: UUID
    let userId: UUID
    let title: String?
    let targetGoal: String?
    let startDate: String
    let endDate: String
    let aiOverview: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case targetGoal = "target_goal"
        case startDate = "start_date"
        case endDate = "end_date"
        case aiOverview = "ai_overview"
        case createdAt = "created_at"
    }
}

struct SupabasePlannedSession: Encodable {
    let id: UUID
    let monthPlanId: UUID
    let userId: UUID
    let plannedDate: String
    let workoutType: String
    let focusNote: String?
    let isRestDay: Bool
    let completed: Bool
    let workoutId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case monthPlanId = "month_plan_id"
        case userId = "user_id"
        case plannedDate = "planned_date"
        case workoutType = "workout_type"
        case focusNote = "focus_note"
        case isRestDay = "is_rest_day"
        case completed
        case workoutId = "workout_id"
    }
}

extension PersonalRecord {
    func toSupabase() -> SupabasePersonalRecord {
        SupabasePersonalRecord(id: id, userId: userId, exerciseName: exerciseName, weightLbs: weightLbs, reps: reps,
                               dateAchieved: RemoteDate.dayString(dateAchieved), workoutId: workoutId, createdAt: createdAt)
    }
}

extension MonthPlan {
    func toSupabase() -> SupabaseMonthPlan {
        SupabaseMonthPlan(id: id, userId: userId, title: title, targetGoal: targetGoal,
                          startDate: RemoteDate.dayString(startDate), endDate: RemoteDate.dayString(endDate),
                          aiOverview: aiOverview, createdAt: createdAt)
    }
}

extension PlannedSession {
    func toSupabase() -> SupabasePlannedSession {
        SupabasePlannedSession(id: id, monthPlanId: monthPlanId, userId: userId,
                               plannedDate: RemoteDate.dayString(plannedDate), workoutType: workoutType,
                               focusNote: focusNote, isRestDay: isRestDay, completed: completed, workoutId: workoutId)
    }
}
