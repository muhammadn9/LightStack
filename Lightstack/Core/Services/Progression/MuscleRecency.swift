import Foundation

/// Coarse muscle groups so "Upper Chest" and "Chest" count together.
enum MuscleGroups {

    static func canonical(_ raw: String) -> String {
        let n = raw.lowercased()
        if n.contains("rear") || n.contains("face pull") { return "rear delts" }
        if n.contains("chest") || n.contains("pec") { return "chest" }
        if n.contains("back") || n.contains("lat") || n.contains("trap") || n.contains("row") { return "back" }
        if n.contains("shoulder") || n.contains("delt") { return "shoulders" }
        if n.contains("bicep") { return "biceps" }
        if n.contains("tricep") { return "triceps" }
        if n.contains("quad") { return "quads" }
        if n.contains("hamstring") { return "hamstrings" }
        if n.contains("glute") { return "glutes" }
        if n.contains("calf") || n.contains("calves") { return "calves" }
        if n.contains("core") || n.contains("abs") { return "core" }
        if n.contains("leg") { return "legs" }
        if n.contains("forearm") { return "forearms" }
        return n.trimmingCharacters(in: .whitespaces).isEmpty ? "other" : n.trimmingCharacters(in: .whitespaces)
    }

    /// Group for an exercise: its muscle group field, else a guess from its name.
    static func canonical(forExercise name: String, muscleGroup: String) -> String {
        let fromGroup = canonical(muscleGroup)
        if fromGroup != "other", fromGroup != "general" { return name.lowercased().contains("face pull") ? "rear delts" : fromGroup }
        return canonical(WorkoutSessionService.inferMuscleGroup(name))
    }
}

/// How recently, and how hard, a muscle group was trained.
struct MuscleRecency: Equatable {
    var lastTrained: Date
    /// Hard working sets of that muscle in its most recent session.
    var hardSets: Int

    func hoursSince(_ now: Date) -> Double { max(0, now.timeIntervalSince(lastTrained)) / 3600 }

    /// Trained hard within the last 48 hours (3+ working sets).
    func isFresh(now: Date, withinHours hours: Double = 48) -> Bool {
        hardSets >= 3 && hoursSince(now) <= hours
    }
}

enum MuscleRecencyBuilder {

    /// Last training date per muscle group from logged history of any workout type.
    /// - Parameter workouts: any order; workouts without logged sets are ignored.
    static func build(
        workouts: [Workout],
        exercises: [UUID: [Exercise]],
        loggedSets: [UUID: [WorkoutSet]]
    ) -> [String: MuscleRecency] {
        var result: [String: MuscleRecency] = [:]
        for workout in workouts.sorted(by: { $0.date > $1.date }) {
            var perMuscle: [String: Int] = [:]
            for ex in exercises[workout.id] ?? [] where ex.trackingType != .cardio {
                let sets = loggedSets[ex.id] ?? []
                guard !sets.isEmpty else { continue }
                let working = SetStyleDetector.splitWarmups(sets.map { HistorySet($0.weightLbs, $0.reps, rir: $0.rir) }).working
                let hard = working.filter { ($0.rir ?? 2) <= 3 }.count
                let muscle = MuscleGroups.canonical(forExercise: ex.name, muscleGroup: ex.muscleGroup)
                perMuscle[muscle, default: 0] += hard
            }
            for (muscle, hard) in perMuscle where result[muscle] == nil {
                result[muscle] = MuscleRecency(lastTrained: workout.date, hardSets: hard)
            }
        }
        return result
    }
}
