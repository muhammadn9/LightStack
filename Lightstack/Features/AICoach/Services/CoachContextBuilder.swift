import Foundation

/// Context container for AI coach calls.
struct CoachContext {
    let profile: UserProfile?
    let rollingSummary: String?
    let recentSessions: [Workout]
    let recentSessionSets: [UUID: [Exercise]]
    /// Logged sets of the recent sessions, keyed by exercise id.
    var recentLoggedSets: [UUID: [WorkoutSet]] = [:]
    /// Best set on record (heaviest e1RM) per lowercased exercise name.
    var bestSets: [String: (weightLbs: Double, reps: Int)] = [:]
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

    /// How many completed sessions of the same type go into the plan prompt (the last in full,
    /// the rest as trend lines) and into the progression engine.
    static let historySessionCount = 5

    /// Build context for an AI coach call, optionally scoped to a workout type.
    /// History is the last few COMPLETED sessions (at least one logged set), so a
    /// pending, empty or abandoned workout never takes a slot.
    func buildContext(userId: UUID, workoutType: String? = nil, includeHistory: Bool = true) -> CoachContext {
        let profile = profileRepository.fetchProfileSync(userId: userId)

        // Fetch rolling summary for this workout type
        var rollingSummary: String?
        if let type = workoutType,
           let cdSummary = localStorage.fetchContextSummary(userId: userId, workoutType: type) {
            rollingSummary = cdSummary.summaryText
        }

        guard includeHistory else {
            return CoachContext(profile: profile, rollingSummary: rollingSummary,
                                recentSessions: [], recentSessionSets: [:])
        }

        var candidates = workoutRepository.fetchRecentWorkouts(userId: userId, limit: 40)
        if let type = workoutType {
            candidates = candidates.filter { $0.workoutType.lowercased() == type.lowercased() }
        }

        var sessions: [Workout] = []
        var sessionExercises: [UUID: [Exercise]] = [:]
        var loggedSets: [UUID: [WorkoutSet]] = [:]
        for workout in candidates {
            if sessions.count >= Self.historySessionCount { break }
            let exercises = workoutRepository.fetchExercises(workoutId: workout.id)
            var sets: [UUID: [WorkoutSet]] = [:]
            for ex in exercises {
                let exSets = workoutRepository.fetchSets(exerciseId: ex.id).sorted { $0.setNumber < $1.setNumber }
                if !exSets.isEmpty { sets[ex.id] = exSets }
            }
            guard !sets.isEmpty else { continue }
            sessions.append(workout)
            sessionExercises[workout.id] = exercises.filter { sets[$0.id] != nil }
            loggedSets.merge(sets) { a, _ in a }
        }

        var bests: [String: (weightLbs: Double, reps: Int)] = [:]
        for ex in sessionExercises.values.flatMap({ $0 }) {
            let key = ex.name.lowercased()
            guard bests[key] == nil, ex.trackingType != .cardio,
                  let pr = localStorage.fetchPersonalRecord(userId: userId, exerciseName: ex.name) else { continue }
            let record = PersonalRecord(from: pr)
            bests[key] = (record.weightLbs, record.reps)
        }

        return CoachContext(
            profile: profile,
            rollingSummary: rollingSummary,
            recentSessions: sessions,
            recentSessionSets: sessionExercises,
            recentLoggedSets: loggedSets,
            bestSets: bests
        )
    }
}
