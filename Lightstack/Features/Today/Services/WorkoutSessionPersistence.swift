import Foundation

/// Handles saving and restoring workout session state
/// so users can pause workouts when switching tabs.
final class WorkoutSessionPersistence {

    private let userDefaults = UserDefaults.standard
    private let stateKey = "com.lightstack.activeWorkoutSession"

    // MARK: - Session State

    struct SessionState: Codable {
        let workout: Workout
        let exercises: [Exercise]
        let loggedSets: [UUID: [WorkoutSet]]
        let phase: String  // "active" or "postWorkout"
        let startTime: Date
        let userNote: String?
        let elapsedSeconds: Int

        var isActive: Bool {
            // Session is considered stale after 24 hours
            Date().timeIntervalSince(startTime) < 24 * 60 * 60
        }
    }

    // MARK: - Save

    func saveSession(
        workout: Workout,
        exercises: [Exercise],
        loggedSets: [UUID: [WorkoutSet]],
        phase: TodayPhase,
        userNote: String?,
        elapsedSeconds: Int = 0
    ) {
        let phaseString: String
        switch phase {
        case .active:
            phaseString = "active"
        case .postWorkout:
            phaseString = "postWorkout"
        default:
            // Don't save setup or generating phases
            return
        }

        let state = SessionState(
            workout: workout,
            exercises: exercises,
            loggedSets: loggedSets,
            phase: phaseString,
            startTime: workout.createdAt,
            userNote: userNote,
            elapsedSeconds: elapsedSeconds
        )

        do {
            let data = try JSONEncoder().encode(state)
            userDefaults.set(data, forKey: stateKey)
            print("[WorkoutSessionPersistence] Saved session state")
        } catch {
            print("[WorkoutSessionPersistence] Failed to save state: \(error)")
        }
    }

    // MARK: - Restore

    func restoreSession() -> SessionState? {
        guard let data = userDefaults.data(forKey: stateKey) else {
            return nil
        }

        do {
            let state = try JSONDecoder().decode(SessionState.self, from: data)
            if state.isActive {
                print("[WorkoutSessionPersistence] Restored active session")
                return state
            } else {
                // Stale session, clear it
                clearSession()
                print("[WorkoutSessionPersistence] Cleared stale session")
                return nil
            }
        } catch {
            print("[WorkoutSessionPersistence] Failed to decode state: \(error)")
            return nil
        }
    }

    // MARK: - Clear

    func clearSession() {
        userDefaults.removeObject(forKey: stateKey)
        print("[WorkoutSessionPersistence] Cleared session state")
    }

    // MARK: - Check

    func hasActiveSession() -> Bool {
        restoreSession() != nil
    }
}
