import Foundation
import CoreData

/// Local representation of the ai_context_summaries table.
/// Stores a rolling summary of recent workouts per workout type,
/// so the AI always has history without context overflow.
struct AIContextSummary: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var workoutType: String
    var summaryText: String
    var sessionsCovered: Int
    var lastUpdated: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case workoutType = "workout_type"
        case summaryText = "summary_text"
        case sessionsCovered = "sessions_covered"
        case lastUpdated = "last_updated"
    }

    // MARK: - Core Data Mapping

    init(from cdEntity: CDAIContextSummary) {
        self.id = cdEntity.id ?? UUID()
        self.userId = cdEntity.userId ?? UUID()
        self.workoutType = cdEntity.workoutType ?? ""
        self.summaryText = cdEntity.summaryText ?? ""
        self.sessionsCovered = Int(cdEntity.sessionsCovered)
        self.lastUpdated = cdEntity.lastUpdated ?? Date()
    }

    func applyToCoreData(_ entity: CDAIContextSummary) {
        entity.id = id
        entity.userId = userId
        entity.workoutType = workoutType
        entity.summaryText = summaryText
        entity.sessionsCovered = Int32(sessionsCovered)
        entity.lastUpdated = lastUpdated
    }

    // MARK: - Factory

    static func create(
        userId: UUID,
        workoutType: String,
        summaryText: String,
        sessionsCovered: Int
    ) -> AIContextSummary {
        AIContextSummary(
            id: UUID(),
            userId: userId,
            workoutType: workoutType,
            summaryText: summaryText,
            sessionsCovered: sessionsCovered,
            lastUpdated: Date()
        )
    }

    // MARK: - Memberwise Init

    init(
        id: UUID, userId: UUID, workoutType: String,
        summaryText: String, sessionsCovered: Int, lastUpdated: Date
    ) {
        self.id = id
        self.userId = userId
        self.workoutType = workoutType
        self.summaryText = summaryText
        self.sessionsCovered = sessionsCovered
        self.lastUpdated = lastUpdated
    }
}
