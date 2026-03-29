import Foundation

/// Manages ephemeral chat state: message list, sending user messages,
/// receiving AI responses, and clearing on session end.
final class CoachChatViewModel: ObservableObject {

    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var inputText = ""

    private let geminiService: GeminiService
    private let coachPromptService: CoachPromptService
    private let coachContextBuilder: CoachContextBuilder
    private let validationService: ValidationService

    private var userId: UUID?
    private var workoutType: String?
    private var systemPrompt: String = ""

    init(
        geminiService: GeminiService,
        coachPromptService: CoachPromptService,
        coachContextBuilder: CoachContextBuilder,
        validationService: ValidationService
    ) {
        self.geminiService = geminiService
        self.coachPromptService = coachPromptService
        self.coachContextBuilder = coachContextBuilder
        self.validationService = validationService
    }

    /// Configure chat with current workout context.
    func configure(userId: UUID, workoutType: String, exercises: [Exercise], loggedSets: [UUID: [WorkoutSet]]) {
        self.userId = userId
        self.workoutType = workoutType

        let context = coachContextBuilder.buildContext(userId: userId, workoutType: workoutType)
        systemPrompt = coachPromptService.buildSystemPrompt(profile: context.profile)

        // Add workout context as an initial system-like context message
        if messages.isEmpty {
            var contextInfo = "Current workout: \(workoutType)\n\nExercises:"
            for exercise in exercises {
                let sets = loggedSets[exercise.id] ?? []
                contextInfo += "\n- \(exercise.name) (\(exercise.muscleGroup))"
                if let target = exercise.targetSets {
                    contextInfo += " — Target: \(target) sets"
                }
                if !sets.isEmpty {
                    contextInfo += " — Logged: \(sets.count) sets"
                    if let lastSet = sets.last {
                        contextInfo += " (last: \(String(format: "%.0f", lastSet.weightLbs)) lbs x \(lastSet.reps) @ RIR \(lastSet.rir))"
                    }
                }
            }

            if let summary = context.rollingSummary {
                contextInfo += "\n\nRecent history: \(summary)"
            }

            // Store the workout context internally — we'll prepend it to the first message
            let contextMessage = ChatMessage(role: .user, content: contextInfo)
            let coachGreeting = ChatMessage(role: .coach, content: "I can see your current session. What would you like to know about your workout?")
            messages = [contextMessage, coachGreeting]
        }
    }

    /// Send a user message and get AI response.
    func sendMessage() {
        let text = validationService.sanitize(inputText)
        guard !text.isEmpty, !isLoading else { return }

        inputText = ""
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        isLoading = true

        geminiService.generateChatAsync(
            systemPrompt: systemPrompt,
            messages: messages
        ) { [weak self] result in
            guard let self = self else { return }
            self.isLoading = false

            switch result {
            case .success(let responseText):
                let coachMessage = ChatMessage(role: .coach, content: responseText)
                self.messages.append(coachMessage)
            case .failure(let error):
                let errorMessage = ChatMessage(role: .coach, content: "Sorry, I couldn't respond right now. Please try again. (\(error.localizedDescription))")
                self.messages.append(errorMessage)
            }
        }
    }

    /// Clear all messages when leaving the workout.
    func clearChat() {
        messages = []
        inputText = ""
        isLoading = false
    }
}
