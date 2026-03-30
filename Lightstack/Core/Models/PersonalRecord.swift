import Foundation
import CoreData

/// Local representation of the personal_records table.
struct PersonalRecord: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var exerciseName: String
    var weightLbs: Double
    var reps: Int
    var dateAchieved: Date
    var workoutId: UUID?
    var createdAt: Date
    var syncStatus: SyncStatus

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

    // syncStatus is local-only — excluded from CodingKeys

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        userId = try c.decode(UUID.self, forKey: .userId)
        exerciseName = try c.decode(String.self, forKey: .exerciseName)
        weightLbs = try c.decode(Double.self, forKey: .weightLbs)
        reps = try c.decode(Int.self, forKey: .reps)
        dateAchieved = try c.decode(Date.self, forKey: .dateAchieved)
        workoutId = try c.decodeIfPresent(UUID.self, forKey: .workoutId)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        syncStatus = .synced
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userId, forKey: .userId)
        try c.encode(exerciseName, forKey: .exerciseName)
        try c.encode(weightLbs, forKey: .weightLbs)
        try c.encode(reps, forKey: .reps)
        try c.encode(dateAchieved, forKey: .dateAchieved)
        try c.encodeIfPresent(workoutId, forKey: .workoutId)
        try c.encode(createdAt, forKey: .createdAt)
    }

    // MARK: - Core Data Mapping

    init(from cdEntity: CDPersonalRecord) {
        self.id = cdEntity.id ?? UUID()
        self.userId = cdEntity.userId ?? UUID()
        self.exerciseName = cdEntity.exerciseName ?? ""
        self.weightLbs = cdEntity.weightLbs
        self.reps = Int(cdEntity.reps)
        self.dateAchieved = cdEntity.dateAchieved ?? Date()
        self.workoutId = cdEntity.workoutId
        self.createdAt = cdEntity.createdAt ?? Date()
        // CDPersonalRecord doesn't have syncStatus - always default to synced when reading from Core Data
        self.syncStatus = .synced
    }

    func applyToCoreData(_ entity: CDPersonalRecord) {
        entity.id = id
        entity.userId = userId
        entity.exerciseName = exerciseName
        entity.weightLbs = weightLbs
        entity.reps = Int32(reps)
        entity.dateAchieved = dateAchieved
        entity.workoutId = workoutId
        entity.createdAt = createdAt
        // CDPersonalRecord doesn't have syncStatus - not persisted to Core Data
    }

    // MARK: - Factory

    static func create(
        userId: UUID,
        exerciseName: String,
        weightLbs: Double,
        reps: Int,
        workoutId: UUID?
    ) -> PersonalRecord {
        PersonalRecord(
            id: UUID(),
            userId: userId,
            exerciseName: exerciseName,
            weightLbs: weightLbs,
            reps: reps,
            dateAchieved: Date(),
            workoutId: workoutId,
            createdAt: Date(),
            syncStatus: .pending
        )
    }

    // MARK: - Computed Properties

    /// Estimated 1-rep max using the Epley formula: weight × (1 + reps/30).
    var estimatedOneRepMax: Double {
        weightLbs * (1 + Double(reps) / 30)
    }

    // MARK: - Memberwise Init

    init(
        id: UUID,
        userId: UUID,
        exerciseName: String,
        weightLbs: Double,
        reps: Int,
        dateAchieved: Date,
        workoutId: UUID?,
        createdAt: Date,
        syncStatus: SyncStatus
    ) {
        self.id = id
        self.userId = userId
        self.exerciseName = exerciseName
        self.weightLbs = weightLbs
        self.reps = reps
        self.dateAchieved = dateAchieved
        self.workoutId = workoutId
        self.createdAt = createdAt
        self.syncStatus = syncStatus
    }
}
