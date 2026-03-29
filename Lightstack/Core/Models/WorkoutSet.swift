import Foundation
import CoreData

/// Local representation of the sets table.
/// Named WorkoutSet to avoid collision with Swift's Set type.
struct WorkoutSet: Codable, Identifiable {
    let id: UUID
    let exerciseId: UUID
    var localId: String?
    var setNumber: Int
    var weightLbs: Double
    var reps: Int
    var rir: Int
    var userFeedback: String?
    var isPR: Bool
    var syncStatus: SyncStatus
    var recordedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case exerciseId = "exercise_id"
        case localId = "local_id"
        case setNumber = "set_number"
        case weightLbs = "weight_lbs"
        case reps
        case rir
        case userFeedback = "user_feedback"
        case isPR = "is_pr"
        case recordedAt = "recorded_at"
    }

    // syncStatus is local-only

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        exerciseId = try c.decode(UUID.self, forKey: .exerciseId)
        localId = try c.decodeIfPresent(String.self, forKey: .localId)
        setNumber = try c.decode(Int.self, forKey: .setNumber)
        weightLbs = try c.decode(Double.self, forKey: .weightLbs)
        reps = try c.decode(Int.self, forKey: .reps)
        rir = try c.decode(Int.self, forKey: .rir)
        userFeedback = try c.decodeIfPresent(String.self, forKey: .userFeedback)
        isPR = try c.decodeIfPresent(Bool.self, forKey: .isPR) ?? false
        recordedAt = try c.decode(Date.self, forKey: .recordedAt)
        syncStatus = .synced
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(exerciseId, forKey: .exerciseId)
        try c.encodeIfPresent(localId, forKey: .localId)
        try c.encode(setNumber, forKey: .setNumber)
        try c.encode(weightLbs, forKey: .weightLbs)
        try c.encode(reps, forKey: .reps)
        try c.encode(rir, forKey: .rir)
        try c.encodeIfPresent(userFeedback, forKey: .userFeedback)
        try c.encode(isPR, forKey: .isPR)
        try c.encode(recordedAt, forKey: .recordedAt)
    }

    func toSupabase() -> WorkoutSet {
        return self
    }

    // MARK: - Core Data Mapping

    init(from cdEntity: CDWorkoutSet) {
        self.id = cdEntity.id ?? UUID()
        self.exerciseId = cdEntity.exercise?.id ?? UUID()
        self.localId = cdEntity.localId
        self.setNumber = Int(cdEntity.setNumber)
        self.weightLbs = cdEntity.weightLbs
        self.reps = Int(cdEntity.reps)
        self.rir = Int(cdEntity.rir)
        self.userFeedback = cdEntity.userFeedback
        self.isPR = cdEntity.isPR
        self.syncStatus = SyncStatus(rawValue: cdEntity.syncStatus ?? "pending") ?? .pending
        self.recordedAt = cdEntity.recordedAt ?? Date()
    }

    func applyToCoreData(_ entity: CDWorkoutSet) {
        entity.id = id
        entity.localId = localId
        entity.setNumber = Int32(setNumber)
        entity.weightLbs = weightLbs
        entity.reps = Int32(reps)
        entity.rir = Int32(rir)
        entity.userFeedback = userFeedback
        entity.isPR = isPR
        entity.syncStatus = syncStatus.rawValue
        entity.recordedAt = recordedAt
    }

    // MARK: - Factory

    static func create(
        exerciseId: UUID,
        setNumber: Int,
        weightLbs: Double,
        reps: Int,
        rir: Int
    ) -> WorkoutSet {
        WorkoutSet(
            id: UUID(),
            exerciseId: exerciseId,
            localId: UUID().uuidString,
            setNumber: setNumber,
            weightLbs: weightLbs,
            reps: reps,
            rir: rir,
            userFeedback: nil,
            isPR: false,
            syncStatus: .pending,
            recordedAt: Date()
        )
    }

    // MARK: - Memberwise Init

    init(
        id: UUID, exerciseId: UUID, localId: String?, setNumber: Int,
        weightLbs: Double, reps: Int, rir: Int, userFeedback: String?,
        isPR: Bool, syncStatus: SyncStatus, recordedAt: Date
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.localId = localId
        self.setNumber = setNumber
        self.weightLbs = weightLbs
        self.reps = reps
        self.rir = rir
        self.userFeedback = userFeedback
        self.isPR = isPR
        self.syncStatus = syncStatus
        self.recordedAt = recordedAt
    }
}
