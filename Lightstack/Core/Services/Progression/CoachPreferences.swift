import Foundation

/// What the athlete is training for. Drives rep ranges and rest in `ProgressionEngine`.
enum CoachFocus: String, Codable, CaseIterable, Equatable {
    case hypertrophy, strength, maintenance

    var title: String {
        switch self {
        case .hypertrophy: return "Muscle"
        case .strength: return "Strength"
        case .maintenance: return "Maintain"
        }
    }

    /// Best guess from free-text profile goals; nil when the goals say nothing obvious.
    static func infer(fromGoals goals: [String]) -> CoachFocus? {
        let text = goals.joined(separator: " ").lowercased()
        guard !text.isEmpty else { return nil }
        let muscle = ["muscle", "hypertrophy", "size", "bulk", "mass", "physique", "aesthetic"]
        if muscle.contains(where: { text.contains($0) }) { return .hypertrophy }
        if text.contains("strength") || text.contains("stronger") || text.contains("powerlift") { return .strength }
        if text.contains("maintain") || text.contains("maintenance") { return .maintenance }
        return nil
    }
}

/// Coach settings kept in UserDefaults (no schema change). Hands-off by default:
/// nothing here has to be set for the coach to work.
enum CoachPreferences {
    static let focusKey = "coach.focus"
    /// Neutral energy used when the athlete does not say how they feel.
    static let neutralEnergy = 6
    /// Session length used when there is no history and no profile default.
    static let fallbackMinutes = 45

    /// The explicitly chosen focus, if any.
    static func storedFocus(in defaults: UserDefaults = .standard) -> CoachFocus? {
        defaults.string(forKey: focusKey).flatMap(CoachFocus.init(rawValue:))
    }

    /// Hypertrophy unless the athlete picked something else.
    static var focus: CoachFocus {
        get { storedFocus() ?? .hypertrophy }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: focusKey) }
    }

    static func setFocus(_ focus: CoachFocus?, in defaults: UserDefaults = .standard) {
        if let focus { defaults.set(focus.rawValue, forKey: focusKey) } else { defaults.removeObject(forKey: focusKey) }
    }

    /// Request override > stored preference > profile goals > hypertrophy.
    static func resolvedFocus(override: CoachFocus? = nil, profileGoals: [String] = [],
                              in defaults: UserDefaults = .standard) -> CoachFocus {
        override ?? storedFocus(in: defaults) ?? CoachFocus.infer(fromGoals: profileGoals) ?? .hypertrophy
    }
}
