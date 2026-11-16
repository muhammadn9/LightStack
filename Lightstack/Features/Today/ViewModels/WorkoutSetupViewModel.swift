import Foundation
import os

/// Manages pre-workout setup state: selected split day, time available, energy level.
/// Triggers AI plan generation through WorkoutSessionService.
final class WorkoutSetupViewModel: ObservableObject {

    private let logger = Logger(subsystem: "org.lightstack.app", category: "WorkoutSetupViewModel")

    @Published var selectedWorkoutType: String = ""
    /// Minutes available. Remembered between launches.
    @Published var timeAvailable: Int = 45 {
        didSet { defaults.set(timeAvailable, forKey: Self.timeKey) }
    }
    /// Energy on the 1-10 scale sent to the AI. The UI shows it as 1-5 dots (2 points per dot),
    /// so keep it even: the default of 8 is 4 dots, matching the "4 of 5" label. Remembered between launches.
    @Published var energyLevel: Int = 8 {
        didSet { defaults.set(energyLevel, forKey: Self.energyKey) }
    }
    @Published var additionalNotes: String = ""
    /// Optional: "incline smith taken, fasted, knee tweak". Sent to the coach with the request.
    @Published var constraints: String = ""
    /// Training focus; hypertrophy unless the athlete (or their profile goals) say otherwise.
    @Published var focus: CoachFocus = CoachPreferences.resolvedFocus()
    /// Which settings row is open inline, if any.
    @Published var expandedRow: SettingsRow?

    enum SettingsRow: String {
        case energy, time, notes
    }

    func toggleRow(_ row: SettingsRow) {
        expandedRow = expandedRow == row ? nil : row
    }

    static let energyKey = "setup.energyLevel"
    static let timeKey = "setup.timeAvailable"

    /// Remembers the athlete's choice for next time.
    func chooseFocus(_ newFocus: CoachFocus) {
        focus = newFocus
        CoachPreferences.setFocus(newFocus)
    }
    @Published var splitDays: [String] = []
    /// Past workout names not in the split (e.g. imported ones), most recent first.
    @Published var historyWorkoutNames: [String] = []

    /// The split days followed by past workout names that are not split days (case-insensitive).
    /// Every chip goes through the coach, whichever list it came from.
    var chips: [String] {
        Self.chips(splitDays: splitDays, historyNames: historyWorkoutNames)
    }

    static func chips(splitDays: [String], historyNames: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in splitDays + historyNames {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            result.append(name)
        }
        return result
    }

    /// "4 of 5"
    var energySummary: String { "\(energyDots) of 5" }

    /// "45 min"
    var timeSummary: String { "\(timeAvailable) min" }

    /// What the notes row shows when closed: "None", or what was filled in.
    var notesSummary: String {
        var parts: [String] = []
        let notes = additionalNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { parts.append(notes) }
        if !constraints.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append("Constraints") }
        if focus != .hypertrophy { parts.append(Self.focusTitle(focus)) }
        return parts.isEmpty ? "None" : parts.joined(separator: " · ")
    }

    static func focusTitle(_ focus: CoachFocus) -> String {
        switch focus {
        case .hypertrophy: return "Hypertrophy"
        case .strength: return "Strength"
        case .maintenance: return "Maintenance"
        }
    }

    /// Dots (1-5) that represent a 1-10 energy value; the single source for label, dots and accessibility.
    static func energyDots(for level: Int) -> Int { min(5, max(1, (level + 1) / 2)) }

    /// The 1-10 value a given dot (1-5) selects.
    static func energyLevel(forDots dots: Int) -> Int { min(5, max(1, dots)) * 2 }

    var energyDots: Int { Self.energyDots(for: energyLevel) }

    static let timePresets = [30, 45, 60, 75, 90]

    private let profileRepository: ProfileRepository
    private let validationService: ValidationService

    private let defaults: UserDefaults

    init(profileRepository: ProfileRepository, validationService: ValidationService,
         defaults: UserDefaults = .standard) {
        self.profileRepository = profileRepository
        self.validationService = validationService
        self.defaults = defaults
        if let energy = defaults.object(forKey: Self.energyKey) as? Int {
            energyLevel = Self.energyLevel(forDots: Self.energyDots(for: energy))
        }
        if let time = defaults.object(forKey: Self.timeKey) as? Int, (15...120).contains(time) {
            timeAvailable = time
        }
    }

    func loadSplitDays(userId: UUID) {
        logger.debug("Loading split days for user: \(userId)")
        if let profile = profileRepository.fetchProfileSync(userId: userId) {
            logger.debug("Profile found with split days: \(profile.splitDays)")
            splitDays = profile.splitDays
            if selectedWorkoutType.isEmpty, let first = splitDays.first {
                selectedWorkoutType = first
            }
        } else {
            logger.error("No profile found for user")
        }
    }

    /// Validate and return sanitized inputs, or nil if invalid.
    func validateAndSubmit() -> (workoutType: String, time: Int, energy: Int, notes: String?, constraints: String?, focus: CoachFocus?)? {
        let sanitizedType = validationService.sanitize(selectedWorkoutType)
        guard !sanitizedType.isEmpty else { return nil }

        let clampedTime = validationService.sanitizeInteger(timeAvailable, min: 15, max: 120)
        let clampedEnergy = validationService.sanitizeInteger(energyLevel, min: 1, max: 10)

        let notes = additionalNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedNotes: String? = notes.isEmpty ? nil : validationService.sanitize(notes)

        let rawConstraints = constraints.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedConstraints: String? = rawConstraints.isEmpty ? nil : validationService.sanitize(rawConstraints)
        // Only an explicit choice overrides the stored preference / profile goals.
        let chosenFocus: CoachFocus? = CoachPreferences.storedFocus() == nil && focus == CoachPreferences.resolvedFocus()
            ? nil : focus

        return (sanitizedType, clampedTime, clampedEnergy, sanitizedNotes, sanitizedConstraints, chosenFocus)
    }
}
