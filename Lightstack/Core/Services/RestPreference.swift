import Foundation

/// The athlete's preferred rest between sets, set in Settings ("Default Rest Timer").
enum RestPreference {
    /// UserDefaults / @AppStorage key shared with `SettingsView`.
    static let key = "defaultRestSeconds"
    /// Used when the preference was never set.
    static let fallbackSeconds = 90

    static var defaultSeconds: Int { defaultSeconds(in: .standard) }

    static func defaultSeconds(in defaults: UserDefaults) -> Int {
        let value = defaults.integer(forKey: key)
        return value > 0 ? value : fallbackSeconds
    }

    /// Rest to store on a newly created exercise. Strength stores nothing: an exercise whose rest nobody
    /// prescribed (plan, coach, engine or an explicit chat value) always follows the CURRENT Settings
    /// default, so changing it mid-workout applies (see `ActiveWorkoutView.restSeconds(for:)`).
    /// Anything else (cardio) keeps whatever it had.
    static func storedSeconds(forMuscleGroup muscleGroup: String, existing: Int? = nil) -> Int? {
        muscleGroup.caseInsensitiveCompare("Cardio") == .orderedSame ? existing : nil
    }

    /// UserDefaults key for the default the running workout last reconciled against.
    static let lastAppliedKey = "defaultRestSecondsLastApplied"

    /// Exercises that still carry `stamped` (an old default written onto them when they were created, or
    /// restored from a session saved before defaults stopped being stamped) and have no per-set rest
    /// prescribed lose it, so they follow the live default. Strength only. Returns the changed exercises.
    static func releasingStampedRest(_ exercises: [Exercise], stamped: Int,
                                     setTargets: [UUID: [SetTarget]]) -> [Exercise] {
        exercises.compactMap { exercise in
            guard exercise.restSeconds == stamped,
                  exercise.trackingType == .strength,
                  !(setTargets[exercise.id] ?? []).contains(where: { ($0.restSeconds ?? 0) > 0 }) else { return nil }
            var released = exercise
            released.restSeconds = nil
            return released
        }
    }
}
