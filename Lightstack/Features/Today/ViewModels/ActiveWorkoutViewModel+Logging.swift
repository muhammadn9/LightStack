import Foundation

/// Logging and persistence shared by the on-screen "complete" button and the Live Activity.
extension ActiveWorkoutViewModel {

    /// Logs the pending set at `index` exactly as tapping complete does: storage and sync via
    /// `TodayViewModel.logSet`, PR flag, then the rest timer (coach-prescribed seconds first).
    @discardableResult
    func logSetAndStartRest(at index: Int, exerciseId: UUID, today: TodayViewModel,
                            startRest: Bool = true) -> Bool {
        let exercise = today.exercises.first { $0.id == exerciseId }
        guard let workoutSet = logPendingSet(at: index, exerciseId: exerciseId, exercise: exercise) else { return false }
        let isPR = today.logSet(workoutSet, exerciseId: exerciseId)

        if isPR {
            var sets = loggedSets[exerciseId] ?? []
            if var lastSet = sets.last {
                lastSet.isPR = true
                sets[sets.count - 1] = lastSet
                loggedSets[exerciseId] = sets
            }
        }

        // Strength exercises without a rest time fall back to the preferred rest. In a
        // superset only the last member's row in a round starts rest.
        if startRest,
           let plan = SupersetRounds.restPlan(afterLogging: exerciseId, in: today.exercises) {
            var seconds = plan.seconds
            let isSuperset = SupersetRounds.page(containing: exerciseId, in: today.exercises)?.isSuperset == true
            let loggedIndex = (loggedSets[exerciseId]?.count ?? 1) - 1
            if !isSuperset,
               let targets = today.setTargets[exerciseId], targets.indices.contains(loggedIndex),
               let prescribed = targets[loggedIndex].restSeconds, prescribed > 0 {
                seconds = prescribed
            }
            startRestTimer(for: exerciseId, seconds: seconds, exerciseName: plan.name)
        }
        return true
    }

    /// Saves the session (clock, unlogged rows, logged sets) so a relaunch picks up where we left off.
    func persistSession(to today: TodayViewModel) {
        syncElapsed()
        today.activeWorkoutElapsed = elapsedSeconds
        today.timerPaused = isPaused
        today.pendingSetsSnapshot = pendingSets
        today.saveSessionState()
    }
}
