import Foundation

/// Remembers, per exercise name, whether the lift is logged "per arm" (single-side), so the
/// toggle defaults to the last value used the next time the same lift appears. Names are
/// grouped with `ExerciseNameResolver`, so "Cable Row" and "Seated Cable Rows" share a value.
enum PerArmPreference {
    static let key = "lightstack.perArmPreferences.v1"

    private static let suggestPhrases = ["single arm", "single-arm", "one arm", "one-arm", "unilateral", "alternating"]

    /// True when the name itself says the lift is done one side at a time.
    static func suggestsPerArm(_ name: String) -> Bool {
        let lower = name.lowercased()
        return suggestPhrases.contains { lower.contains($0) }
    }

    /// Last value the user chose for this lift, else the name-based suggestion.
    static func defaultValue(for name: String, defaults: UserDefaults = .standard) -> Bool {
        let groupKey = ExerciseNameResolver.groupKey(name)
        if let stored = (defaults.dictionary(forKey: key) as? [String: Bool])?[groupKey] {
            return stored
        }
        return suggestsPerArm(name)
    }

    static func remember(_ value: Bool, for name: String, defaults: UserDefaults = .standard) {
        var stored = (defaults.dictionary(forKey: key) as? [String: Bool]) ?? [:]
        stored[ExerciseNameResolver.groupKey(name)] = value
        defaults.set(stored, forKey: key)
    }
}
