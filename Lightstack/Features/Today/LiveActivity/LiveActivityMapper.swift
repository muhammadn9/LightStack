import Foundation

/// Pure mapping from the active session to Live Activity content, plus the -/+ step rules.
/// Kept free of ActivityKit so it can be unit tested.
enum LiveActivityMapper {

    /// The next set the athlete will do: the first pending row in page order.
    struct CurrentSet: Equatable {
        let exerciseId: UUID
        /// Index into `pendingSets[exerciseId]`.
        let pendingIndex: Int
    }

    static func currentSet(exercises: [Exercise],
                           loggedSets: [UUID: [WorkoutSet]],
                           pendingSets: [UUID: [PendingSetInput]]) -> CurrentSet? {
        pendingRows(exercises: exercises, loggedSets: loggedSets, pendingSets: pendingSets).first
    }

    private static func pendingRows(exercises: [Exercise],
                                    loggedSets: [UUID: [WorkoutSet]],
                                    pendingSets: [UUID: [PendingSetInput]]) -> [CurrentSet] {
        var result: [CurrentSet] = []
        for page in SupersetGroup.pages(from: exercises) {
            let rows = SupersetRounds.rows(memberIds: page.exerciseIds, logged: loggedSets, pending: pendingSets)
            for row in rows {
                if case .pending(let index) = row.kind {
                    result.append(CurrentSet(exerciseId: row.exerciseId, pendingIndex: index))
                }
            }
        }
        return result
    }

    static func setKey(exerciseId: UUID, loggedCount: Int) -> String {
        "\(exerciseId.uuidString):\(loggedCount)"
    }

    /// Builds the Live Activity content for the session as it stands right now.
    static func contentState(
        exercises: [Exercise],
        loggedSets: [UUID: [WorkoutSet]],
        pendingSets: [UUID: [PendingSetInput]],
        setTargets: [UUID: [SetTarget]],
        activeRestExerciseId: UUID?,
        restTargetDates: [UUID: Date],
        elapsedSeconds: Int,
        isPaused: Bool,
        unit: String,
        now: Date = Date()
    ) -> LightstackWorkoutAttributes.ContentState {
        let anchor = now.addingTimeInterval(-TimeInterval(elapsedSeconds))
        var restEnd: Date?
        if let id = activeRestExerciseId, let target = restTargetDates[id], target > now {
            restEnd = target
        }

        let rows = pendingRows(exercises: exercises, loggedSets: loggedSets, pendingSets: pendingSets)
        guard let current = rows.first, let exercise = exercises.first(where: { $0.id == current.exerciseId }),
              let entry = pendingSets[current.exerciseId]?[safeIndex: current.pendingIndex] else {
            return .init(exerciseName: "", setKey: "", setNumber: 0, totalSets: 0, setLabel: nil,
                         weightText: "", unit: unit, reps: 0, rir: nil, isCardio: false, cardioText: nil,
                         canLog: false, nextExercise: nil, restEndDate: restEnd, elapsedAnchor: anchor,
                         isPaused: isPaused, pausedElapsedSeconds: elapsedSeconds, allDone: true)
        }

        let loggedCount = loggedSets[exercise.id]?.count ?? 0
        let pendingCount = pendingSets[exercise.id]?.count ?? 0
        let overallIndex = loggedCount + current.pendingIndex
        let isCardio = exercise.trackingType == .cardio

        var label: String?
        if !isCardio, let target = setTargets[exercise.id]?[safeIndex: overallIndex] {
            let role = target.resolvedRole
            label = role == .straight ? nil : role.label
        }

        var weightText = ""
        var reps = 0
        var rir: Int?
        var cardioText: String?
        var canLog = false
        if isCardio {
            canLog = !entry.duration.isEmpty
            let parts = [entry.duration, entry.distance.isEmpty ? nil : "\(entry.distance) mi"].compactMap { $0 }
            cardioText = parts.isEmpty ? nil : parts.joined(separator: " · ")
        } else if let resolved = ActiveWorkoutViewModel.resolveStrength(
            weight: entry.weight, reps: entry.reps, rir: entry.rir, previous: entry.previous) {
            weightText = weightString(resolved.weight)
            reps = resolved.reps
            rir = resolved.rir
            canLog = true
        }

        let next = rows.first(where: { $0.exerciseId != current.exerciseId })
            .flatMap { row in exercises.first(where: { $0.id == row.exerciseId })?.name }

        return .init(
            exerciseName: exercise.name,
            setKey: setKey(exerciseId: exercise.id, loggedCount: loggedCount),
            setNumber: overallIndex + 1,
            totalSets: loggedCount + pendingCount,
            setLabel: label,
            weightText: weightText, unit: unit, reps: reps, rir: rir,
            isCardio: isCardio, cardioText: cardioText, canLog: canLog,
            nextExercise: next, restEndDate: restEnd, elapsedAnchor: anchor,
            isPaused: isPaused, pausedElapsedSeconds: elapsedSeconds, allDone: false
        )
    }

    // MARK: - Steps

    /// "135", "62.5", or "BW" for zero.
    static func weightString(_ weight: Double) -> String {
        weight <= 0 ? "BW" : String(format: "%g", weight)
    }

    /// Weight after one -/+ press: one plate step (5 barbell/machine, 2.5 dumbbell/cable), never below 0.
    static func steppedWeight(_ current: Double, exerciseName: String, direction: Int) -> Double {
        let step = ExerciseTraits.roundingStep(exerciseName)
        let next = current + Double(direction) * step
        return max(0, (next * 100).rounded() / 100)
    }

    /// Reps after one -/+ press, kept within 0...100.
    static func steppedReps(_ current: Int, direction: Int) -> Int {
        min(100, max(0, current + direction))
    }
}

private extension Array {
    subscript(safeIndex index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
