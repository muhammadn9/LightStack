import Foundation
import CoreData

/// Local representation of the month_plans table.
struct MonthPlan: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var title: String?
    var targetGoal: String?
    var startDate: Date
    var endDate: Date
    var aiOverview: String?
    var createdAt: Date

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

    // MARK: - Core Data Mapping

    init(from cdEntity: CDMonthPlan) {
        self.id = cdEntity.id ?? UUID()
        self.userId = cdEntity.userId ?? UUID()
        self.title = cdEntity.title
        self.targetGoal = cdEntity.targetGoal
        self.startDate = cdEntity.startDate ?? Date()
        self.endDate = cdEntity.endDate ?? Date()
        self.aiOverview = cdEntity.aiOverview
        self.createdAt = cdEntity.createdAt ?? Date()
    }

    func applyToCoreData(_ entity: CDMonthPlan) {
        entity.id = id
        entity.userId = userId
        entity.title = title
        entity.targetGoal = targetGoal
        entity.startDate = startDate
        entity.endDate = endDate
        entity.aiOverview = aiOverview
        entity.createdAt = createdAt
    }

    // MARK: - Factory

    static func create(
        userId: UUID,
        title: String?,
        targetGoal: String?,
        startDate: Date,
        endDate: Date,
        aiOverview: String?
    ) -> MonthPlan {
        MonthPlan(
            id: UUID(),
            userId: userId,
            title: title,
            targetGoal: targetGoal,
            startDate: startDate,
            endDate: endDate,
            aiOverview: aiOverview,
            createdAt: Date()
        )
    }

    // MARK: - Memberwise Init

    init(
        id: UUID, userId: UUID, title: String?, targetGoal: String?,
        startDate: Date, endDate: Date, aiOverview: String?, createdAt: Date
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.targetGoal = targetGoal
        self.startDate = startDate
        self.endDate = endDate
        self.aiOverview = aiOverview
        self.createdAt = createdAt
    }
}
