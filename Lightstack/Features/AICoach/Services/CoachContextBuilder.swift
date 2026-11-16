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
    /// Per-exercise briefs for the exercises of the latest same-type session (match them to the draft with `briefs(matching:)`).
    var briefs: [ExerciseBrief] = []
    /// Hard sets per sub-muscle over the last 28 days (all workout types), keyed by muscle name.
    var muscleLoad: [String: MuscleLoad] = [:]
    /// Yesterday's intake and the athlete's nutrition goal, when the nutrition feature has data.
    var fuel: CoachFuelSummary?
    /// Meals in the 24 hours before the workout (or before now); nil when none, or when sharing them is off.
    var meals: PreWorkoutMeals?
    /// The coach's past calls and notes from up to 60 recent workouts (all types), parsed from the stored documents only.
    var memory = CoachMemoryIndex()

    /// The athlete's usual session length in minutes (median of recent sessions).
    var usualMinutes: Int? { medianSessionMinutes }

    /// The briefs of the draft's exercises, in draft order.
    func briefs(matching draft: [DraftExercise]) -> [ExerciseBrief] {
        draft.compactMap { d in briefs.first(where: { ExerciseNameResolver.isMatch($0.name, d.name) }) }
    }
}

/// Builds the AI prompt context from saved data.
final class CoachContextBuilder {

    private let profileRepository: ProfileRepository
    private let workoutRepository: WorkoutRepository
    private let localStorage: LocalStorageService
    private let validationService: ValidationService
    private let fuel: ((UUID, Date) -> CoachFuelSummary?)?
    private let meals: ((UUID, Date) -> PreWorkoutMeals?)?
    private let defaults: UserDefaults

