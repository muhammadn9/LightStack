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

    /// Rest to store on a newly created exercise: strength takes the preference,
    /// anything else (cardio) keeps whatever it had.
    static func seconds(forMuscleGroup muscleGroup: String, existing: Int? = nil,
                        in defaults: UserDefaults = .standard) -> Int? {
        muscleGroup.caseInsensitiveCompare("Cardio") == .orderedSame
            ? existing
            : defaultSeconds(in: defaults)
    }
}
