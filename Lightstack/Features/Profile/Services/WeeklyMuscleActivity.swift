import CoreData
import Foundation

/// Weighted hard-set counts for each muscle, scoped to the user's local Monday–Sunday week.
/// This is a derived read model: workout edits, deletions and offline logging are reflected
/// the next time it is calculated. No AI request, migration or remote write is involved.
struct WeeklyMuscleActivity {
    let weekStart: Date
    let setsByMuscle: [String: Double]
    let completedSets: Int

    func intensity(for muscle: String) -> Double {
        // Full brightness around eight effective sets in a week; 0 means no highlight.
        min(1, max(0, (setsByMuscle[muscle] ?? 0) / 8))
    }

    static func empty(now: Date = Date(), calendar: Calendar = .current) -> Self {
        let week = ProgressStats.weekCalendar(calendar)
        return .init(
            weekStart: ProgressStats.weekStart(of: now, calendar: week),
            setsByMuscle: [:],
            completedSets: 0
        )
    }
}

enum MuscleExerciseMap {
    /// Main target counts as 1 set; involved secondary targets are counted at 0.35 sets.
    /// Conservative, hand-maintained patterns. Unknown exercises are mapped only by their
    /// saved primary group, rather than inventing detailed anatomical targets.
    static func targets(exerciseName: String, muscleGroup: String) -> [String: Double] {
        let name = normalize(exerciseName)
        func has(_ terms: String...) -> Bool { terms.contains { name.contains($0) } }
        func weights(_ primary: [String], _ secondary: [String] = []) -> [String: Double] {
            var result: [String: Double] = [:]
            primary.forEach { result[$0] = 1 }
            secondary.forEach { result[$0] = max(result[$0] ?? 0, 0.35) }
            return result
        }

        if has("calf raise", "calf press", "seated calf", "standing calf") {
            return weights(["calves"])
        }
        if has("tibialis raise", "toe raise", "shin raise") { return weights(["tibialis"]) }
        if has("woodchop", "wood chop", "pallof", "russian twist", "side bend") {
            return weights(["obliques"], ["abs"])
        }
        if has("crunch", "sit up", "situp", "ab wheel", "leg raise", "knee raise", "plank") {
            return weights(["abs"], ["obliques", "hipFlexors"])
        }
        if has("hip adduction", "adductor", "inner thigh") { return weights(["adductors"]) }
        if has("hip abduction", "abductor") { return weights(["glutes"]) }
        if has("leg extension") { return weights(["quads"]) }
        if has("leg curl", "hamstring curl") { return weights(["hamstrings"]) }
        if has("romanian deadlift", "rdl", "stiff leg", "good morning") {
            return weights(["hamstrings", "glutes"], ["lowerBack"])
        }
        if has("deadlift") { return weights(["hamstrings", "glutes"], ["lowerBack", "traps"]) }
        if has("hip thrust", "glute bridge", "kickback") { return weights(["glutes"], ["hamstrings"]) }
        if has("squat", "leg press", "hack squat", "split squat", "lunge", "step up") {
            return weights(["quads"], ["glutes", "adductors"])
        }
        if has("shrug") { return weights(["traps"]) }
        if has("face pull", "reverse fly", "reverse pec", "rear delt") {
            return weights(["rearDelts", "rhomboids"], ["traps"])
        }
        if has("lateral raise", "side raise", "upright row") {
            return weights(["sideDelts"], ["traps"])
        }
        if has("shoulder press", "overhead press", "military press", "arnold press") {
            return weights(["frontDelts", "sideDelts"], ["triceps"])
        }
        if has("tricep", "triceps", "pushdown", "skull crusher", "overhead extension") {
            return weights(["triceps"])
        }
        if has("hammer curl", "reverse curl") { return weights(["brachialis", "forearms"], ["biceps"]) }
        if has("curl") { return weights(["biceps"], ["brachialis", "forearms"]) }
        if has("wrist curl", "wrist roller", "grip trainer", "farmer carry") {
            return weights(["forearms"], ["traps"])
        }
        if has("pull up", "pullup", "chin up", "pulldown", "pull down", "straight arm pull") {
            return weights(["lats"], ["biceps", "rhomboids"])
        }
        if has("row") {
            return weights(["lats", "rhomboids"], ["biceps", "rearDelts", "traps"])
        }
        if has("pullover") { return weights(["lats"], ["chest"]) }
        if has("fly", "flye", "pec deck", "cable crossover") {
            return weights(["chest"], ["frontDelts"])
        }
        if has("dip") { return weights(["chest", "triceps"], ["frontDelts"]) }
        if has("incline") && has("press", "bench") {
            return weights(["upperChest"], ["triceps", "frontDelts", "chest"])
        }
        if has("decline") && has("press", "bench") {
            return weights(["chest"], ["triceps", "frontDelts"])
        }
        if has("bench", "chest press", "push up", "pushup", "floor press") {
            return weights(["chest"], ["triceps", "frontDelts"])
        }
        if has("front raise") { return weights(["frontDelts"]) }

        switch normalize(muscleGroup) {
        case "chest", "pectoral", "pectorals": return weights(["chest"])
        case "back": return weights(["lats", "rhomboids"])
        case "biceps": return weights(["biceps"])
        case "triceps": return weights(["triceps"])
        case "arms": return weights(["biceps", "triceps"])
        case "shoulder", "shoulders", "deltoids": return weights(["frontDelts", "sideDelts"])
        case "legs", "quadriceps", "quads": return weights(["quads"])
        case "hamstring", "hamstrings": return weights(["hamstrings"])
        case "glutes", "glute": return weights(["glutes"])
        case "calves", "calf": return weights(["calves"])
        case "core", "abdominals", "abs": return weights(["abs"])
        case "traps", "trapezius": return weights(["traps"])
        case "forearm", "forearms": return weights(["forearms"])
        default: return [:]
        }
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

final class WeeklyMuscleActivityService {
    private let localStorage: LocalStorageService

    init(localStorage: LocalStorageService) {
        self.localStorage = localStorage
    }

    func summary(userId: UUID, now: Date = Date(), calendar: Calendar = .current) -> WeeklyMuscleActivity {
        let weekCalendar = ProgressStats.weekCalendar(calendar)
        let start = ProgressStats.weekStart(of: now, calendar: weekCalendar)
        guard let end = weekCalendar.date(byAdding: .weekOfYear, value: 1, to: start) else {
            return .empty(now: now, calendar: calendar)
        }

        let request: NSFetchRequest<CDWorkout> = CDWorkout.fetchRequest()
        request.predicate = NSPredicate(
            format: "userId == %@ AND date >= %@ AND date < %@ AND date <= %@",
            userId as CVarArg, start as CVarArg, end as CVarArg, now as CVarArg
        )
        request.relationshipKeyPathsForPrefetching = ["exercises", "exercises.sets"]

        var setsByMuscle: [String: Double] = [:]
        var completedSets = 0
        let workouts = (try? localStorage.context.fetch(request)) ?? []
        for workout in workouts {
            for exercise in (workout.exercises as? Set<CDExercise> ?? []) {
                let effective = MuscleExerciseMap.targets(
                    exerciseName: exercise.name ?? "",
                    muscleGroup: exercise.muscleGroup ?? ""
                )
                guard !effective.isEmpty else { continue }
                let loggedSets = (exercise.sets as? Set<CDWorkoutSet> ?? []).filter {
                    $0.reps > 0 && $0.recordedAt.map { $0 <= now } ?? true
                }
                completedSets += loggedSets.count
                for (muscle, coefficient) in effective {
                    setsByMuscle[muscle, default: 0] += Double(loggedSets.count) * coefficient
                }
            }
        }
        return WeeklyMuscleActivity(weekStart: start, setsByMuscle: setsByMuscle, completedSets: completedSets)
    }
}
