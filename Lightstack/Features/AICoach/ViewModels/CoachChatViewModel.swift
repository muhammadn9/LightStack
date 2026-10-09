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
    private var knownExerciseNames: [String] = []

    /// How many recent messages (after the workout-context message) go to the AI.
    static let historyWindow = 6

    /// The context message plus the last few messages. The full history stays on screen.
    static func windowedMessages(_ messages: [ChatMessage], window: Int = historyWindow) -> [ChatMessage] {
        guard messages.count > window + 1, let context = messages.first else { return messages }
        return [context] + messages.suffix(window)
    }

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
        systemPrompt = coachPromptService.buildSystemPrompt(profile: context.profile, task: .chat)

        // Names the athlete could swap in without asking the AI: their recent history
        // plus the built-in catalog.
        var names = Set(ExerciseCatalog.exercises.map(\.name))
        for list in context.recentSessionSets.values { list.forEach { names.insert($0.name) } }
        knownExerciseNames = names.sorted()

        // Add workout context as an initial system-like context message
        if messages.isEmpty {
            let supersetTags = Self.supersetTags(for: exercises)
            var contextInfo = "Current workout: \(workoutType)\n\nExercises:"
            for exercise in exercises {
                let sets = loggedSets[exercise.id] ?? []
                contextInfo += "\n- \(exercise.name) (\(exercise.muscleGroup))"
                if let tag = supersetTags[exercise.id] { contextInfo += " [\(tag)]" }
                if let target = exercise.targetSets {
                    contextInfo += " — Target: \(target) sets"
                }
                if !sets.isEmpty {
                    contextInfo += " — Logged: \(sets.count) sets"
                    if let lastSet = sets.last {
                        contextInfo += " (last: \(String(format: "%.0f", lastSet.weightLbs)) lbs x \(lastSet.reps) @ \(lastSet.rir.map { "RIR \($0)" } ?? "RIR not recorded"))"
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

        // Simple, unambiguous commands are handled locally: no AI call.
        if let command = LocalChatCommandParser.parse(text, exercises: currentExercises, knownNames: knownExerciseNames) {
            messages.append(ChatMessage(role: .coach, content: command.reply))
            pendingModifications = command.modifications
            showModificationConfirmation = true
            return
        }

        isLoading = true

        aiServiceManager.generateChat(
            systemPrompt: systemPrompt,
            messages: Self.windowedMessages(messages),
            expectsJSON: false,
            options: .forTask(.chat)
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
                } else if extractionFailed || Self.containsMarkdownTable(responseText) {
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

    /// "Superset A", "Superset B"... per exercise id, for valid supersets only.
    static func supersetTags(for exercises: [Exercise]) -> [UUID: String] {
        var tags: [UUID: String] = [:]
        var letter = 0
        for page in SupersetGroup.pages(from: exercises) where page.isSuperset {
            let name = "Superset \(Character(UnicodeScalar(UInt8(65 + letter % 26))))"
            letter += 1
            page.exerciseIds.forEach { tags[$0] = name }
        }
        return tags
    }

    /// True when the reply contains a markdown table separator row (`|---|---|`).
    /// A table means the coach laid out a plan in prose only — nothing reached
    /// the workout — so we surface that instead of silently doing nothing.
    static func containsMarkdownTable(_ text: String) -> Bool {
        text.components(separatedBy: .newlines).contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.contains("|"), trimmed.contains("-") else { return false }
            return trimmed.allSatisfy { "|-: ".contains($0) }
        }
    }

    /// Called when user confirms modifications.
    func confirmModifications(applyTo todayViewModel: TodayViewModel) {
        var applied: [WorkoutModification] = []
        var missing: [String] = []
        for modification in pendingModifications {
            if todayViewModel.applyModification(modification, preserveLoggedSets: true) {
                applied.append(modification)
            } else if let name = modification.targetExerciseName {
                missing.append(name)
            }
        }
        // Keep local command matching in step with the workout after changes.
        currentExercises = todayViewModel.exercises
        // Never silent: say in the chat what changed, and what couldn't be found.
        var lines: [String] = []
        if !applied.isEmpty { lines.append(Self.confirmationText(for: applied)) }
        if !missing.isEmpty {
            lines.append("Couldn't find \(missing.joined(separator: ", ")) in this workout, so nothing changed for it.")
        }
        if !lines.isEmpty {
            messages.append(ChatMessage(role: .coach, content: lines.joined(separator: "\n")))
        }
        pendingModifications = []
        showModificationConfirmation = false
    }

    /// Chat text confirming applied modifications, one line each.
    static func confirmationText(for modifications: [WorkoutModification]) -> String {
        modifications.map(\.appliedSummary).joined(separator: "\n")
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
