import Foundation

/// Generates AI coaching feedback from a FormAnalysisResult using the existing AIServiceManager.
final class FormFeedbackService {

    private let aiServiceManager: AIServiceManager

    init(aiServiceManager: AIServiceManager) {
        self.aiServiceManager = aiServiceManager
    }

    // MARK: - Public

    func generateFeedback(
        for result: FormAnalysisResult,
        completion: @escaping (Result<FormAnalysisResult, Error>) -> Void
    ) {
        let messages: [ChatMessage] = [
            ChatMessage(role: .user, content: Self.buildUserPrompt(from: result))
        ]

        aiServiceManager.generateChat(
            systemPrompt: Self.systemPrompt,
            messages: messages
        ) { aiResult in
            switch aiResult {
            case .success(let text):
                var updated = result
                updated.aiCoachText = text
                completion(.success(updated))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Prompt Construction (internal for testing)

    static let systemPrompt = """
    You are an expert strength and conditioning coach analyzing exercise form \
    captured via smartphone pose estimation. You receive structured data about \
    rep count, range of motion, symmetry, and detected form issues.

    Provide 3-5 sentences of direct, actionable coaching feedback:
    1. What was done well overall
    2. The most important form issue to fix (if any)
    3. One specific cue to improve the next set

    Be concise and encouraging. Reference specific rep numbers if relevant.
    """

    static func buildUserPrompt(from result: FormAnalysisResult) -> String {
        """
        Exercise: \(result.exerciseName)
        Total reps detected: \(result.repCount)
        Good reps: \(result.goodRepCount)/\(result.repCount)

        Per-rep breakdown:
        \(result.repSummaryForPrompt())

        Please provide your coaching feedback.
        """
    }
}
