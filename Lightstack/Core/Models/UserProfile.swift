import Foundation
import CoreData

/// Local representation of the profiles table.
/// Used as the data transfer object between Core Data and Supabase.
struct UserProfile: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var displayName: String?
    var age: Int?
    var heightInches: Double?
    var weightLbs: Double?
    var trainingAgeMonths: Int?
    var primaryGoals: [String]
    var splitDays: [String]
    var avoidExercises: [String]
    var equipment: [String: Bool]
    var notesToCoach: String?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case displayName = "display_name"
        case age
        case heightInches = "height_inches"
        case weightLbs = "weight_lbs"
        case trainingAgeMonths = "training_age_months"
        case primaryGoals = "primary_goals"
        case splitDays = "split_days"
        case avoidExercises = "avoid_exercises"
        case equipment
        case notesToCoach = "notes_to_coach"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // MARK: - Core Data Mapping

    init(from cdEntity: CDUserProfile) {
        self.id = cdEntity.id ?? UUID()
        self.userId = cdEntity.userId ?? UUID()
        self.displayName = cdEntity.displayName
        self.age = cdEntity.age == 0 ? nil : Int(cdEntity.age)
        self.heightInches = cdEntity.heightInches == 0 ? nil : cdEntity.heightInches
        self.weightLbs = cdEntity.weightLbs == 0 ? nil : cdEntity.weightLbs
        self.trainingAgeMonths = cdEntity.trainingAgeMonths == 0 ? nil : Int(cdEntity.trainingAgeMonths)
        self.primaryGoals = cdEntity.primaryGoals ?? []
        self.splitDays = cdEntity.splitDays ?? []
        self.avoidExercises = cdEntity.avoidExercises ?? []
        self.equipment = cdEntity.equipment ?? [:]
        self.notesToCoach = cdEntity.notesToCoach
        self.createdAt = cdEntity.createdAt ?? Date()
        self.updatedAt = cdEntity.updatedAt ?? Date()
    }

    func applyToCoreData(_ entity: CDUserProfile) {
        entity.id = id
        entity.userId = userId
        entity.displayName = displayName
        entity.age = Int32(age ?? 0)
        entity.heightInches = heightInches ?? 0
        entity.weightLbs = weightLbs ?? 0
        entity.trainingAgeMonths = Int32(trainingAgeMonths ?? 0)
        entity.primaryGoals = primaryGoals as NSObject as? [String]
        entity.splitDays = splitDays as NSObject as? [String]
        entity.avoidExercises = avoidExercises as NSObject as? [String]
        entity.equipment = equipment as NSObject as? [String: Bool]
        entity.notesToCoach = notesToCoach
        entity.createdAt = createdAt
        entity.updatedAt = updatedAt
    }

    // MARK: - Factory

    static func create(
        userId: UUID,
        displayName: String?,
        age: Int?,
        heightInches: Double?,
        weightLbs: Double?,
        trainingAgeMonths: Int?,
        primaryGoals: [String],
        splitDays: [String],
        avoidExercises: [String],
        equipment: [String: Bool],
        notesToCoach: String?
    ) -> UserProfile {
        let now = Date()
        return UserProfile(
            id: UUID(),
            userId: userId,
            displayName: displayName,
            age: age,
            heightInches: heightInches,
            weightLbs: weightLbs,
            trainingAgeMonths: trainingAgeMonths,
            primaryGoals: primaryGoals,
            splitDays: splitDays,
            avoidExercises: avoidExercises,
            equipment: equipment,
            notesToCoach: notesToCoach,
            createdAt: now,
            updatedAt: now
        )
    }

    // MARK: - Memberwise Init

    init(
        id: UUID,
        userId: UUID,
        displayName: String?,
        age: Int?,
        heightInches: Double?,
        weightLbs: Double?,
        trainingAgeMonths: Int?,
        primaryGoals: [String],
        splitDays: [String],
        avoidExercises: [String],
        equipment: [String: Bool],
        notesToCoach: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.userId = userId
        self.displayName = displayName
        self.age = age
        self.heightInches = heightInches
        self.weightLbs = weightLbs
        self.trainingAgeMonths = trainingAgeMonths
        self.primaryGoals = primaryGoals
        self.splitDays = splitDays
        self.avoidExercises = avoidExercises
        self.equipment = equipment
        self.notesToCoach = notesToCoach
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
