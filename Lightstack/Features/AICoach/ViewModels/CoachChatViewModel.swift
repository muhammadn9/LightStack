import Foundation

/// Manages ephemeral chat state: message list, sending user messages,
/// receiving AI responses, and clearing on session end.
final class CoachChatViewModel: ObservableObject {

    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var inputText = ""
    @Published var pendingModifications: [WorkoutModification] = []
    @Published var showModificationConfirmation = false
    /// True when the latest modification batch has low confidence and needs explicit user confirmation
    /// even though the user initiated the conversation (i.e., do NOT pre-apply).
    @Published var requiresExplicitConfirmation = false

    private let aiServiceManager: AIServiceManager
    private let coachPromptService: CoachPromptService
    private let coachContextBuilder: CoachContextBuilder
    private let validationService: ValidationService
    private let modificationParser = WorkoutModificationParser()
    let intentService: OnDeviceIntentService

    private var userId: UUID?
    private var workoutType: String?
    private var systemPrompt: String = ""
    private var currentExercises: [Exercise] = []
    private var currentLoggedSets: [UUID: [WorkoutSet]] = [:]

    init(
        aiServiceManager: AIServiceManager,
        coachPromptService: CoachPromptService,
        coachContextBuilder: CoachContextBuilder,
        validationService: ValidationService,
        intentService: OnDeviceIntentService = OnDeviceIntentService()
    ) {
        self.aiServiceManager = aiServiceManager
        self.coachPromptService = coachPromptService
        self.coachContextBuilder = coachContextBuilder
        self.validationService = validationService
        self.intentService = intentService
    }

    /// Configure chat with current workout context.
    func configure(userId: UUID, workoutType: String, exercises: [Exercise], loggedSets: [UUID: [WorkoutSet]]) {
        self.userId = userId
        self.workoutType = workoutType
        self.currentExercises = exercises
        self.currentLoggedSets = loggedSets

        let context = coachContextBuilder.buildContext(userId: userId, workoutType: workoutType)
        systemPrompt = coachPromptService.buildSystemPrompt(profile: context.profile) + """

        WORKOUT MODIFICATIONS
        You can suggest modifications to the current workout if the athlete asks.
        Use these special commands in your response:

        [ADD] Exercise Name | Muscle Group | Sets | Reps | RIR | Rest | Note
        [REMOVE] Exercise Name
        [MODIFY] Exercise Name | Sets | Reps | RIR | Rest | Note
        [REPLACE] Old Name → New Name | Muscle Group | Sets | Reps | RIR | Rest | Note

        Always explain WHY you're suggesting the change before the command.
        The athlete will be asked to confirm before any changes are applied.
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

        // Snapshot for async capture
        let capturedText = text

        aiServiceManager.generateChat(
            systemPrompt: systemPrompt,
            messages: messages
        ) { [weak self] result in
            guard let self = self else { return }
            self.isLoading = false

            switch result {
            case .success(let responseText):
                let coachMessage = ChatMessage(role: .coach, content: responseText)
                self.messages.append(coachMessage)

                // Use on-device intent classification + structured extraction when available;
                // fall back to the pipe-delimited parser otherwise.
                if self.intentService.isAvailable {
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        await self.handleModificationsOnDevice(userMessage: capturedText, responseText: responseText)
                    }
                } else {
                    self.handleModificationsFallback(responseText: responseText, requireConfirmation: false)
                }

            case .failure(let error):
                let errorMessage = ChatMessage(role: .coach, content: "Sorry, I couldn't respond right now. Please try again. (\(error.localizedDescription))")
                self.messages.append(errorMessage)
            }
        }
    }

    // MARK: - Private modification helpers

    @MainActor
    private func handleModificationsOnDevice(userMessage: String, responseText: String) async {
        // Step 1: classify intent — skip extraction if not a modification request.
        let classification: IntentClassification
        do {
            classification = try await intentService.classify(userMessage)
        } catch {
            // Intent check failed; fall back to parser without extra confirmation.
            handleModificationsFallback(responseText: responseText, requireConfirmation: false)
            return
        }

        guard classification.intent == .modificationRequest else {
            // Not a modification request — nothing to extract.
            return
        }

        let lowConfidence = classification.confidence < OnDeviceIntentService.confidenceThreshold

        // Step 2: structured extraction via guided generation.
        do {
            let mods = try await intentService.extractModifications(from: responseText)
            guard !mods.isEmpty else { return }
            pendingModifications = mods
            requiresExplicitConfirmation = lowConfidence
            showModificationConfirmation = true
        } catch {
            // Extraction failed — fall back to pipe parser, but honour low-confidence flag.
            handleModificationsFallback(responseText: responseText, requireConfirmation: lowConfidence)
        }
    }

    private func handleModificationsFallback(responseText: String, requireConfirmation: Bool) {
        let mods = modificationParser.parse(responseText)
        guard !mods.isEmpty else { return }
        pendingModifications = mods
        requiresExplicitConfirmation = requireConfirmation
        showModificationConfirmation = true
    }

    /// Called when user confirms modifications.
    func confirmModifications(applyTo todayViewModel: TodayViewModel) {
        for modification in pendingModifications {
            todayViewModel.applyModification(modification, preserveLoggedSets: true)
        }
        pendingModifications = []
        showModificationConfirmation = false
        requiresExplicitConfirmation = false
    }

    /// Called when user rejects modifications.
    func rejectModifications() {
        pendingModifications = []
        showModificationConfirmation = false
        requiresExplicitConfirmation = false
    }

    /// Clear all messages when leaving the workout.
    func clearChat() {
        messages = []
        inputText = ""
        isLoading = false
        pendingModifications = []
        showModificationConfirmation = false
        requiresExplicitConfirmation = false
    }
}
