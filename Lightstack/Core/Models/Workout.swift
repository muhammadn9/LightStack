import Foundation
import CoreData

/// Local representation of the workouts table.
struct Workout: Codable, Identifiable {
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

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case localId = "local_id"
        case date
        case workoutType = "workout_type"
        case durationMinutes = "duration_minutes"
        case energyLevel = "energy_level"
        case timeAvailableMinutes = "time_available_minutes"
        case userNote = "user_note"
        case aiProgressionNote = "ai_progression_note"
        case plannedSessionId = "planned_session_id"
        case createdAt = "created_at"
    }

    // syncStatus is local-only — excluded from CodingKeys

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        userId = try c.decode(UUID.self, forKey: .userId)
        localId = try c.decodeIfPresent(String.self, forKey: .localId)
        date = try c.decode(Date.self, forKey: .date)
        workoutType = try c.decode(String.self, forKey: .workoutType)
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes)
        energyLevel = try c.decodeIfPresent(Int.self, forKey: .energyLevel)
        timeAvailableMinutes = try c.decodeIfPresent(Int.self, forKey: .timeAvailableMinutes)
        userNote = try c.decodeIfPresent(String.self, forKey: .userNote)
        aiProgressionNote = try c.decodeIfPresent(String.self, forKey: .aiProgressionNote)
        plannedSessionId = try c.decodeIfPresent(UUID.self, forKey: .plannedSessionId)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        syncStatus = .synced
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userId, forKey: .userId)
        try c.encodeIfPresent(localId, forKey: .localId)
        try c.encode(date, forKey: .date)
        try c.encode(workoutType, forKey: .workoutType)
        try c.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
        try c.encodeIfPresent(energyLevel, forKey: .energyLevel)
        try c.encodeIfPresent(timeAvailableMinutes, forKey: .timeAvailableMinutes)
        try c.encodeIfPresent(userNote, forKey: .userNote)
        try c.encodeIfPresent(aiProgressionNote, forKey: .aiProgressionNote)
        try c.encodeIfPresent(plannedSessionId, forKey: .plannedSessionId)
        try c.encode(createdAt, forKey: .createdAt)
    }

    /// Supabase-ready Codable wrapper (excludes syncStatus, maps synced column).
    func toSupabase() -> SupabaseWorkout {
        SupabaseWorkout(workout: self)
    }

    // MARK: - Core Data Mapping

    init(from cdEntity: CDWorkout) {
        self.id = cdEntity.id ?? UUID()
        self.userId = cdEntity.userId ?? UUID()
        self.localId = cdEntity.localId
        self.date = cdEntity.date ?? Date()
        self.workoutType = cdEntity.workoutType ?? ""
        self.durationMinutes = cdEntity.durationMinutes == 0 ? nil : Int(cdEntity.durationMinutes)
        self.energyLevel = cdEntity.energyLevel == 0 ? nil : Int(cdEntity.energyLevel)
        self.timeAvailableMinutes = cdEntity.timeAvailableMinutes == 0 ? nil : Int(cdEntity.timeAvailableMinutes)
        self.userNote = cdEntity.userNote
        self.aiProgressionNote = cdEntity.aiProgressionNote
        self.plannedSessionId = cdEntity.plannedSessionId
        self.syncStatus = SyncStatus(rawValue: cdEntity.syncStatus ?? "pending") ?? .pending
        self.createdAt = cdEntity.createdAt ?? Date()
    }

    func applyToCoreData(_ entity: CDWorkout) {
        entity.id = id
        entity.userId = userId
        entity.localId = localId
        entity.date = date
        entity.workoutType = workoutType
        entity.durationMinutes = Int32(durationMinutes ?? 0)
        entity.energyLevel = Int32(energyLevel ?? 0)
        entity.timeAvailableMinutes = Int32(timeAvailableMinutes ?? 0)
        entity.userNote = userNote
        entity.aiProgressionNote = aiProgressionNote
        entity.plannedSessionId = plannedSessionId
        entity.syncStatus = syncStatus.rawValue
        entity.createdAt = createdAt
    }

    // MARK: - Factory

    static func create(
        userId: UUID,
        workoutType: String,
        energyLevel: Int?,
        timeAvailableMinutes: Int?
    ) -> Workout {
        let localId = UUID().uuidString
        return Workout(
            id: UUID(),
            userId: userId,
            localId: localId,
            date: Date(),
            workoutType: workoutType,
            durationMinutes: nil,
            energyLevel: energyLevel,
            timeAvailableMinutes: timeAvailableMinutes,
            userNote: nil,
            aiProgressionNote: nil,
            plannedSessionId: nil,
            syncStatus: .pending,
            createdAt: Date()
        )
    }

    // MARK: - Memberwise Init

    init(
        id: UUID, userId: UUID, localId: String?, date: Date, workoutType: String,
        durationMinutes: Int?, energyLevel: Int?, timeAvailableMinutes: Int?,
        userNote: String?, aiProgressionNote: String?, plannedSessionId: UUID?,
        syncStatus: SyncStatus, createdAt: Date
    ) {
        self.id = id
        self.userId = userId
        self.localId = localId
        self.date = date
        self.workoutType = workoutType
        self.durationMinutes = durationMinutes
        self.energyLevel = energyLevel
        self.timeAvailableMinutes = timeAvailableMinutes
        self.userNote = userNote
        self.aiProgressionNote = aiProgressionNote
        self.plannedSessionId = plannedSessionId
        self.syncStatus = syncStatus
        self.createdAt = createdAt
    }
}

/// Sync status for offline queue tracking.
enum SyncStatus: String, Codable {
    case pending
    case synced
}

/// Supabase-specific Codable wrapper — includes `synced` column instead of `syncStatus`.
struct SupabaseWorkout: Encodable {
    let id: UUID
    let userId: UUID
    let localId: String?
    let date: Date
    let workoutType: String
    let durationMinutes: Int?
    let energyLevel: Int?
    let timeAvailableMinutes: Int?
    let userNote: String?
    let aiProgressionNote: String?
    let plannedSessionId: UUID?
    let synced: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case localId = "local_id"
        case date
        case workoutType = "workout_type"
        case durationMinutes = "duration_minutes"
        case energyLevel = "energy_level"
        case timeAvailableMinutes = "time_available_minutes"
        case userNote = "user_note"
        case aiProgressionNote = "ai_progression_note"
        case plannedSessionId = "planned_session_id"
        case synced
        case createdAt = "created_at"
    }

    init(workout: Workout) {
        self.id = workout.id
        self.userId = workout.userId
        self.localId = workout.localId
        self.date = workout.date
        self.workoutType = workout.workoutType
        self.durationMinutes = workout.durationMinutes
        self.energyLevel = workout.energyLevel
        self.timeAvailableMinutes = workout.timeAvailableMinutes
        self.userNote = workout.userNote
        self.aiProgressionNote = workout.aiProgressionNote
        self.plannedSessionId = workout.plannedSessionId
        self.synced = true
        self.createdAt = workout.createdAt
    }
}
