import Foundation
import os

/// Manages profile state: streak, total sessions, volume, duration, and more.
final class ProfileViewModel: ObservableObject {

    private let logger = Logger(subsystem: "org.lightstack.app", category: "ProfileViewModel")

    @Published var streak: Int = 0
    @Published var totalSessions: Int = 0
    @Published var totalVolume: Double = 0
    @Published var averageSessionDuration: Int = 0
    @Published var averageRIR: Double = 0
    @Published var weeklyFrequency: Double = 0
    @Published var setsPerMuscleGroup: [String: Int] = [:]
    @Published var volumePerMuscleGroup: [String: Double] = [:]
    @Published var topLifts: [(exerciseName: String, e1rm: Double)] = []
    @Published var personalRecords: [PersonalRecord] = []

    // Profile editing state
    @Published var profile: UserProfile?
    @Published var isEditing: Bool = false
    @Published var isSaving: Bool = false

    // Edit fields
    @Published var editDisplayName: String = ""
    @Published var editAge: String = ""
    @Published var editWeightLbs: String = ""
    @Published var editHeightFeet: String = ""
    @Published var editHeightInches: String = ""
    @Published var editTrainingAgeMonths: String = ""
    @Published var editGoals: Set<String> = []
    @Published var editSplitDays: [String] = []
    @Published var editEquipment: [String: Bool] = [:]
    @Published var editCustomEquipment: String = ""
    @Published var editNotesToCoach: String = ""

    private let workoutRepository: WorkoutRepository
    private let statsService: WorkoutStatsService
    private let profileRepository: ProfileRepository
    private let prRepository: PRRepository
    private let validationService: ValidationService

    init(
        workoutRepository: WorkoutRepository,
        statsService: WorkoutStatsService,
        profileRepository: ProfileRepository,
        prRepository: PRRepository,
        validationService: ValidationService
    ) {
        self.workoutRepository = workoutRepository
        self.statsService = statsService
        self.profileRepository = profileRepository
        self.prRepository = prRepository
        self.validationService = validationService
    }

    func loadStats(userId: UUID) {
        streak = workoutRepository.fetchStreak(userId: userId)
        totalSessions = statsService.totalSessions(userId: userId)
        totalVolume = statsService.totalVolume(userId: userId)
        averageSessionDuration = statsService.averageSessionDuration(userId: userId)
        averageRIR = statsService.averageRIR(userId: userId)
        weeklyFrequency = statsService.weeklyFrequency(userId: userId)
        setsPerMuscleGroup = statsService.setsPerMuscleGroup(userId: userId)
        volumePerMuscleGroup = statsService.volumePerMuscleGroup(userId: userId)
        topLifts = statsService.topLifts(userId: userId)
        prRepository.cleanOrphanedPRs(userId: userId)
        personalRecords = prRepository.fetchAllPRs(userId: userId)
    }

    // MARK: - Profile Loading

    func loadProfile(userId: UUID) {
        profile = profileRepository.loadProfile(userId: userId)
        logger.debug("Loaded profile: \(self.profile?.displayName ?? "nil")")
        logger.debug("Split days: \(self.profile?.splitDays ?? [])")
    }

    // MARK: - Editing

    func startEditing() {
        guard let profile = profile else {
            logger.error("Cannot start editing - profile is nil")
            return
        }
        logger.debug("Starting edit with profile: \(profile.displayName ?? "no name")")
        isEditing = true

        editDisplayName = profile.displayName ?? ""
        editAge = profile.age.map { String($0) } ?? ""
        editWeightLbs = profile.weightLbs.map { String(format: "%.1f", $0) } ?? ""

        if let heightInches = profile.heightInches {
            editHeightFeet = String(Int(heightInches) / 12)
            editHeightInches = String(Int(heightInches) % 12)
        } else {
            editHeightFeet = ""
            editHeightInches = ""
        }

        editTrainingAgeMonths = profile.trainingAgeMonths.map { String($0) } ?? ""
        editGoals = Set(profile.primaryGoals)
        editSplitDays = profile.splitDays
        editEquipment = profile.equipment
        editCustomEquipment = profile.customEquipment ?? ""
        editNotesToCoach = profile.notesToCoach ?? ""
    }

    func cancelEditing() {
        isEditing = false
    }

    func saveProfile(userId: UUID) {
        guard var profile = profile else { return }
        isSaving = true

        // Parse and update fields
        profile.displayName = validationService.sanitize(editDisplayName)
        if let n = Int(editAge), (10...120).contains(n) { profile.age = n }
        if let w = Double(editWeightLbs), (50...1000).contains(w) { profile.weightLbs = w }

        if let feet = Int(editHeightFeet), let inches = Int(editHeightInches),
           (3...8).contains(feet), (0...11).contains(inches) {
            profile.heightInches = Double(feet * 12 + inches)
        }

        if let tam = Int(editTrainingAgeMonths) { profile.trainingAgeMonths = max(0, min(1200, tam)) }
        profile.primaryGoals = Array(editGoals)
        profile.splitDays = editSplitDays
        profile.equipment = editEquipment
        profile.customEquipment = editCustomEquipment.isEmpty ? nil : validationService.sanitize(editCustomEquipment)
        profile.notesToCoach = validationService.sanitize(editNotesToCoach)
        profile.updatedAt = Date()

        // Save
        profileRepository.saveProfile(profile)
        self.profile = profile

        isSaving = false
        isEditing = false
    }

    // MARK: - Split Days Management

    func addSplitDay(_ day: String) {
        if !editSplitDays.contains(day) {
            editSplitDays.append(day)
        }
    }

    func removeSplitDay(_ day: String) {
        editSplitDays.removeAll { $0 == day }
    }
}
