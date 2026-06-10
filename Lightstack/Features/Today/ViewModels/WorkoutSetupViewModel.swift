import Foundation
import os

/// Manages pre-workout setup state: selected split day, time available, energy level.
/// Triggers AI plan generation through WorkoutSessionService.
final class WorkoutSetupViewModel: ObservableObject {

    private let logger = Logger(subsystem: "org.lightstack.app", category: "WorkoutSetupViewModel")

    @Published var selectedWorkoutType: String = ""
    @Published var timeAvailable: Int = 45
    @Published var energyLevel: Int = 7
    @Published var additionalNotes: String = ""
    @Published var splitDays: [String] = []

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
