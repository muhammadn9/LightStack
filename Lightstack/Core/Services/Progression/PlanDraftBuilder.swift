import Foundation

/// One exercise of the engine's draft plan: the app's numbers for a lift with history.
struct DraftExercise: Equatable {
    var name: String
    var muscleGroup: String
    var result: ProgressionResult
    /// What the engine was given, so a coach decision can rebuild the lift around another top set.
    var input: ProgressionInput? = nil
    var isPerArm: Bool = false
    /// True when this lift was the one that got rule-based warm-ups in the draft.
    var allowedWarmups: Bool = false
}

/// The engine's full draft for the next session of a workout type, built from the last
/// same-type session's exercise list. The coach decides on it; the app turns decisions into sets.
enum PlanDraftBuilder {

    static func build(
        lastSessionExercises: [Exercise],
        history: ExerciseHistoryIndex,
        energy: Int,
        feedback: SessionFeedback?,
        coach: PlanCoachContext,
        timeMinutes: Int?
    ) -> [DraftExercise] {
        var ordered: [Exercise] = []
        for ex in lastSessionExercises.sorted(by: { $0.orderIndex < $1.orderIndex }) where ex.trackingType != .cardio {
            if !ordered.contains(where: { ExerciseNameResolver.isMatch($0.name, ex.name) }) { ordered.append(ex) }
        }
        if let moved = heavyFirst(ordered) { ordered = moved.exercises }
        let warmupIndexes = Set(ordered.indices.filter { ExerciseTraits.classify(ordered[$0].name) == .heavyCompound }.prefix(1))

        var draft: [DraftExercise] = []
        for (i, ex) in ordered.enumerated() {
            guard let group = history.group(for: ex.name) else { continue }
            let input = engineInput(name: ex.name, muscleGroup: ex.muscleGroup, group: group, energy: energy,
                                    feedback: feedback, coach: coach, allowWarmups: warmupIndexes.contains(i))
            if let result = ProgressionEngine.plan(input) {
                draft.append(DraftExercise(name: ex.name, muscleGroup: ex.muscleGroup, result: result, input: input,
                                           isPerArm: ex.isPerArm, allowedWarmups: warmupIndexes.contains(i)))
            }
        }
        // Fit the available time: drop trailing exercises, but keep the first two.
        if let limit = timeMinutes {
            while draft.count > 2, estimatedMinutes(draft) > Double(limit) * 1.1 { draft.removeLast() }
        }
        return draft
    }

    /// The engine's input for one lift of one session: everything but a coach decision's top-set override.
    static func engineInput(name: String, muscleGroup: String, group: ExerciseHistoryGroup, energy: Int,
                            feedback: SessionFeedback?, coach: PlanCoachContext, allowWarmups: Bool) -> ProgressionInput {
        let muscle = MuscleGroups.canonical(forExercise: name, muscleGroup: muscleGroup)
        return ProgressionInput(
            name: name, sessions: group.sessions, best: group.capBest,
            feedback: group.sessions.first?.feedback ?? feedback, energy: energy,
            allowWarmups: allowWarmups, focus: coach.focus, restPreference: coach.restPreference,
            nextTarget: coach.nextTarget(for: name, lastSessionDate: group.sessions.first?.date),
            recentlyTrained: coach.isFresh(muscle: muscle),
            now: coach.now, lastSameTypeSessionDate: group.latestSessionDate,
            muscleVeryRecent: coach.isVeryRecent(muscle: muscle),
            fuelLow: coach.fuelHold?.isLow ?? false, fuelReason: coach.fuelHold?.primaryReason,
            increments: WeightIncrements.learned(name: name, group: group))
    }

    /// The session-level heads-up for the requested workout (nil when its muscles are rested).
    static func recencyWarning(for draft: [DraftExercise], coach: PlanCoachContext) -> RecencyWarning? {
        coach.recencyWarning(forLifts: draft.map { ($0.name, $0.muscleGroup) })
    }

    /// Rough session length: 40 s of work per set plus the prescribed rest, and a few minutes of setup.
    static func estimatedMinutes(_ draft: [DraftExercise]) -> Double {
        let seconds = draft.flatMap(\.result.sets).reduce(0) { $0 + 40 + $1.restSeconds }
        return Double(seconds) / 60 + 3
    }

    /// Stable reorder with heavy compounds first. nil when nothing needs to move or supersets are present.
    static func heavyFirst(_ exercises: [Exercise]) -> (exercises: [Exercise], names: [String])? {
        guard exercises.allSatisfy({ $0.supersetGroupId == nil }) else { return nil }
        let isHeavy: (Exercise) -> Bool = { ExerciseTraits.classify($0.name) == .heavyCompound }
        // Only act when a heavy compound sits behind an isolation exercise.
        guard let firstIso = exercises.firstIndex(where: { ExerciseTraits.classify($0.name) == .isolation }),
              exercises[firstIso...].contains(where: isHeavy) else { return nil }
        let heavy = exercises.filter(isHeavy)
        let rest = exercises.filter { !isHeavy($0) }
        let moved = exercises[firstIso...].filter(isHeavy).map(\.name)
        return (heavy + rest, moved)
    }
}
