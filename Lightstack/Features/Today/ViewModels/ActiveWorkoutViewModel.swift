import Foundation

/// One pending (not-yet-logged) set for an exercise, with editable fields.
struct PendingSetInput: Identifiable {
    var id = UUID()
    var weight: String
    var reps: String
    var rir: String
}

/// Manages active workout state: current exercises, set logging,
/// timer tracking, and workout completion.
final class ActiveWorkoutViewModel: ObservableObject {

    @Published var loggedSets: [UUID: [WorkoutSet]] = [:]
    /// Per-exercise array of pending sets (shown as individual editable rows).
    @Published var pendingSets: [UUID: [PendingSetInput]] = [:]
    // Legacy single-set editing fields kept for any remaining callers.
    @Published var editingWeight: [UUID: String] = [:]
    @Published var editingReps: [UUID: String] = [:]
    @Published var editingRir: [UUID: String] = [:]
    @Published var editingNote: [UUID: String] = [:]
    @Published var restTimers: [UUID: Int] = [:]    // exerciseId → seconds remaining
    @Published var activeRestExerciseId: UUID? = nil
    @Published var elapsedSeconds: Int = 0
    @Published var isPaused: Bool = false

    private var timer: Timer?
    private var restTimerClock: Timer?

    /// Called when a rest timer starts. Parameters: exerciseName, totalRestSeconds
    var onRestTimerStart: ((String, Int) -> Void)?
    /// Called when a rest timer completes or is cancelled
    var onRestTimerCancel: (() -> Void)?

    var formattedElapsedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func startTimer(from initialSeconds: Int = 0) {
        elapsedSeconds = initialSeconds
        isPaused = false
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.elapsedSeconds += 1 }
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func pauseTimer() {
        isPaused = true
        timer?.invalidate()
        timer = nil
    }

