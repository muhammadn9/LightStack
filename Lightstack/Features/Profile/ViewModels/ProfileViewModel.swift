import Foundation

/// Manages profile state: streak, total sessions, volume, duration, and more.
final class ProfileViewModel: ObservableObject {

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
        personalRecords = prRepository.fetchAllPRs(userId: userId)
    }

    // MARK: - Profile Loading

    func loadProfile(userId: UUID) {
        profile = profileRepository.loadProfile(userId: userId)
    }

    // MARK: - Editing

    func startEditing() {
        guard let profile = profile else { return }
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
        profile.age = Int(editAge)
        profile.weightLbs = Double(editWeightLbs)

        if let feet = Int(editHeightFeet), let inches = Int(editHeightInches) {
            profile.heightInches = Double(feet * 12 + inches)
        }

        profile.trainingAgeMonths = Int(editTrainingAgeMonths)
        profile.primaryGoals = Array(editGoals)
        profile.splitDays = editSplitDays
        profile.equipment = editEquipment
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
