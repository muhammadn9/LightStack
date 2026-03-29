import Foundation
import CoreData

/// Local representation of the exercises table.
struct Exercise: Codable, Identifiable {
    let id: UUID
    var workoutId: UUID
    var localId: String?
    var name: String
    var muscleGroup: String
    var orderIndex: Int
    var targetSets: Int?
    var targetReps: String?
    var targetRir: String?
    var restSeconds: Int?
    var coachNote: String?
    var syncStatus: SyncStatus

    enum CodingKeys: String, CodingKey {
        case id
        case workoutId = "workout_id"
        case localId = "local_id"
        case name
        case muscleGroup = "muscle_group"
        case orderIndex = "order_index"
        case targetSets = "target_sets"
        case targetReps = "target_reps"
        case targetRir = "target_rir"
        case restSeconds = "rest_seconds"
        case coachNote = "coach_note"
    }

    // syncStatus is local-only

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        workoutId = try c.decode(UUID.self, forKey: .workoutId)
        localId = try c.decodeIfPresent(String.self, forKey: .localId)
        name = try c.decode(String.self, forKey: .name)
        muscleGroup = try c.decode(String.self, forKey: .muscleGroup)
        orderIndex = try c.decode(Int.self, forKey: .orderIndex)
        targetSets = try c.decodeIfPresent(Int.self, forKey: .targetSets)
        targetReps = try c.decodeIfPresent(String.self, forKey: .targetReps)
        targetRir = try c.decodeIfPresent(String.self, forKey: .targetRir)
        restSeconds = try c.decodeIfPresent(Int.self, forKey: .restSeconds)
        coachNote = try c.decodeIfPresent(String.self, forKey: .coachNote)
        syncStatus = .synced
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(workoutId, forKey: .workoutId)
        try c.encodeIfPresent(localId, forKey: .localId)
        try c.encode(name, forKey: .name)
        try c.encode(muscleGroup, forKey: .muscleGroup)
        try c.encode(orderIndex, forKey: .orderIndex)
        try c.encodeIfPresent(targetSets, forKey: .targetSets)
        try c.encodeIfPresent(targetReps, forKey: .targetReps)
        try c.encodeIfPresent(targetRir, forKey: .targetRir)
        try c.encodeIfPresent(restSeconds, forKey: .restSeconds)
        try c.encodeIfPresent(coachNote, forKey: .coachNote)
    }

    func toSupabase() -> Exercise {
        return self
    }

    // MARK: - Core Data Mapping

    init(from cdEntity: CDExercise) {
        self.id = cdEntity.id ?? UUID()
        self.workoutId = cdEntity.workout?.id ?? UUID()
        self.localId = cdEntity.localId
        self.name = cdEntity.name ?? ""
        self.muscleGroup = cdEntity.muscleGroup ?? ""
        self.orderIndex = Int(cdEntity.orderIndex)
        self.targetSets = cdEntity.targetSets == 0 ? nil : Int(cdEntity.targetSets)
        self.targetReps = cdEntity.targetReps
        self.targetRir = cdEntity.targetRir
        self.restSeconds = cdEntity.restSeconds == 0 ? nil : Int(cdEntity.restSeconds)
        self.coachNote = cdEntity.coachNote
        self.syncStatus = SyncStatus(rawValue: cdEntity.syncStatus ?? "pending") ?? .pending
    }

    func applyToCoreData(_ entity: CDExercise) {
        entity.id = id
        entity.localId = localId
        entity.name = name
        entity.muscleGroup = muscleGroup
        entity.orderIndex = Int32(orderIndex)
        entity.targetSets = Int32(targetSets ?? 0)
        entity.targetReps = targetReps
        entity.targetRir = targetRir
        entity.restSeconds = Int32(restSeconds ?? 0)
        entity.coachNote = coachNote
        entity.syncStatus = syncStatus.rawValue
    }

    // MARK: - Factory

    static func create(
        workoutId: UUID,
        name: String,
        muscleGroup: String,
        orderIndex: Int,
        targetSets: Int?,
        targetReps: String?,
        targetRir: String?,
        restSeconds: Int?,
        coachNote: String?
    ) -> Exercise {
        Exercise(
            id: UUID(),
            workoutId: workoutId,
            localId: UUID().uuidString,
            name: name,
            muscleGroup: muscleGroup,
            orderIndex: orderIndex,
            targetSets: targetSets,
            targetReps: targetReps,
            targetRir: targetRir,
            restSeconds: restSeconds,
            coachNote: coachNote,
            syncStatus: .pending
        )
    }

    // MARK: - Memberwise Init

    init(
        id: UUID, workoutId: UUID, localId: String?, name: String,
        muscleGroup: String, orderIndex: Int, targetSets: Int?,
        targetReps: String?, targetRir: String?, restSeconds: Int?,
        coachNote: String?, syncStatus: SyncStatus
    ) {
        self.id = id
        self.workoutId = workoutId
        self.localId = localId
        self.name = name
        self.muscleGroup = muscleGroup
        self.orderIndex = orderIndex
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetRir = targetRir
        self.restSeconds = restSeconds
        self.coachNote = coachNote
        self.syncStatus = syncStatus
    }
}
