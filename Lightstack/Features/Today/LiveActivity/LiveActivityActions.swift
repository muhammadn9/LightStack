import Foundation

/// What the Live Activity buttons do to the real session. Operates on the same
/// view models the workout screen uses, so persistence, sync and the rest timer
/// behave exactly as if the athlete had tapped in the app.
enum LiveActivityActions {

    /// Applies `action` to the set identified by `setKey`. Returns false when nothing
    /// changed (no current set, a stale tap on an older render, or a row that can't log).
    @discardableResult
    static func apply(_ action: LiveActivityAction, setKey: String,
                      active: ActiveWorkoutViewModel, today: TodayViewModel) -> Bool {
        if action == .skipRest {
            guard active.activeRestExerciseId != nil else { return false }
            active.cancelAllRestTimers()
            return true
        }

        guard let current = LiveActivityMapper.currentSet(
            exercises: today.exercises, loggedSets: active.loggedSets, pendingSets: active.pendingSets),
              let exercise = today.exercises.first(where: { $0.id == current.exerciseId }),
              var rows = active.pendingSets[current.exerciseId],
              rows.indices.contains(current.pendingIndex) else { return false }

        let loggedCount = active.loggedSets[current.exerciseId]?.count ?? 0
        guard LiveActivityMapper.setKey(exerciseId: current.exerciseId, loggedCount: loggedCount) == setKey else {
            return false
        }

        let entry = rows[current.pendingIndex]
        switch action {
        case .logSet:
            let ready = ActiveWorkoutViewModel.isReadyToLog(entry, trackingType: exercise.trackingType)
            guard ready else { return false }
            return active.logSetAndStartRest(at: current.pendingIndex, exerciseId: current.exerciseId, today: today)

        case .weightUp, .weightDown, .repsUp, .repsDown:
            guard exercise.trackingType != .cardio,
                  let resolved = ActiveWorkoutViewModel.resolveStrength(
                    weight: entry.weight, reps: entry.reps, rir: entry.rir, previous: entry.previous) else { return false }
            let direction = (action == .weightUp || action == .repsUp) ? 1 : -1
            if action == .weightUp || action == .weightDown {
                let weight = LiveActivityMapper.steppedWeight(resolved.weight, exerciseName: exercise.name, direction: direction)
                rows[current.pendingIndex].weight = LiveActivityMapper.weightString(weight)
            } else {
                rows[current.pendingIndex].reps = String(LiveActivityMapper.steppedReps(resolved.reps, direction: direction))
            }
            // Pin RIR too, so a blank field does not drift when the hint changes.
            if rows[current.pendingIndex].rir.isEmpty, let rir = resolved.rir {
                rows[current.pendingIndex].rir = String(rir)
            }
            active.pendingSets[current.exerciseId] = rows
            return true

        case .skipRest:
            return false
        }
    }
}
