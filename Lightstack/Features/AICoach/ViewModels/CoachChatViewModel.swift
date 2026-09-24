import Foundation

/// Manages ephemeral chat state: message list, sending user messages,
/// receiving AI responses, and clearing on session end.
final class CoachChatViewModel: ObservableObject {

    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var inputText = ""
    @Published var pendingModifications: [WorkoutModification] = []
    @Published var showModificationConfirmation = false

    private let aiServiceManager: AIServiceManager
    private let coachPromptService: CoachPromptService
    private let coachContextBuilder: CoachContextBuilder
    private let validationService: ValidationService
    private let modificationParser = WorkoutModificationParser()
    private let jsonParser = WorkoutModificationJSONParser()

    private var userId: UUID?
    private var workoutType: String?
    private var systemPrompt: String = ""
    private var currentExercises: [Exercise] = []
    private var currentLoggedSets: [UUID: [WorkoutSet]] = [:]

    init(
        aiServiceManager: AIServiceManager,
        coachPromptService: CoachPromptService,
        coachContextBuilder: CoachContextBuilder,
        validationService: ValidationService
    ) {
        self.aiServiceManager = aiServiceManager
        self.coachPromptService = coachPromptService
        self.coachContextBuilder = coachContextBuilder
        self.validationService = validationService
    }

    /// Configure chat with current workout context.
    func configure(userId: UUID, workoutType: String, exercises: [Exercise], loggedSets: [UUID: [WorkoutSet]]) {
        self.userId = userId
        self.workoutType = workoutType
        self.currentExercises = exercises
        self.currentLoggedSets = loggedSets

        let context = coachContextBuilder.buildContext(userId: userId, workoutType: workoutType)
        systemPrompt = coachPromptService.buildSystemPrompt(
            profile: context.profile,
            includeWorkoutPlanFormat: false
        ) + """

        WORKOUT MODIFICATIONS
        You can suggest modifications to the current workout if the athlete asks.
        Always explain WHY you are suggesting the change in natural language first.
        The athlete will be asked to confirm before any changes are applied.

        If — and only if — you are suggesting modifications, append a single fenced \
        JSON code block at the very end of your response using this exact schema:

        ```json
        {
          "modifications": [
            {
              "action": "add",
              "name": "Exercise Name",
              "muscle_group": "Muscle Group",
              "target_sets": 3,
              "target_reps": "8-10",
              "target_rir": "2",
              "rest_seconds": 90,
              "note": "Optional note"
            },
            {
              "action": "remove",
              "name": "Exercise Name"
            },
            {
              "action": "modify",
              "name": "Exercise Name",
              "new_target_sets": 4,
              "new_target_reps": "6-8",
              "new_target_rir": "1",
              "new_rest": 120,
              "note": "Optional note"
            },
            {
              "action": "replace",
              "old_name": "Old Exercise",
              "new_name": "New Exercise",
              "muscle_group": "Muscle Group",
              "target_sets": 3,
              "target_reps": "8-10",
              "target_rir": "2",
              "rest_seconds": 90,
              "note": "Optional note"
            }
          ]
        }
        ```

        Rules:
        - Include only the modifications you are actually suggesting (any mix of actions).
        - Omit optional fields (target_reps, target_rir, rest_seconds, note, new_*) when not relevant.
        - If you are NOT suggesting any modifications, omit the JSON block entirely.
        - Do NOT include the JSON block for general questions or advice without workout changes.
        """

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

        aiServiceManager.generateChat(
            systemPrompt: systemPrompt,
            messages: messages,
            expectsJSON: false
        ) { [weak self] result in
            guard let self = self else { return }
            self.isLoading = false

            switch result {
            case .success(let responseText):
                // Strip JSON before displaying to the user. If that leaves
                // nothing, the reply was JSON end to end — show a sentence
                // rather than an empty bubble.
                var displayText = self.jsonParser.strippingJSONBlock(from: responseText)
                if displayText.isEmpty {
                    displayText = "Here's what I'd change for this session."
                }
                let coachMessage = ChatMessage(role: .coach, content: displayText)
                self.messages.append(coachMessage)

                // Parse modifications: try JSON parser first, fall back to pipe parser
                let modifications: [WorkoutModification]
                var extractionFailed = false
                do {
                    let jsonModifications = try self.jsonParser.parse(responseText)
                    if !jsonModifications.isEmpty {
                        modifications = jsonModifications
                    } else {
                        // No JSON block found — try legacy pipe format
                        modifications = self.modificationParser.parse(responseText)
                    }
                } catch {
                    // Malformed JSON block — fall back to legacy pipe parser
                    modifications = self.modificationParser.parse(responseText)
                    extractionFailed = true
                }

                if !modifications.isEmpty {
                    self.pendingModifications = modifications
                    self.showModificationConfirmation = true
                } else if extractionFailed {
                    // The coach described changes but we couldn't read them. Say so
                    // rather than leaving the athlete waiting for a prompt that
                    // will never appear.
                    self.messages.append(ChatMessage(
                        role: .coach,
                        content: "I couldn't apply those changes automatically — please adjust the workout manually, or ask me again."
                    ))
                }
            case .failure(let error):
                let errorMessage = ChatMessage(role: .coach, content: "Sorry, I couldn't respond right now. Please try again. (\(error.localizedDescription))")
                self.messages.append(errorMessage)
            }
        }
    }

    /// Called when user confirms modifications.
    func confirmModifications(applyTo todayViewModel: TodayViewModel) {
        for modification in pendingModifications {
            todayViewModel.applyModification(modification, preserveLoggedSets: true)
        }
        pendingModifications = []
        showModificationConfirmation = false
    }

    /// Called when user rejects modifications.
    func rejectModifications() {
        pendingModifications = []
        showModificationConfirmation = false
    }

    /// Clear all messages when leaving the workout.
    func clearChat() {
        messages = []
        inputText = ""
        isLoading = false
        pendingModifications = []
        showModificationConfirmation = false
    }
}