    init(
        profileRepository: ProfileRepository,
        workoutRepository: WorkoutRepository,
        localStorage: LocalStorageService,
        validationService: ValidationService,
        fuel: ((UUID, Date) -> CoachFuelSummary?)? = nil,
        meals: ((UUID, Date) -> PreWorkoutMeals?)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.fuel = fuel
        self.meals = meals
        self.defaults = defaults
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
    /// Muscle load looks back this far (this week plus the three weeks before it).
    static let loadDays = 28

    /// Build context for an AI coach call, optionally scoped to a workout type.
    /// History is the last few COMPLETED sessions (at least one logged set), so a
    /// pending, empty or abandoned workout never takes a slot.
    func buildContext(userId: UUID, workoutType: String? = nil, includeHistory: Bool = true,
                      excludingWorkoutId excluded: UUID? = nil, now: Date = Date(),
                      fuelAt: Date? = nil) -> CoachContext {
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

        // 60 workouts for the coach's memory (documents only); the history passes use the newest 40.
        let scanned = workoutRepository.fetchRecentWorkouts(userId: userId, limit: CoachMemoryIndex.scanLimit)
            .filter { $0.id != excluded }
        let everything = Array(scanned.prefix(40))
        var candidates = everything
        if let type = workoutType {
            candidates = candidates.filter { $0.workoutType.lowercased() == type.lowercased() }
        }

        // Every exercise and set is fetched at most once; the history, recency and load passes share them.
        var exerciseCache: [UUID: [Exercise]] = [:]
        var setCache: [UUID: [WorkoutSet]] = [:]
        func exercises(of workout: Workout) -> [Exercise] {
            if let cached = exerciseCache[workout.id] { return cached }
            let fetched = workoutRepository.fetchExercises(workoutId: workout.id)
            exerciseCache[workout.id] = fetched
            return fetched
        }
        func sets(of exercise: Exercise) -> [WorkoutSet] {
            if let cached = setCache[exercise.id] { return cached }
            let fetched = workoutRepository.fetchSets(exerciseId: exercise.id).sorted { $0.setNumber < $1.setNumber }
            setCache[exercise.id] = fetched
            return fetched
        }

        var sessions: [Workout] = []
        var sessionExercises: [UUID: [Exercise]] = [:]
        var loggedSets: [UUID: [WorkoutSet]] = [:]
        for workout in candidates {
            if sessions.count >= Self.historySessionCount { break }
            let workoutExercises = exercises(of: workout)
            var workoutSets: [UUID: [WorkoutSet]] = [:]
            for ex in workoutExercises {
                let exSets = sets(of: ex)
                if !exSets.isEmpty { workoutSets[ex.id] = exSets }
            }
            guard !workoutSets.isEmpty else { continue }
            sessions.append(workout)
            sessionExercises[workout.id] = workoutExercises.filter { workoutSets[$0.id] != nil }
            loggedSets.merge(workoutSets) { a, _ in a }
        }

        var bests: [String: (weightLbs: Double, reps: Int)] = [:]
        for ex in sessionExercises.values.flatMap({ $0 }) {
            let key = ex.name.lowercased()
            guard bests[key] == nil, ex.trackingType != .cardio,
                  let pr = localStorage.fetchPersonalRecord(userId: userId, exerciseName: ex.name) else { continue }
            let record = PersonalRecord(from: pr)
            bests[key] = (record.weightLbs, record.reps)
        }

        // Muscle recency and load across every workout type: one pass over the last 28 days.
        let recencyCutoff = now.addingTimeInterval(-Double(Self.recencyDays) * 86_400)
        let loadCutoff = now.addingTimeInterval(-Double(Self.loadDays) * 86_400)
        var windowExercises: [UUID: [Exercise]] = [:]
        var windowSets: [UUID: [WorkoutSet]] = [:]
        var windowWorkouts: [Workout] = []
        for workout in everything where workout.date >= loadCutoff && workout.date <= now.addingTimeInterval(3600) {
            let workoutExercises = exercises(of: workout)
            var any = false
            for ex in workoutExercises {
                let exSets = sets(of: ex)
                if !exSets.isEmpty { windowSets[ex.id] = exSets; any = true }
            }
            guard any else { continue }
            windowExercises[workout.id] = workoutExercises
            windowWorkouts.append(workout)
        }
        let recencyWorkouts = windowWorkouts.filter { $0.date >= recencyCutoff }

        // Nutrition goes to the AI only when the athlete shares it (the meals switch only adds the meal names).
        let shareSummary = CoachPreferences.shareNutritionSummary(in: defaults)
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
                workouts: recencyWorkouts, exercises: windowExercises, loggedSets: windowSets),
            medianSessionMinutes: Self.medianMinutes(everything, preferring: workoutType),
            briefs: ExerciseBriefBuilder.briefs(sessions: sessions, exercises: sessionExercises, loggedSets: loggedSets),
            muscleLoad: MuscleLoadBuilder.build(
                workouts: windowWorkouts, exercises: windowExercises, loggedSets: windowSets, now: now),
            fuel: shareSummary ? fuel?(userId, fuelAt ?? now) : nil,
            meals: shareSummary && CoachPreferences.sharePreWorkoutMeals(in: defaults) ? meals?(userId, fuelAt ?? now) : nil,
            memory: CoachMemoryIndex(workouts: scanned)
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

// MARK: - Brief types

/// How an athlete trains a lift, from the median reps of their top sets.
enum LiftStyle: String, Equatable {
    case heavyLow, moderate, lightHigh

    /// Median top-set reps: 6 or fewer is heavy-low, 7-11 moderate, 12+ light-high.
    static func from(medianReps: Double) -> LiftStyle {
        if medianReps < 7 { return .heavyLow }
        if medianReps < 12 { return .moderate }
        return .lightHigh
    }

    var label: String {
        switch self {
        case .heavyLow: return "heavy-low"
        case .moderate: return "moderate"
        case .lightHigh: return "light-high"
        }
    }
}

/// Median set-to-set time in seconds (a set's log to the next set's log), actual vs prescribed.
struct RestStats: Equatable {
    var heavyActual: Int?
    var heavyPrescribed: Int?
    var lightActual: Int?
    var lightPrescribed: Int?
    /// How many intervals went into the medians.
    var samples: Int = 0

    var isEmpty: Bool { samples == 0 }
}

/// Everything the coach should know about one planned exercise, in as few tokens as possible.
struct ExerciseBrief: Equatable {
    var name: String
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    var style: LiftStyle
    var repLow: Int
    var repHigh: Int
    /// Top set of the latest session.
    var lastTop: HistorySet
    /// Average RIR of the latest session's working sets that have one.
    var avgRIR: Double?
    /// Best working-set e1RM per session, oldest to newest (up to 4 sessions).
    var e1RMTrend: [Int]
    var rest: RestStats

    var muscles: [String] { primaryMuscles + secondaryMuscles }
}

/// Hard sets of one sub-muscle: this week against the weekly average of the three weeks before.
struct MuscleLoad: Equatable {
    var thisWeekSets: Double
    var avgPrior3WeeksSets: Double
    /// Whole days since the muscle last got a hard set.
    var daysSince: Int?
}


/// One past session of one exercise, as the brief builder reads it.
struct BriefSession {
    var date: Date
    /// Logged sets in set order.
    var sets: [WorkoutSet]
    var inSuperset: Bool
    /// What the coach prescribed for this exercise that day, when the workout kept it.
    var prescription: ExercisePrescription?
}

enum ExerciseBriefBuilder {

    /// Briefs for the strength exercises of the newest session (newest session first in `sessions`).
    static func briefs(
        sessions: [Workout], exercises: [UUID: [Exercise]], loggedSets: [UUID: [WorkoutSet]]
    ) -> [ExerciseBrief] {
        guard let latest = sessions.first else { return [] }
        let docs = sessions.map { CoachReviewDocument.parse($0.aiProgressionNote) }
        var seen: [String] = []
        var result: [ExerciseBrief] = []
        let latestExercises = (exercises[latest.id] ?? []).sorted { $0.orderIndex < $1.orderIndex }
        for ex in latestExercises where ex.trackingType != .cardio {
            if seen.contains(where: { ExerciseNameResolver.isMatch($0, ex.name) }) { continue }
            seen.append(ex.name)
            var history: [BriefSession] = []
            for (i, session) in sessions.enumerated() {
                let match = (exercises[session.id] ?? []).first {
                    $0.name.lowercased() == ex.name.lowercased() || ExerciseNameResolver.isMatch($0.name, ex.name)
                }
                guard let match, let sets = loggedSets[match.id], !sets.isEmpty else { continue }
                let prescription = docs[i]?.prescription.first { ExerciseNameResolver.isMatch($0.name, ex.name) }
                history.append(BriefSession(date: session.date, sets: sets,
                                            inSuperset: match.supersetGroupId != nil, prescription: prescription))
            }
            if let brief = build(name: ex.name, muscleGroup: ex.muscleGroup, sessions: history) { result.append(brief) }
        }
        return result
    }

    /// Brief for one exercise from its past sessions (any order). nil when there is nothing logged.
    static func build(name: String, muscleGroup: String, sessions: [BriefSession]) -> ExerciseBrief? {
        let usable = sessions.filter { !$0.sets.isEmpty }.sorted { $0.date > $1.date }
        guard let latest = usable.first else { return nil }
        let recent = Array(usable.prefix(4))

        func working(_ session: BriefSession) -> [HistorySet] {
            SetStyleDetector.splitWarmups(session.sets.map { HistorySet($0.weightLbs, $0.reps, rir: $0.rir) }).working
        }
        func topSet(_ sets: [HistorySet]) -> HistorySet? {
            sets.max { ($0.weight, $0.reps) < ($1.weight, $1.reps) }
        }

        let lastWorking = working(latest)
        guard let lastTop = topSet(lastWorking) else { return nil }
        let reps = recent.compactMap { topSet(working($0))?.reps }.sorted()
        guard let repLow = reps.first, let repHigh = reps.last else { return nil }
        let mid = reps.count / 2
        let medianReps = reps.count % 2 == 1 ? Double(reps[mid]) : Double(reps[mid - 1] + reps[mid]) / 2

        let rirs = lastWorking.compactMap { $0.rir }
        let avgRIR: Double? = rirs.isEmpty ? nil : Double(rirs.reduce(0, +)) / Double(rirs.count)
        let trend = recent.reversed().compactMap { session -> Int? in
            guard let best = working(session).map({ $0.e1RM }).max(), best > 0 else { return nil }
            return Int(best.rounded())
        }
        let muscles = ExerciseTraits.muscles(forExercise: name, muscleGroup: muscleGroup)
        return ExerciseBrief(
            name: name, primaryMuscles: muscles.primary, secondaryMuscles: muscles.secondary,
            style: LiftStyle.from(medianReps: medianReps), repLow: repLow, repHigh: repHigh,
            lastTop: lastTop, avgRIR: avgRIR, e1RMTrend: trend,
            rest: restStats(usable))
    }

    /// Median rest between logged sets, split into heavy and light, against what was prescribed.
    /// Intervals of 15 s or less (batch-logged) or over 600 s (a break) are dropped, as are
    /// superset exercises and the gap after a warm-up. The gap is judged by the set before it:
    /// heavy = a top/ramp set, 6 reps or fewer, or at least 85% of that session's top weight at 10 reps or fewer.
    static func restStats(_ sessions: [BriefSession]) -> RestStats {
        var heavyActual: [Double] = []
        var heavyRx: [Double] = []
        var lightActual: [Double] = []
        var lightRx: [Double] = []
        var samples = 0
        for session in sessions where !session.inSuperset && session.sets.count >= 2 {
            let sets = session.sets
            let history = sets.map { HistorySet($0.weightLbs, $0.reps, rir: $0.rir) }
            let warmups = SetStyleDetector.warmupFlags(history)
            let topWeight = history.map { $0.weight }.max() ?? 0
            let planned = session.prescription?.sets ?? []
            for i in 1..<sets.count {
                let gap = sets[i].recordedAt.timeIntervalSince(sets[i - 1].recordedAt)
                guard gap > 15, gap <= 600 else { continue }
                let before = i - 1
                let role: SetRole? = before < planned.count ? planned[before].role : nil
                guard !warmups[before], role != .warmup else { continue }
                let s = history[before]
                let heavy = role == .top || role == .ramp || s.reps <= 6
                    || (topWeight > 0 && s.weight >= 0.85 * topWeight && s.reps <= 10)
                let prescribed: Double? = before < planned.count ? Double(planned[before].restSeconds) : nil
                samples += 1
                if heavy {
                    heavyActual.append(gap)
                    if let prescribed { heavyRx.append(prescribed) }
                } else {
                    lightActual.append(gap)
                    if let prescribed { lightRx.append(prescribed) }
                }
            }
        }
        return RestStats(heavyActual: median(heavyActual), heavyPrescribed: median(heavyRx),
                         lightActual: median(lightActual), lightPrescribed: median(lightRx), samples: samples)
    }

    private static func median(_ values: [Double]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        let m = sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
        return Int(m.rounded())
    }
}

enum MuscleLoadBuilder {

    /// Hard sets per sub-muscle: RIR 3 or less (or unknown), warm-ups excluded; the primary muscle counts 1,
    /// a secondary 0.5. "This week" is the last 7 days; the prior average is days 7-28 divided by 3.
    static func build(
        workouts: [Workout], exercises: [UUID: [Exercise]], loggedSets: [UUID: [WorkoutSet]], now: Date
    ) -> [String: MuscleLoad] {
        var thisWeek: [String: Double] = [:]
        var prior: [String: Double] = [:]
        var latest: [String: Date] = [:]
        for workout in workouts {
            let age = now.timeIntervalSince(workout.date)
            guard age <= Double(CoachContextBuilder.loadDays) * 86_400 else { continue }
            let isThisWeek = age < 7 * 86_400
            for ex in exercises[workout.id] ?? [] where ex.trackingType != .cardio {
                let sets = loggedSets[ex.id] ?? []
                guard !sets.isEmpty else { continue }
                let working = SetStyleDetector.splitWarmups(sets.map { HistorySet($0.weightLbs, $0.reps, rir: $0.rir) }).working
                let hard = Double(working.filter { ($0.rir ?? 0) <= 3 }.count)
                guard hard > 0 else { continue }
                let muscles = ExerciseTraits.muscles(forExercise: ex.name, muscleGroup: ex.muscleGroup)
                let weighted: [(String, Double)] = muscles.primary.map { ($0, 1.0) } + muscles.secondary.map { ($0, 0.5) }
                for (muscle, weight) in weighted {
                    if isThisWeek { thisWeek[muscle, default: 0] += hard * weight } else { prior[muscle, default: 0] += hard * weight }
                    if let seen = latest[muscle], seen >= workout.date { continue }
                    latest[muscle] = workout.date
                }
            }
        }
        var result: [String: MuscleLoad] = [:]
        for muscle in Set(thisWeek.keys).union(prior.keys) {
            let days = latest[muscle].map { max(0, Int((now.timeIntervalSince($0) / 86_400).rounded(.down))) }
            result[muscle] = MuscleLoad(thisWeekSets: thisWeek[muscle] ?? 0,
                                        avgPrior3WeeksSets: (prior[muscle] ?? 0) / 3, daysSince: days)
        }
        return result
    }
}
