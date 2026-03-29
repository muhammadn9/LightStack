import Foundation

/// Context container for AI coach calls.
struct CoachContext {
    let profile: UserProfile?
    let rollingSummary: String?
    let recentSessions: [Workout]
    let recentSessionSets: [UUID: [Exercise]]
}

/// Builds the AI prompt context from saved data.
final class CoachContextBuilder {

    private let profileRepository: ProfileRepository
    private let workoutRepository: WorkoutRepository
    private let localStorage: LocalStorageService
    private let validationService: ValidationService

    init(
        profileRepository: ProfileRepository,
        workoutRepository: WorkoutRepository,
        localStorage: LocalStorageService,
        validationService: ValidationService
    ) {
        self.profileRepository = profileRepository
        self.workoutRepository = workoutRepository
        self.localStorage = localStorage
        self.validationService = validationService
    }

    /// Build context for an AI coach call, optionally scoped to a workout type.
    func buildContext(userId: UUID, workoutType: String? = nil) -> CoachContext {
        let profile = profileRepository.fetchProfileSync(userId: userId)

        // Fetch rolling summary for this workout type
        var rollingSummary: String?
        if let type = workoutType,
           let cdSummary = localStorage.fetchContextSummary(userId: userId, workoutType: type) {
            rollingSummary = cdSummary.summaryText
        }

        // Fetch last 2 workouts of same type with their exercises
        let recentWorkouts = workoutRepository.fetchRecentWorkouts(userId: userId, limit: 10)
        var filtered: [Workout] = []
        if let type = workoutType {
            filtered = recentWorkouts.filter { $0.workoutType.lowercased() == type.lowercased() }
            filtered = Array(filtered.prefix(2))
        } else {
            filtered = Array(recentWorkouts.prefix(2))
        }

        var recentSessionSets: [UUID: [Exercise]] = [:]
        for workout in filtered {
            let exercises = workoutRepository.fetchExercises(workoutId: workout.id)
            recentSessionSets[workout.id] = exercises
        }

        return CoachContext(
            profile: profile,
            rollingSummary: rollingSummary,
            recentSessions: filtered,
            recentSessionSets: recentSessionSets
        )
    }
}