    func resumeTimer() {
        isPaused = false
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.elapsedSeconds += 1 }
        }
    }

    func togglePause() {
        isPaused ? resumeTimer() : pauseTimer()
    }

    /// Parse editing fields, create WorkoutSet, return it for logging.
    func buildSet(exerciseId: UUID) -> WorkoutSet? {
        guard let repsStr = editingReps[exerciseId],
              let reps = Int(repsStr),
              reps > 0
        else { return nil }

        let weightStr = editingWeight[exerciseId] ?? ""
        let weight: Double
        if weightStr.isEmpty || weightStr.uppercased() == "BW" {
            weight = 0.0
        } else if let w = Double(weightStr), w >= 0 {
            weight = w
        } else {
            return nil
        }

        let rir = Int(editingRir[exerciseId] ?? "2") ?? 2
        let existingSets = loggedSets[exerciseId] ?? []
        let setNumber = existingSets.count + 1

        let workoutSet = WorkoutSet.create(
            exerciseId: exerciseId,
            setNumber: setNumber,
            weightLbs: weight,
            reps: reps,
            rir: rir
        )

        // Add to local state
        var sets = existingSets
        sets.append(workoutSet)
        loggedSets[exerciseId] = sets

        // Clear editing fields
        editingWeight[exerciseId] = ""
        editingReps[exerciseId] = ""
        editingRir[exerciseId] = ""
        editingNote[exerciseId] = ""

        return workoutSet
    }

    // MARK: - Prefill Targets

    /// Pre-fill input fields with AI-suggested targets for an exercise (only if empty).
    /// Also initialises the per-set pending rows via syncPendingSets.
    func prefillTargets(for exercise: Exercise) {
        if editingWeight[exercise.id]?.isEmpty ?? true {
            editingWeight[exercise.id] = prefillWeightValue(from: exercise)
        }
        if editingReps[exercise.id]?.isEmpty ?? true {
            editingReps[exercise.id] = prefillRepsValue(from: exercise)
        }
        if editingRir[exercise.id]?.isEmpty ?? true {
            editingRir[exercise.id] = prefillRirValue(from: exercise)
        }
        syncPendingSets(for: exercise)
    }

    /// Reset legacy single-set fields after logging (carries forward last logged values).
    func resetToTargets(for exercise: Exercise) {
        if let lastSet = loggedSets[exercise.id]?.last {
            editingWeight[exercise.id] = lastSet.weightLbs == 0 ? "BW" : String(format: "%g", lastSet.weightLbs)
            editingReps[exercise.id] = String(lastSet.reps)
            editingRir[exercise.id] = String(lastSet.rir)
            editingNote[exercise.id] = ""
        } else {
            editingWeight[exercise.id] = nil
            editingReps[exercise.id] = nil
            editingRir[exercise.id] = nil
            editingNote[exercise.id] = ""
            prefillTargets(for: exercise)
        }
    }

    func deleteSet(_ workoutSet: WorkoutSet, exerciseId: UUID) {
        loggedSets[exerciseId]?.removeAll { $0.id == workoutSet.id }
    }

    // MARK: - Pending Sets (all-sets-visible model)

    /// Ensures pendingSets[exercise.id] has exactly (targetSets - loggedSets) entries,
    /// pre-filled with AI targets or last-logged values.
    func syncPendingSets(for exercise: Exercise) {
        let loggedCount = loggedSets[exercise.id]?.count ?? 0
        let targetCount = exercise.targetSets ?? 0
        let needed = max(0, targetCount - loggedCount)

        var current = pendingSets[exercise.id] ?? []

        while current.count < needed {
            let last = loggedSets[exercise.id]?.last
            current.append(PendingSetInput(
                weight: last.map { $0.weightLbs == 0 ? "BW" : String(format: "%g", $0.weightLbs) }
                    ?? prefillWeightValue(from: exercise),
                reps: last.map { String($0.reps) } ?? prefillRepsValue(from: exercise),
                rir: last.map { String($0.rir) } ?? prefillRirValue(from: exercise)
            ))
        }
        if current.count > needed {
            current = Array(current.prefix(needed))
        }
        pendingSets[exercise.id] = current
    }

    /// Log the pending set at `index`, add it to loggedSets, and remove it from pendingSets.
    func logPendingSet(at index: Int, exerciseId: UUID) -> WorkoutSet? {
        guard var pending = pendingSets[exerciseId], index < pending.count else { return nil }

        let entry = pending[index]
        let weight: Double
        if entry.weight.isEmpty || entry.weight.uppercased() == "BW" {
            weight = 0.0
        } else if let w = Double(entry.weight), w >= 0 {
            weight = w
        } else {
            return nil
        }
        guard let reps = Int(entry.reps), reps > 0 else { return nil }
        let rir = Int(entry.rir) ?? 2

        let existingSets = loggedSets[exerciseId] ?? []
        let setNumber = existingSets.count + 1

        let workoutSet = WorkoutSet.create(
            exerciseId: exerciseId,
            setNumber: setNumber,
            weightLbs: weight,
            reps: reps,
            rir: rir
        )

        var logged = existingSets
        logged.append(workoutSet)
        loggedSets[exerciseId] = logged

        pending.remove(at: index)
        pendingSets[exerciseId] = pending

        return workoutSet
    }

    /// Add one extra pending set pre-filled from the last logged set (or AI target).
    func addPendingSet(for exercise: Exercise) {
        let last = loggedSets[exercise.id]?.last
        let entry = PendingSetInput(
            weight: last.map { $0.weightLbs == 0 ? "BW" : String(format: "%g", $0.weightLbs) }
                ?? prefillWeightValue(from: exercise),
            reps: last.map { String($0.reps) } ?? prefillRepsValue(from: exercise),
            rir: last.map { String($0.rir) } ?? prefillRirValue(from: exercise)
        )
        pendingSets[exercise.id, default: []].append(entry)
    }

    // MARK: - Private prefill helpers

    private func prefillWeightValue(from exercise: Exercise) -> String {
        guard let note = exercise.coachNote else { return "" }
        let cleaned = note.replacingOccurrences(of: "Target: ", with: "")
        let upper = cleaned.uppercased()
        if upper.contains("BW") || upper.contains("BODYWEIGHT") { return "BW" }
        let parts = cleaned.components(separatedBy: " ")
        if let first = parts.first, Double(first) != nil { return first }
        return ""
    }

    private func prefillRepsValue(from exercise: Exercise) -> String {
        guard let reps = exercise.targetReps,
              let range = reps.range(of: #"\d+"#, options: .regularExpression)
        else { return "" }
        return String(reps[range])
    }

    private func prefillRirValue(from exercise: Exercise) -> String {
        guard let rir = exercise.targetRir,
              let range = rir.range(of: #"\d+"#, options: .regularExpression)
        else { return "2" }
        return String(rir[range])
    }

    // MARK: - Rest Timer

    /// Start a rest countdown timer for an exercise.
    func startRestTimer(for exerciseId: UUID, seconds: Int, exerciseName: String = "") {
        onRestTimerCancel?()  // cancel any existing notification
        restTimerClock?.invalidate()
        restTimerClock = nil
        restTimers[exerciseId] = seconds
        activeRestExerciseId = exerciseId

        restTimerClock = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            DispatchQueue.main.async {
                let current = self.restTimers[exerciseId] ?? 0
                if current <= 1 {
                    self.restTimers[exerciseId] = 0
                    self.activeRestExerciseId = nil
                    t.invalidate()
                    self.restTimerClock = nil
                    self.onRestTimerCancel?()  // timer expired naturally
                } else {
                    self.restTimers[exerciseId] = current - 1
                }
            }
        }

        onRestTimerStart?(exerciseName, seconds)  // schedule new notification
    }

    func formattedRestTime(for exerciseId: UUID) -> String? {
        guard let remaining = restTimers[exerciseId], remaining > 0 else { return nil }
        let minutes = remaining / 60
        let seconds = remaining % 60
        return minutes > 0 ? "\(minutes):\(String(format: "%02d", seconds))" : "\(seconds)s"
    }

    deinit {
        stopTimer()
        restTimerClock?.invalidate()
    }
}
