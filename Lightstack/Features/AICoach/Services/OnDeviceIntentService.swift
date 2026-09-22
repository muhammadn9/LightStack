import Foundation
import FoundationModels

// MARK: - Intent classification result

/// The intent classifier's verdict on a user chat message.
enum ModificationIntent {
    /// The message asks for a workout modification (e.g. add/remove/swap/change an exercise).
    case modificationRequest
    /// The message is general coaching chat (questions, feedback, etc.).
    case generalChat
}

/// Result returned by `OnDeviceIntentService`.
struct IntentClassification {
    let intent: ModificationIntent
    /// 0.0 … 1.0.  Values below `OnDeviceIntentService.confidenceThreshold` mean the
    /// caller should surface the suggestion but require explicit user confirmation.
    let confidence: Double
}

// MARK: - Errors

enum OnDeviceIntentError: Error, LocalizedError {
    case modelUnavailable(SystemLanguageModel.Availability.UnavailableReason)
    case generationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason):
            return "On-device model unavailable: \(reason)"
        case .generationFailed(let underlying):
            return "Generation failed: \(underlying.localizedDescription)"
        }
    }
}

enum ExtractionError: Error, LocalizedError {
    case modelUnavailable
    case generationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "On-device model unavailable; falling back to text parser."
        case .generationFailed(let underlying):
            return "Structured extraction failed: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - Generable types for structured extraction

/// Mirrors `WorkoutModification.addExercise`.
@Generable(description: "An exercise to add to the workout")
struct GenerableAddExercise {
    @Guide(description: "Exercise name")
    var name: String
    @Guide(description: "Primary muscle group targeted")
    var muscleGroup: String
    @Guide(description: "Number of sets", .minimum(1), .maximum(20))
    var targetSets: Int
    @Guide(description: "Target reps, e.g. '8-10' or '5'")
    var targetReps: String?
    @Guide(description: "Target RIR (reps in reserve), e.g. '2'")
    var targetRir: String?
    @Guide(description: "Rest in seconds between sets", .minimum(0), .maximum(600))
    var restSeconds: Int?
    @Guide(description: "Optional coaching note")
    var note: String?
}

/// Mirrors `WorkoutModification.removeExercise`.
@Generable(description: "An exercise to remove from the workout")
struct GenerableRemoveExercise {
    @Guide(description: "Exercise name to remove")
    var name: String
}

/// Mirrors `WorkoutModification.modifyExercise`.
@Generable(description: "Modifications to an existing exercise")
struct GenerableModifyExercise {
    @Guide(description: "Exercise name to modify")
    var name: String
    @Guide(description: "New number of sets", .minimum(1), .maximum(20))
    var newTargetSets: Int?
    @Guide(description: "New target reps, e.g. '8-10'")
    var newTargetReps: String?
    @Guide(description: "New RIR, e.g. '2'")
    var newTargetRir: String?
    @Guide(description: "New rest in seconds", .minimum(0), .maximum(600))
    var newRest: Int?
    @Guide(description: "Optional coaching note")
    var note: String?
}

/// Mirrors `WorkoutModification.replaceExercise`.
@Generable(description: "Replace one exercise with another")
struct GenerableReplaceExercise {
    @Guide(description: "Name of the exercise to replace")
    var oldName: String
    @Guide(description: "Name of the replacement exercise")
    var newName: String
    @Guide(description: "Primary muscle group of the new exercise")
    var muscleGroup: String
    @Guide(description: "Number of sets for the new exercise", .minimum(1), .maximum(20))
    var targetSets: Int
    @Guide(description: "Target reps, e.g. '8-10'")
    var targetReps: String?
    @Guide(description: "Target RIR, e.g. '2'")
    var targetRir: String?
    @Guide(description: "Rest in seconds", .minimum(0), .maximum(600))
    var restSeconds: Int?
    @Guide(description: "Optional coaching note")
    var note: String?
}

/// The top-level container the model fills during structured extraction.
@Generable(description: "All workout modifications found in an AI response")
struct GenerableWorkoutModifications {
    @Guide(description: "Exercises to add (may be empty)")
    var additions: [GenerableAddExercise]
    @Guide(description: "Exercises to remove (may be empty)")
    var removals: [GenerableRemoveExercise]
    @Guide(description: "Exercises to modify (may be empty)")
    var modifications: [GenerableModifyExercise]
    @Guide(description: "Exercises to replace (may be empty)")
    var replacements: [GenerableReplaceExercise]
}

// MARK: - On-device intent classification result (Generable)

@Generable(description: "Result of classifying whether a user message requests a workout modification")
struct GenerableIntentResult {
    @Guide(description: "true if the user is requesting a workout modification, false otherwise")
    var isModificationRequest: Bool
    @Guide(
        description: "Confidence from 0.0 to 1.0 that the classification is correct",
        .minimum(0.0),
        .maximum(1.0)
    )
    var confidence: Double
}

// MARK: - Service

/// Classifies user intent and extracts structured workout modifications
/// using Apple's on-device FoundationModels framework.
///
/// Inject this type and check `isAvailable` before calling any async methods.
/// All methods degrade gracefully when the model is unavailable.
final class OnDeviceIntentService {

