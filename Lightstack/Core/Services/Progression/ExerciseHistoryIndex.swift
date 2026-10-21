import Foundation

/// All logged history of one exercise, name variants merged ("Smith Bench" / "Smith Machine Bench").
struct ExerciseHistoryGroup {
    /// Variant names, newest session first.
    var names: [String]
    /// Newest first.
    var sessions: [HistorySession]
    /// Best set on record, when known.
    var best: HistorySet?

    var displayName: String { names.first ?? "" }
}

/// Recent same-type sessions regrouped per exercise. Built from `CoachContext` data.
struct ExerciseHistoryIndex {
    private(set) var groups: [ExerciseHistoryGroup] = []

    init() {}

    init(groups: [ExerciseHistoryGroup]) { self.groups = groups }

    /// - Parameters:
    ///   - sessions: newest first.
    ///   - bestSets: best set per lowercased exercise name.
    init(
        sessions: [Workout],
        exercises: [UUID: [Exercise]],
        loggedSets: [UUID: [WorkoutSet]],
        bestSets: [String: (weightLbs: Double, reps: Int)]
    ) {
        var built: [ExerciseHistoryGroup] = []
        for workout in sessions {
            for ex in exercises[workout.id] ?? [] where ex.trackingType != .cardio {
                let sets = (loggedSets[ex.id] ?? []).sorted { $0.setNumber < $1.setNumber }
                    .map { HistorySet($0.weightLbs, $0.reps, rir: $0.rir) }
                guard !sets.isEmpty else { continue }
                let index = built.firstIndex { group in
                    group.names.contains { ExerciseNameResolver.isMatch($0, ex.name) }
                }
                if let i = index {
                    if !built[i].names.contains(ex.name) { built[i].names.append(ex.name) }
                    if let s = built[i].sessions.firstIndex(where: { $0.date == workout.date }) {
                        built[i].sessions[s].sets += sets
                    } else {
                        built[i].sessions.append(HistorySession(date: workout.date, sets: sets))
                    }
                } else {
                    built.append(ExerciseHistoryGroup(
                        names: [ex.name],
                        sessions: [HistorySession(date: workout.date, sets: sets)],
                        best: nil
                    ))
                }
            }
        }
        for i in built.indices {
            let recorded = built[i].names.compactMap { bestSets[$0.lowercased()] }
                .map { HistorySet($0.weightLbs, $0.reps) }
                .max { $0.e1RM < $1.e1RM }
            built[i].best = recorded ?? Self.bestLogged(in: built[i].sessions)
        }
        groups = built
    }

    func group(for name: String) -> ExerciseHistoryGroup? {
        groups.first { $0.names.contains { ExerciseNameResolver.isMatch($0, name) } }
    }

    /// Heaviest-e1RM working set across sessions (fallback when no personal record is known).
    static func bestLogged(in sessions: [HistorySession]) -> HistorySet? {
        sessions.flatMap { SetStyleDetector.splitWarmups($0.sets).working }
            .filter { $0.weight > 0 }
            .max { $0.e1RM < $1.e1RM }
    }

    /// Compact one-line trend, oldest to newest, for the AI prompt, e.g.
    /// "10/03 200×3 top · 10/16 230×1 top, 180×6 · 10/20 185×6,185×6,180×5".
    static func trendLine(for sessions: [HistorySession], dateText: (Date) -> String) -> String {
        sessions.reversed().map { session in
            let work = SetStyleDetector.splitWarmups(session.sets).working
            let top = work.map(\.weight).max()
            let parts = work.map { s -> String in
                let base = "\(String(format: "%g", s.weight))×\(s.reps)"
                return work.count > 1 && s.weight == top && SetStyleDetector.classify(working: work) != .straightSets
                    ? base + " top" : base
            }
            return "\(dateText(session.date)) " + parts.joined(separator: ",")
        }.joined(separator: " · ")
    }
}
