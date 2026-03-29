import Foundation

/// Manages active workout state: current exercises, set logging,
/// timer tracking, and workout completion.
final class ActiveWorkoutViewModel: ObservableObject {

    @Published var loggedSets: [UUID: [WorkoutSet]] = [:]
    @Published var editingWeight: [UUID: String] = [:]
    @Published var editingReps: [UUID: String] = [:]
    @Published var editingRir: [UUID: String] = [:]
    @Published var elapsedSeconds: Int = 0

    private var timer: Timer?

    var formattedElapsedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func startTimer() {
        elapsedSeconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.elapsedSeconds += 1
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
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

        return workoutSet
    }

    deinit {
        stopTimer()
    }
}