    // MARK: - Configuration

    /// Below this confidence level the caller should surface the modification
    /// suggestion but NOT auto-apply it — require explicit user confirmation.
    ///
    /// Chosen at 0.75: low enough to catch clearly-worded but brief requests
    /// ("swap squats for leg press"), high enough to exclude off-topic queries
    /// whose keyword overlap is coincidental.
    static let confidenceThreshold: Double = 0.75

    // MARK: - Availability

    private let model: SystemLanguageModel

    /// Whether Apple Intelligence / the on-device model is ready to use.
    var isAvailable: Bool {
        model.availability == .available
    }

    /// Raw availability value for callers that want to surface a reason.
    var availability: SystemLanguageModel.Availability {
        model.availability
    }

    // MARK: - Init

    init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    // MARK: - Intent classification

    /// Classify whether `message` is a workout-modification request.
    /// Throws `OnDeviceIntentError.modelUnavailable` if Apple Intelligence is off.
    func classify(_ message: String) async throws -> IntentClassification {
        guard isAvailable else {
            if case .unavailable(let reason) = model.availability {
                throw OnDeviceIntentError.modelUnavailable(reason)
            }
            throw OnDeviceIntentError.modelUnavailable(.appleIntelligenceNotEnabled)
        }

        let session = LanguageModelSession(
            model: model,
            instructions: """
            You are a fitness coach assistant intent classifier. \
            Decide if the user's message is requesting a workout modification \
            (add, remove, swap, or change an exercise or its parameters). \
            Set isModificationRequest to true only when the message clearly asks \
            for a structural change to the workout program.
            """
        )

        let prompt = "Classify this user message: \"\(message)\""

        do {
            let response = try await session.respond(
                to: prompt,
                generating: GenerableIntentResult.self
            )
            let result = response.content
            let intent: ModificationIntent = result.isModificationRequest ? .modificationRequest : .generalChat
            return IntentClassification(intent: intent, confidence: result.confidence)
        } catch {
            throw OnDeviceIntentError.generationFailed(error)
        }
    }

    // MARK: - Structured extraction

    /// Extract `WorkoutModification` values from `responseText` using guided generation.
    /// Throws `ExtractionError` on failure — the caller should fall back to
    /// `WorkoutModificationParser` when this throws.
    func extractModifications(from responseText: String) async throws -> [WorkoutModification] {
        guard isAvailable else {
            throw ExtractionError.modelUnavailable
        }

        let session = LanguageModelSession(
            model: model,
            instructions: """
            You are a structured data extractor. Given an AI fitness coach response, \
            extract all workout modification commands (add, remove, modify, replace). \
            Return empty arrays for categories with no modifications. \
            Preserve all numeric and text values exactly as stated.
            """
        )

        let prompt = """
        Extract all workout modifications from the following AI coach response:

        \(responseText)
        """

        do {
            let response = try await session.respond(
                to: prompt,
                generating: GenerableWorkoutModifications.self
            )
            return mapToWorkoutModifications(response.content)
        } catch {
            throw ExtractionError.generationFailed(error)
        }
    }

    // MARK: - Private mapping

    private func mapToWorkoutModifications(_ generable: GenerableWorkoutModifications) -> [WorkoutModification] {
        var result: [WorkoutModification] = []

        for add in generable.additions {
            result.append(.addExercise(
                name: add.name,
                muscleGroup: add.muscleGroup,
                targetSets: add.targetSets,
                targetReps: add.targetReps,
                targetRir: add.targetRir,
                restSeconds: add.restSeconds,
                note: add.note
            ))
        }

        for remove in generable.removals {
            result.append(.removeExercise(name: remove.name))
        }

        for modify in generable.modifications {
            result.append(.modifyExercise(
                name: modify.name,
                newTargetSets: modify.newTargetSets,
                newTargetReps: modify.newTargetReps,
                newTargetRir: modify.newTargetRir,
                newRest: modify.newRest,
                note: modify.note
            ))
        }

        for replace in generable.replacements {
            result.append(.replaceExercise(
                oldName: replace.oldName,
                newName: replace.newName,
                muscleGroup: replace.muscleGroup,
                targetSets: replace.targetSets,
                targetReps: replace.targetReps,
                targetRir: replace.targetRir,
                restSeconds: replace.restSeconds,
                note: replace.note
            ))
        }

        return result
    }
}
