import Foundation

/// Manages active workout state: current exercises, set logging,
/// timer tracking, and workout completion.
final class ActiveWorkoutViewModel: ObservableObject {

    @Published var loggedSets: [UUID: [WorkoutSet]] = [:]
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
        guard let weightStr = editingWeight[exerciseId],
              let weight = Double(weightStr),
              weight > 0,
              let repsStr = editingReps[exerciseId],
              let reps = Int(repsStr),
              reps > 0
        else {
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
    func prefillTargets(for exercise: Exercise) {
        if editingWeight[exercise.id]?.isEmpty ?? true {
            if let note = exercise.coachNote {
                // coachNote format: "Target: 135 lbs" or "Target: 135"
                let parts = note.replacingOccurrences(of: "Target: ", with: "").components(separatedBy: " ")
                if let first = parts.first, Double(first) != nil {
                    editingWeight[exercise.id] = first
                }
            }
        }
        if editingReps[exercise.id]?.isEmpty ?? true {
            if let reps = exercise.targetReps,
               let range = reps.range(of: #"\d+"#, options: .regularExpression) {
                editingReps[exercise.id] = String(reps[range])
            }
        }
        if editingRir[exercise.id]?.isEmpty ?? true {
            if let rir = exercise.targetRir,
               let range = rir.range(of: #"\d+"#, options: .regularExpression) {
                editingRir[exercise.id] = String(rir[range])
            }
        }
    }

    /// Reset fields to AI targets after logging a set (ready for next set).
    func resetToTargets(for exercise: Exercise) {
        editingWeight[exercise.id] = nil
        editingReps[exercise.id] = nil
        editingRir[exercise.id] = nil
        editingNote[exercise.id] = nil
        prefillTargets(for: exercise)
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
