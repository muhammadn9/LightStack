import Foundation

/// One exercise offered as a replacement on the plan preview.
struct SwapCandidate: Identifiable, Equatable {
    let name: String
    let muscleGroup: String
    /// True when the user has logged this lift before (shown ahead of catalog picks).
    let isFromHistory: Bool
    /// Last session's sets for this lift (empty when never logged). Filled in by the view model.
    var previous: [PreviousSetHint] = []

    var id: String { name.lowercased() }
}

/// Targets a swapped-in exercise starts with.
struct SwapPrefill: Equatable {
    var targetSets: Int?
    var targetReps: String?
    var targetRir: String?
    var coachNote: String?
    var setTargets: [SetTarget]

    /// With a last session: its set count, per-set weight x reps x RIR. Without one:
    /// the replaced exercise's set count and rep target, and no weight.
    static func make(previous: [PreviousSetHint], replacing old: Exercise) -> SwapPrefill {
        guard let first = previous.first else {
            return SwapPrefill(targetSets: old.targetSets, targetReps: old.targetReps,
                               targetRir: old.targetRir, coachNote: nil, setTargets: [])
        }
        func weightText(_ w: Double) -> String { w == 0 ? "BW" : "\(String(format: "%g", w)) lbs" }
        let targets = previous.map {
            SetTarget(weight: $0.weightLbs == 0 ? "BW" : String(format: "%g", $0.weightLbs),
                      reps: String($0.reps),
                      rir: $0.rir.map(String.init))
        }
        return SwapPrefill(
            targetSets: previous.count,
            targetReps: String(first.reps),
            targetRir: first.rir.map(String.init) ?? old.targetRir,
            coachNote: TodayViewModel.coachNote(nil, weight: weightText(first.weightLbs), note: nil),
            setTargets: targets
        )
    }
}

/// Deterministic, local "what else could I do instead" ranking. No AI.
enum ExerciseSwapSuggestions {

    /// Coarse muscle key so "Triceps" (plan) matches the catalog's "Arms / Triceps Brachii".
    static func muscleKey(group: String, name: String,
                          catalog: [CatalogExercise] = ExerciseCatalog.exercises) -> String {
        let nameKey = PersonalRecordsListView.exerciseKey(name)
        if let entry = catalog.first(where: { PersonalRecordsListView.exerciseKey($0.name) == nameKey }) {
            return key(group: entry.muscleGroup, primary: entry.primaryMuscle)
        }
        return key(group: group, primary: "")
    }

    private static func key(group: String, primary: String) -> String {
        let g = group.trimmingCharacters(in: .whitespaces).lowercased()
        let p = primary.lowercased()
        switch g {
        case "arms":
            if p.contains("tricep") { return "triceps" }
            if p.contains("bicep") || p.contains("brachioradialis") { return "biceps" }
            return "arms"
        case "bicep", "biceps": return "biceps"
        case "tricep", "triceps": return "triceps"
        case "quads", "quadriceps", "hamstrings", "glutes", "calves", "leg": return "legs"
        case "abs": return "core"
        default: return g
        }
    }

    private static func matches(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let arm: Set<String> = ["biceps", "triceps"]
        return (a == "arms" && arm.contains(b)) || (b == "arms" && arm.contains(a))
    }

    /// History first (most recent first, as given), then catalog exercises that train the
    /// same muscle, with the same primary muscle ahead of the rest. Anything already in
    /// the plan (or the exercise being replaced) is excluded.
    static func rank(
        replacing old: (name: String, muscleGroup: String),
        planNames: [String],
        history: [HistoryExercise],
        catalog: [CatalogExercise] = ExerciseCatalog.exercises,
        limit: Int = 10,
        historyLimit: Int = 6
    ) -> [SwapCandidate] {
        let target = muscleKey(group: old.muscleGroup, name: old.name, catalog: catalog)
        var excluded = Set((planNames + [old.name]).map(PersonalRecordsListView.exerciseKey))
        var result: [SwapCandidate] = []

        for item in history where result.count < historyLimit {
            let k = PersonalRecordsListView.exerciseKey(item.name)
            guard !excluded.contains(k),
                  matches(muscleKey(group: item.muscleGroup, name: item.name, catalog: catalog), target)
            else { continue }
            excluded.insert(k)
            result.append(SwapCandidate(name: item.name, muscleGroup: item.muscleGroup, isFromHistory: true))
        }

        let oldPrimary = catalog.first {
            PersonalRecordsListView.exerciseKey($0.name) == PersonalRecordsListView.exerciseKey(old.name)
        }?.primaryMuscle
        let pool = catalog.filter {
            matches(key(group: $0.muscleGroup, primary: $0.primaryMuscle), target)
        }
        let ordered = pool.filter { $0.primaryMuscle == oldPrimary } + pool.filter { $0.primaryMuscle != oldPrimary }
        for entry in ordered where result.count < limit {
            let k = PersonalRecordsListView.exerciseKey(entry.name)
            guard !excluded.contains(k) else { continue }
            excluded.insert(k)
            result.append(SwapCandidate(name: entry.name, muscleGroup: entry.muscleGroup, isFromHistory: false))
        }
        return result
    }
}
