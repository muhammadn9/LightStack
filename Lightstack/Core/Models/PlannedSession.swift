import Foundation
import CoreData

/// Local representation of the planned_sessions table.
struct PlannedSession: Codable, Identifiable {
    let id: UUID
    let monthPlanId: UUID
    let userId: UUID
    var plannedDate: Date
    var workoutType: String
    var focusNote: String?
    var isRestDay: Bool
    var completed: Bool
    var workoutId: UUID?

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

    // MARK: - Core Data Mapping

    init(from cdEntity: CDPlannedSession) {
        self.id = cdEntity.id ?? UUID()
        self.monthPlanId = cdEntity.monthPlan?.id ?? UUID()
        self.userId = cdEntity.userId ?? UUID()
        self.plannedDate = cdEntity.plannedDate ?? Date()
        self.workoutType = cdEntity.workoutType ?? ""
        self.focusNote = cdEntity.focusNote
        self.isRestDay = cdEntity.isRestDay
        self.completed = cdEntity.completed
        self.workoutId = cdEntity.workoutId
    }

    func applyToCoreData(_ entity: CDPlannedSession) {
        entity.id = id
        entity.userId = userId
        entity.plannedDate = plannedDate
        entity.workoutType = workoutType
        entity.focusNote = focusNote
        entity.isRestDay = isRestDay
        entity.completed = completed
        entity.workoutId = workoutId
    }

    // MARK: - Factory

    static func create(
        monthPlanId: UUID,
        userId: UUID,
        plannedDate: Date,
        workoutType: String,
        focusNote: String?,
        isRestDay: Bool
    ) -> PlannedSession {
        PlannedSession(
            id: UUID(),
            monthPlanId: monthPlanId,
            userId: userId,
            plannedDate: plannedDate,
            workoutType: workoutType,
            focusNote: focusNote,
            isRestDay: isRestDay,
            completed: false,
            workoutId: nil
        )
    }

    // MARK: - Memberwise Init

    init(
        id: UUID, monthPlanId: UUID, userId: UUID, plannedDate: Date,
        workoutType: String, focusNote: String?, isRestDay: Bool,
        completed: Bool, workoutId: UUID?
    ) {
        self.id = id
        self.monthPlanId = monthPlanId
        self.userId = userId
        self.plannedDate = plannedDate
        self.workoutType = workoutType
        self.focusNote = focusNote
        self.isRestDay = isRestDay
        self.completed = completed
        self.workoutId = workoutId
    }
}
