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
    /// The coach's own reviews of the latest same-type sessions, newest first.
    var recentReviews: [CoachReviewEntry] = []
    /// Last trained date and hard sets per canonical muscle group, across all workout types.
    var muscleRecency: [String: MuscleRecency] = [:]
    /// Median length of recent finished sessions, when there is enough history.
    var medianSessionMinutes: Int?
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
    /// Past reviews shown to the plan and post-workout calls.
    static let reviewCount = 4
    /// Muscle recency looks back this far.
    static let recencyDays = 7

    /// Build context for an AI coach call, optionally scoped to a workout type.
    /// History is the last few COMPLETED sessions (at least one logged set), so a
    /// pending, empty or abandoned workout never takes a slot.
    func buildContext(userId: UUID, workoutType: String? = nil, includeHistory: Bool = true,
                      excludingWorkoutId excluded: UUID? = nil, now: Date = Date()) -> CoachContext {
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

        let everything = workoutRepository.fetchRecentWorkouts(userId: userId, limit: 40).filter { $0.id != excluded }
        var candidates = everything
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

        // Muscle recency across every workout type in the last week.
        let cutoff = now.addingTimeInterval(-Double(Self.recencyDays) * 86_400)
        var recencyExercises: [UUID: [Exercise]] = [:]
        var recencySets: [UUID: [WorkoutSet]] = [:]
        var recencyWorkouts: [Workout] = []
        for workout in everything where workout.date >= cutoff && workout.date <= now.addingTimeInterval(3600) {
            let exercises = workoutRepository.fetchExercises(workoutId: workout.id)
            var any = false
            for ex in exercises {
                let exSets = workoutRepository.fetchSets(exerciseId: ex.id)
                if !exSets.isEmpty { recencySets[ex.id] = exSets; any = true }
            }
            guard any else { continue }
            recencyExercises[workout.id] = exercises
            recencyWorkouts.append(workout)
        }

        return CoachContext(
            profile: profile,
            rollingSummary: rollingSummary,
            recentSessions: sessions,
            recentSessionSets: sessionExercises,
            recentLoggedSets: loggedSets,
            bestSets: bests,
            recentReviews: workoutType.map {
                CoachReviewStore.latestReviews(from: everything, workoutType: $0, limit: Self.reviewCount)
            } ?? [],
            muscleRecency: MuscleRecencyBuilder.build(
                workouts: recencyWorkouts, exercises: recencyExercises, loggedSets: recencySets),
            medianSessionMinutes: Self.medianMinutes(everything, preferring: workoutType)
        )
    }

    /// Median of the last few finished sessions' durations (same type when there are 3+ of them).
    static func medianMinutes(_ workouts: [Workout], preferring type: String?) -> Int? {
        func durations(_ list: [Workout]) -> [Int] {
            list.sorted { $0.date > $1.date }.compactMap(\.durationMinutes).filter { (10...180).contains($0) }.prefix(8).map { $0 }
        }
        var values = type.map { t in durations(workouts.filter { $0.workoutType.lowercased() == t.lowercased() }) } ?? []
        if values.count < 3 { values = durations(workouts) }
        guard values.count >= 2 else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        let median = sorted.count % 2 == 1 ? Double(sorted[mid]) : Double(sorted[mid - 1] + sorted[mid]) / 2
        return Int(median.rounded())
    }
}
