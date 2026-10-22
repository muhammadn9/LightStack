import Foundation
import os

/// Manages pre-workout setup state: selected split day, time available, energy level.
/// Triggers AI plan generation through WorkoutSessionService.
final class WorkoutSetupViewModel: ObservableObject {

    private let logger = Logger(subsystem: "org.lightstack.app", category: "WorkoutSetupViewModel")

    @Published var selectedWorkoutType: String = ""
    @Published var timeAvailable: Int = 45
    /// Energy on the 1-10 scale sent to the AI. The UI shows it as 1-5 dots (2 points per dot),
    /// so keep it even: the default of 8 is 4 dots, matching the "4 / 5" label.
    @Published var energyLevel: Int = 8
    @Published var additionalNotes: String = ""
    @Published var splitDays: [String] = []
    /// Past workout names not in the split (e.g. imported ones), most recent first.
    @Published var historyWorkoutNames: [String] = []
    @Published var showAllHistory = false

    /// How many history chips show before "Show all".
    static let historyChipLimit = 8

    /// Names visible given the collapsed/expanded state.
    var visibleHistoryNames: [String] {
        showAllHistory ? historyWorkoutNames : Array(historyWorkoutNames.prefix(Self.historyChipLimit))
    }

    var hasHiddenHistory: Bool { historyWorkoutNames.count > Self.historyChipLimit }

    /// Dots (1-5) that represent a 1-10 energy value; the single source for label, dots and accessibility.
    static func energyDots(for level: Int) -> Int { min(5, max(1, (level + 1) / 2)) }

    /// The 1-10 value a given dot (1-5) selects.
    static func energyLevel(forDots dots: Int) -> Int { min(5, max(1, dots)) * 2 }

    var energyDots: Int { Self.energyDots(for: energyLevel) }

    static let timePresets = [30, 45, 60, 75, 90]

    private let profileRepository: ProfileRepository
    private let validationService: ValidationService

    init(profileRepository: ProfileRepository, validationService: ValidationService) {
        self.profileRepository = profileRepository
        self.validationService = validationService
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
    func validateAndSubmit() -> (workoutType: String, time: Int, energy: Int, notes: String?)? {
        let sanitizedType = validationService.sanitize(selectedWorkoutType)
        guard !sanitizedType.isEmpty else { return nil }

        let clampedTime = validationService.sanitizeInteger(timeAvailable, min: 15, max: 120)
        let clampedEnergy = validationService.sanitizeInteger(energyLevel, min: 1, max: 10)

        let notes = additionalNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedNotes: String? = notes.isEmpty ? nil : validationService.sanitize(notes)

        return (sanitizedType, clampedTime, clampedEnergy, sanitizedNotes)
    }
}
