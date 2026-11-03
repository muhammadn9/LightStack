import Foundation

// MARK: - Thread persistence

/// A chat message as saved on the phone.
struct StoredChatMessage: Codable, Equatable {
    var id: UUID
    var isCoach: Bool
    var content: String
    var timestamp: Date

    init(_ message: ChatMessage) {
        id = message.id
        isCoach = message.role == .coach
        content = message.content
        timestamp = message.timestamp
    }

    var message: ChatMessage {
        ChatMessage(id: id, role: isCoach ? .coach : .user, content: content, timestamp: timestamp)
    }
}

/// One workout's coach conversation (everything after the hidden context message).
struct StoredChatThread: Codable, Equatable {
    var messages: [StoredChatMessage]
    /// The coach's plan message has been added to this thread.
    var planSeeded: Bool
    /// The post-workout review has been added to this thread.
    var reviewAppended: Bool
    var updatedAt: Date
}

/// Keeps each workout's coach thread locally (UserDefaults JSON keyed by workout id), capped:
/// the newest few threads, the newest messages of each, long messages shortened.
final class CoachThreadStore {
    static let shared = CoachThreadStore()
    static let defaultsKey = "coach.chat.threads"
    static let maxThreads = 12
    static let maxMessages = 60
    static let maxCharacters = 3000

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func thread(forWorkout id: UUID) -> StoredChatThread? {
        load()[id.uuidString]
    }

    func save(_ thread: StoredChatThread, forWorkout id: UUID) {
        var capped = thread
        capped.messages = Array(thread.messages.suffix(Self.maxMessages)).map { message in
            var copy = message
            if copy.content.count > Self.maxCharacters {
                copy.content = String(copy.content.prefix(Self.maxCharacters)) + "…"
            }
            return copy
        }
        var all = load()
        all[id.uuidString] = capped
        if all.count > Self.maxThreads {
            let oldest = all.sorted { $0.value.updatedAt < $1.value.updatedAt }
                .prefix(all.count - Self.maxThreads).map(\.key)
            oldest.forEach { all[$0] = nil }
        }
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    func removeAll() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    private func load() -> [String: StoredChatThread] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let all = try? JSONDecoder().decode([String: StoredChatThread].self, from: data) else { return [:] }
        return all
    }
}

// MARK: - Plan seed

/// What the coach said about a workout, used to open its chat thread: the plan message
/// (summary, notes, each exercise's reason and targets) and, later, the post-workout review.
struct ThreadSeed: Equatable {
    struct Item: Equatable {
        var name: String
        var reason: String?
        var railFallback: Bool
        /// "95x8 warm-up, 135x8 @RIR2, 135x8 @RIR1"
        var targets: String
        /// "3 sets, top 135x8"
        var compact: String
    }

    var workoutId: UUID
    var summary: String?
    var notes: String?
    var items: [Item]
    var reviewText: String?

    /// The coach's opening message of the thread. nil when there are no exercises.
    var planMessage: String? {
        guard !items.isEmpty else { return nil }
        var lines = ["Here's the plan I built for today."]
        if let summary, !summary.isEmpty { lines.append(summary) }
        if let notes, !notes.isEmpty { lines.append(notes) }
        for item in items {
            var line = "\n\(item.name): \(item.targets)"
            if let reason = item.reason, !reason.isEmpty {
                line += "\n  \(item.railFallback ? "Safety rail: " : "")\(reason)"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// A few lines for the chat's hidden context (the full plan message is not resent each turn).
    var compactSummary: String? {
        guard !items.isEmpty else { return nil }
        var text = ""
        if let summary, !summary.isEmpty { text += summary + " " }
        text += items.map { "\($0.name) (\($0.compact))" }.joined(separator: "; ")
        return text.count > Self.compactLimit ? String(text.prefix(Self.compactLimit)) + "…" : text
    }

    static let compactLimit = 900

    /// Builds the seed from the plan on screen.
    static func build(
        workoutId: UUID,
        summary: String?,
        notes: String?,
        exercises: [Exercise],
        setTargets: [UUID: [SetTarget]],
        reasons: [CoachExerciseReason]?,
        review: SessionReview?
    ) -> ThreadSeed {
        let items = exercises.map { exercise -> Item in
            let targets = setTargets[exercise.id] ?? []
            let reason = reasons?.first { ExerciseNameResolver.isMatch($0.exercise, exercise.name) }
            return Item(
                name: exercise.name,
                reason: reason?.text,
                railFallback: reason?.railFallback ?? false,
                targets: targetsText(for: exercise, targets: targets),
                compact: compactText(for: exercise, targets: targets)
            )
        }
        return ThreadSeed(workoutId: workoutId, summary: clean(summary), notes: clean(notes),
                          items: items, reviewText: review.flatMap(reviewMessage(from:)))
    }

    /// "95x8 warm-up, 135x8 @RIR2": the prescribed sets, or the exercise's own targets when none.
    static func targetsText(for exercise: Exercise, targets: [SetTarget]) -> String {
        if targets.isEmpty {
            let sets = exercise.targetSets.map { "\($0) sets" } ?? "sets"
            let reps = exercise.targetReps.map { " of \($0)" } ?? ""
            return sets + reps
        }
        return targets.prefix(8).map { setText($0) }.joined(separator: ", ")
    }

    private static func compactText(for exercise: Exercise, targets: [SetTarget]) -> String {
        let working = targets.filter { $0.resolvedRole != .warmup }
        guard !working.isEmpty else {
            return exercise.targetSets.map { "\($0) sets" } ?? "no targets"
        }
        let top = working.max { (Double($0.prefillWeight) ?? 0) < (Double($1.prefillWeight) ?? 0) } ?? working[0]
        return "\(working.count) sets, top \(setText(top, includeRir: false))"
    }

    private static func setText(_ target: SetTarget, includeRir: Bool = true) -> String {
        let weight = target.prefillWeight
        let reps = target.prefillReps
        var text: String
        if weight.isEmpty {
            text = reps.isEmpty ? "set" : "\(reps) reps"
        } else {
            text = reps.isEmpty ? weight : "\(weight)x\(reps)"
        }
        if target.resolvedRole == .warmup {
            text += " warm-up"
        } else if includeRir, !target.prefillRir.isEmpty {
            text += " @RIR\(target.prefillRir)"
        }
        return text
    }

    /// The post-workout review as a coach message. nil when it has nothing to say.
    static func reviewMessage(from review: SessionReview) -> String? {
        var lines: [String] = []
        let overall = review.overallRead.trimmingCharacters(in: .whitespacesAndNewlines)
        if !overall.isEmpty { lines.append("Workout review: \(overall)") }
        for exercise in review.exercises {
            var line = "\(exercise.name): \(exercise.notes.trimmingCharacters(in: .whitespacesAndNewlines))"
            if let next = exercise.nextTarget { line += " Next time: \(next.text)." }
            lines.append(line)
        }
        guard !lines.isEmpty else { return nil }
        let text = lines.joined(separator: "\n")
        return text.count > 1500 ? String(text.prefix(1500)) + "…" : text
    }

    private static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

// MARK: - View model

/// Manages the coach chat: message list, sending user messages, receiving AI responses.
///
/// `.workout` mode is one continuous thread per workout: it opens with the coach's plan message,
/// carries on through the session and is kept locally per workout id. `.planning` mode is the chat
/// before any plan exists (goals, how today should go).
final class CoachChatViewModel: ObservableObject {

    enum Mode: Equatable { case workout, planning }

    @Published var messages: [ChatMessage] = [] {
        didSet { persistThread() }
    }
    @Published var isLoading = false
    @Published var inputText = ""
    @Published var pendingModifications: [WorkoutModification] = []
    @Published var showModificationConfirmation = false
    @Published private(set) var mode: Mode = .workout
    /// A goal the athlete agreed to in chat, waiting for "Save goal".
    @Published var pendingGoal: CoachGoal?
    @Published private(set) var activeGoals: [CoachGoal] = []

    private let aiServiceManager: AIServiceManager
    private let coachPromptService: CoachPromptService
    private let coachContextBuilder: CoachContextBuilder
    private let validationService: ValidationService
    private let threadStore: CoachThreadStore
    private let goalStore: CoachGoalStore
    private let liftHistory: ((UUID, String) -> [GoalAssessor.Point])?
    private let loggedLiftNames: ((UUID) -> [String])?
    private let modificationParser = WorkoutModificationParser()
    private let jsonParser = WorkoutModificationJSONParser()

    private var userId: UUID?
    private var workoutType: String?
    private var systemPrompt: String = ""
    private var currentExercises: [Exercise] = []
    private var currentLoggedSets: [UUID: [WorkoutSet]] = [:]
    private var knownExerciseNames: [String] = []
    private var preferredExerciseNames: [String] = []

    /// Hidden lines (the goal "APP CHECK") appended to a user message when it goes to the AI.
    private var hiddenContext: [UUID: String] = [:]
    private var lastGoalCheck: (exercise: String, line: String)?

    private var threadWorkoutId: UUID?
    private var planSeeded = false
    private var reviewAppended = false

    /// How many recent messages (after the workout-context message) go to the AI.
    static let historyWindow = 6
    /// Longest "agreed notes" handed to the plan request.
    static let planNotesLimit = 300

    /// The context message plus the last few messages. The full history stays on screen.
    static func windowedMessages(_ messages: [ChatMessage], window: Int = historyWindow) -> [ChatMessage] {
        guard messages.count > window + 1, let context = messages.first else { return messages }
        return [context] + messages.suffix(window)
    }

    init(
        aiServiceManager: AIServiceManager,
        coachPromptService: CoachPromptService,
        coachContextBuilder: CoachContextBuilder,
        validationService: ValidationService,
        threadStore: CoachThreadStore = .shared,
        goalStore: CoachGoalStore = .shared,
        liftHistory: ((UUID, String) -> [GoalAssessor.Point])? = nil,
        loggedLiftNames: ((UUID) -> [String])? = nil
    ) {
        self.aiServiceManager = aiServiceManager
        self.coachPromptService = coachPromptService
        self.coachContextBuilder = coachContextBuilder
        self.validationService = validationService
        self.threadStore = threadStore
        self.goalStore = goalStore
        self.liftHistory = liftHistory
        self.loggedLiftNames = loggedLiftNames
    }

    // MARK: - Prompt text

    /// Goal conversation rules, added to the chat system prompt in every mode.
    static func goalRules(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return """
        LIFT GOALS. Today is \(formatter.string(from: now)). When the athlete names a lift target ("225x1 bench", "hit 225 on bench", \
        "how do I get to 225 bench"), the app adds a hidden line starting "APP CHECK:" to their message with their real numbers \
        (current e1RM, weekly trend, the target's e1RM, the gap and a verdict). Build the conversation around those numbers. \
        Never invent lifts, weights or dates the athlete has not logged. If there is no APP CHECK, ask for a recent top set.
        Talk like a coach: direct, short, one question at a time.
        - Gap 3% or less: it is within reach now. Give the warm-up ladder from the APP CHECK and how to attempt it: rest 3-5 minutes \
        between ladder steps, take 1 attempt, stop if the bar speeds slow.
        - Gap 3% to 10%: not this week. Lay out a multi-session block with dates and top sets that build toward it.
        - Bigger gap: say plainly it is far off and offer an intermediate goal.
        When the athlete agrees to a goal (or an intermediate goal), reply with one short confirming sentence and end with exactly \
        one fenced json block, and nothing after it:
        ```json
        {"goal": {"exercise": "str", "weight": 225, "reps": 1, "deadline": "YYYY-MM-DD" or null, \
        "steps": [{"date": "YYYY-MM-DD", "text": "str", "weight": 205, "reps": 3, "attempt": false}]}}
        ```
        The last step is the attempt itself ("attempt": true). Do NOT output this block until the athlete has agreed.
        """
    }

    /// Extra rules for the chat before any plan exists.
    static let planningRules = """
    NO PLAN YET. The athlete is talking to you before today's workout exists. Find out what they want from today \
    (focus, time, a tweak or injury, a lift they want to hit) one question at a time. Do not write workouts, sets or \
    modification blocks; the app builds the plan afterwards. Once it is clear, finish your reply with one line: \
    "Plan notes: <what the plan should account for, plain text, under 300 characters>".
    """

    static let planningGreeting = "What do you want out of today? Tell me how you feel, what to focus on, or a lift you want to hit, and I'll take it into the plan."

    // MARK: - Configure

    /// Opens the chat for a workout. With a `seed` this is the workout's continuous thread: it starts with the coach's
    /// plan message, keeps (and restores) the conversation, and gets the review once one exists.
    func configure(userId: UUID, workoutType: String, exercises: [Exercise], loggedSets: [UUID: [WorkoutSet]],
                   seed: ThreadSeed? = nil) {
        // A planning chat that led to this workout carries over as the start of its thread.
        let carried: [ChatMessage] = (mode == .planning && messages.count > 1) ? Array(messages.dropFirst()) : []
        mode = .workout
        self.workoutType = workoutType
        self.currentExercises = exercises
        self.currentLoggedSets = loggedSets

        let context = prepareContext(userId: userId, workoutType: workoutType, extraRules: nil)
        var info = Self.workoutContextInfo(workoutType: workoutType, exercises: exercises, loggedSets: loggedSets)
        if let summary = context.rollingSummary { info += "\n\nRecent history: \(summary)" }
        if let compact = seed?.compactSummary { info += "\n\nToday's plan: \(compact)" }
        if let goals = goalsLine() { info += "\n\n\(goals)" }
        let contextMessage = ChatMessage(role: .user, content: info)

        if let seed {
            if threadWorkoutId == seed.workoutId, !messages.isEmpty {
                messages[0] = contextMessage
            } else {
                threadWorkoutId = nil   // no saving while the thread is rebuilt
                let stored = threadStore.thread(forWorkout: seed.workoutId)
                planSeeded = stored?.planSeeded ?? false
                reviewAppended = stored?.reviewAppended ?? false
                let restored = stored?.messages.map(\.message) ?? carried
                threadWorkoutId = seed.workoutId
                messages = [contextMessage] + restored
            }
            appendSeededMessages(seed)
        } else {
            threadWorkoutId = nil
            if messages.isEmpty {
                let greeting = ChatMessage(role: .coach, content: "I can see your current session. What would you like to know about your workout?")
                messages = [contextMessage, greeting]
            } else {
                messages[0] = contextMessage
            }
        }
    }

    /// Opens the chat before any plan exists.
    func configurePlanning(userId: UUID) {
        let continuing = mode == .planning && messages.count > 1
        mode = .planning
        workoutType = nil
        currentExercises = []
        currentLoggedSets = [:]
        threadWorkoutId = nil
        planSeeded = false
        reviewAppended = false

        let context = prepareContext(userId: userId, workoutType: nil, extraRules: Self.planningRules)
        var info = "Planning a workout. No plan exists yet."
        let recent = context.recentSessions.prefix(5).map { "\($0.workoutType) \($0.date.formatted(.dateTime.month(.abbreviated).day()))" }
        if !recent.isEmpty { info += "\n\nRecent sessions: " + recent.joined(separator: ", ") }
        if let goals = goalsLine() { info += "\n\n\(goals)" }
        let contextMessage = ChatMessage(role: .user, content: info)

        if continuing {
            messages[0] = contextMessage
        } else {
            messages = [contextMessage, ChatMessage(role: .coach, content: Self.planningGreeting)]
        }
    }

    /// Plan message first, review last. Each is added once per thread.
    private func appendSeededMessages(_ seed: ThreadSeed) {
        if !planSeeded, let text = seed.planMessage {
            planSeeded = true
            messages.append(ChatMessage(role: .coach, content: text))
        }
        if !reviewAppended, let text = seed.reviewText {
            reviewAppended = true
            messages.append(ChatMessage(role: .coach, content: text))
        }
        if messages.count == 1 {
            messages.append(ChatMessage(role: .coach, content: "I can see your current session. What would you like to know about your workout?"))
        }
    }

    /// Builds the profile-based system prompt and the list of lift names the athlete could mean.
    private func prepareContext(userId: UUID, workoutType: String?, extraRules: String?) -> CoachContext {
        self.userId = userId
        let context = coachContextBuilder.buildContext(userId: userId, workoutType: workoutType)
        var prompt = coachPromptService.buildSystemPrompt(profile: context.profile, task: .chat)
        prompt += "\n\n" + Self.goalRules()
        if let extraRules { prompt += "\n\n" + extraRules }
        systemPrompt = prompt

        // Names the athlete could swap in or aim for without asking the AI: their logged lifts
        // plus the built-in catalog.
        var logged = Set(loggedLiftNames?(userId) ?? [])
        for list in context.recentSessionSets.values { list.forEach { logged.insert($0.name) } }
        var names = Set(ExerciseCatalog.exercises.map(\.name))
        names.formUnion(logged)
        knownExerciseNames = names.sorted()
        preferredExerciseNames = logged.sorted()

        refreshGoals()
        return context
    }

    private static func workoutContextInfo(workoutType: String, exercises: [Exercise],
                                           loggedSets: [UUID: [WorkoutSet]]) -> String {
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
        return contextInfo
    }

    // MARK: - Thread saving

    private func persistThread() {
        guard let id = threadWorkoutId, messages.count > 1 else { return }
        let thread = StoredChatThread(
            messages: messages.dropFirst().map(StoredChatMessage.init),
            planSeeded: planSeeded,
            reviewAppended: reviewAppended,
            updatedAt: Date()
        )
        threadStore.save(thread, forWorkout: id)
    }

    // MARK: - Sending

    /// Send a user message and get AI response.
    func sendMessage() {
        let text = validationService.sanitize(inputText)
        guard !text.isEmpty, !isLoading else { return }

        inputText = ""
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)

        // A lift target ("225x1 bench"): the app checks the numbers first and the AI talks around them.
        if let intent = LocalChatCommandParser.parseGoal(text, knownNames: knownExerciseNames,
                                                         preferredNames: preferredExerciseNames) {
            let line = goalCheckLine(for: intent)
            hiddenContext[userMessage.id] = line
            lastGoalCheck = (intent.exerciseName, line)
        } else if let command = LocalChatCommandParser.parse(text, exercises: currentExercises, knownNames: knownExerciseNames) {
            // Simple, unambiguous commands are handled locally: no AI call.
            messages.append(ChatMessage(role: .coach, content: command.reply))
            pendingModifications = command.modifications
            showModificationConfirmation = true
            return
        }

        isLoading = true

        aiServiceManager.generateChat(
            systemPrompt: systemPrompt,
            messages: Self.withHiddenContext(Self.windowedMessages(messages), hidden: hiddenContext),
            expectsJSON: false,
            options: .forTask(.chat)
        ) { [weak self] result in
            guard let self = self else { return }
            self.isLoading = false

            switch result {
            case .success(let responseText):
                self.handleReply(responseText)
            case .failure(let error):
                let errorMessage = ChatMessage(role: .coach, content: "Sorry, I couldn't respond right now. Please try again. (\(error.localizedDescription))")
                self.messages.append(errorMessage)
            }
        }
    }

    /// The messages as the AI sees them: hidden lines appended to the user messages they belong to.
    static func withHiddenContext(_ messages: [ChatMessage], hidden: [UUID: String]) -> [ChatMessage] {
        messages.map { message in
            guard let extra = hidden[message.id] else { return message }
            return ChatMessage(id: message.id, role: message.role,
                               content: message.content + "\n\n" + extra, timestamp: message.timestamp)
        }
    }

    private func handleReply(_ responseText: String) {
        // Strip JSON before displaying to the user. If that leaves
        // nothing, the reply was JSON end to end — show a sentence
        // rather than an empty bubble.
        let goal = jsonParser.parseGoal(responseText)
        var displayText = jsonParser.strippingJSONBlock(from: responseText)
        if displayText.isEmpty {
            displayText = goal != nil ? "Here's the goal and the steps we agreed." : "Here's what I'd change for this session."
        }
        messages.append(ChatMessage(role: .coach, content: displayText))

        if var goal {
            goal.exerciseName = canonicalName(goal.exerciseName)
            if let check = lastGoalCheck, ExerciseNameResolver.isMatch(check.exercise, goal.exerciseName) {
                goal.assessment = check.line
            }
            pendingGoal = goal
            return
        }
        // Before a plan exists there is nothing to modify.
        guard mode == .workout else { return }

        // Parse modifications: try JSON parser first, fall back to pipe parser
        let modifications: [WorkoutModification]
        var extractionFailed = false
        do {
            let jsonModifications = try jsonParser.parse(responseText)
            if !jsonModifications.isEmpty {
                modifications = jsonModifications
            } else {
                // No JSON block found — try legacy pipe format
                modifications = modificationParser.parse(responseText)
            }
        } catch {
            // Malformed JSON block — fall back to legacy pipe parser
            modifications = modificationParser.parse(responseText)
            extractionFailed = true
        }

        if !modifications.isEmpty {
            pendingModifications = modifications
            showModificationConfirmation = true
        } else if extractionFailed || Self.containsMarkdownTable(responseText) {
            // The coach described changes but we couldn't read them. Say so
            // rather than leaving the athlete waiting for a prompt that
            // will never appear.
            messages.append(ChatMessage(
                role: .coach,
                content: "I couldn't apply those changes automatically — please adjust the workout manually, or ask me again."
            ))
        }
    }

    // MARK: - Goals

    /// The app's numbers for a goal, as the hidden "APP CHECK" line.
    private func goalCheckLine(for intent: GoalIntent) -> String {
        if let userId, let history = liftHistory?(userId, intent.exerciseName),
           let assessment = GoalAssessor.assess(exercise: intent.exerciseName, targetWeight: intent.weight,
                                                targetReps: intent.reps, history: history) {
            return GoalAssessor.appCheckLine(assessment)
        }
        return GoalAssessor.noHistoryLine(exercise: intent.exerciseName, targetWeight: intent.weight,
                                          targetReps: intent.reps)
    }

    /// A known name for the lift the coach wrote, else the coach's own spelling.
    private func canonicalName(_ name: String) -> String {
        if let check = lastGoalCheck, ExerciseNameResolver.isMatch(check.exercise, name) { return check.exercise }
        let lower = name.lowercased()
        return knownExerciseNames.first { $0.lowercased() == lower }
            ?? knownExerciseNames.first { ExerciseNameResolver.isMatch($0, name) }
            ?? name
    }

    private func goalsLine() -> String? {
        guard !activeGoals.isEmpty else { return nil }
        return "Active goals: " + activeGoals.map(\.summary).joined(separator: "; ")
    }

    func refreshGoals() {
        activeGoals = userId.map { goalStore.activeGoals(for: $0) } ?? []
    }

    /// "Save goal" on the confirmation card.
    func saveGoal() {
        guard let goal = pendingGoal, let userId else { return }
        goalStore.add(goal, for: userId)
        pendingGoal = nil
        refreshGoals()
        messages.append(ChatMessage(role: .coach, content: "Saved: \(goal.summary). I'll keep it in mind when I plan your sessions."))
    }

    /// "Not now" on the confirmation card.
    func dismissPendingGoal() {
        pendingGoal = nil
    }

    func dropGoal(id: UUID) {
        guard let userId else { return }
        goalStore.setStatus(.dropped, goalId: id, for: userId)
        refreshGoals()
    }

    // MARK: - Plan notes

    /// What the plan request should account for, from this chat (at most `planNotesLimit` characters).
    func agreedPlanNotes() -> String {
        Self.agreedNotes(from: messages)
    }

    /// The coach's last "Plan notes:" line, else what the athlete said in the chat.
    static func agreedNotes(from messages: [ChatMessage], limit: Int = planNotesLimit) -> String {
        let body = Array(messages.dropFirst())
        let marker = "plan notes:"
        for message in body.reversed() where message.role == .coach {
            for line in message.content.components(separatedBy: .newlines).reversed() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.lowercased().hasPrefix(marker) else { continue }
                let notes = String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                if !notes.isEmpty { return truncated(notes, limit) }
            }
        }
        let said = body.filter { $0.role == .user }
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return truncated(said.joined(separator: "; "), limit)
    }

    static func truncated(_ text: String, _ limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(max(0, limit - 1))) + "…"
    }

    // MARK: - Helpers

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

    /// The seed for the workout on screen: the plan's summary and notes, each exercise's reason and targets,
    /// and the post-workout review once it exists. nil when no workout is open.
    static func seed(from today: TodayViewModel) -> ThreadSeed? {
        guard let workoutId = today.sessionService.currentWorkoutId else { return nil }
        let exercises = today.exercises
        var summary: String?
        var notes: String?
        var reasons: [CoachExerciseReason]?
        // The last plan snapshot only counts when it is about this workout's exercises.
        if let userId = today.userId,
           let snapshot = CoachDebugStore.shared.lastPlan(forUser: userId),
           let saved = snapshot.reasons,
           saved.contains(where: { reason in exercises.contains { ExerciseNameResolver.isMatch($0.name, reason.exercise) } }) {
            reasons = saved
            if let raw = snapshot.rawResponse, let object = JSONReply.object(from: raw) {
                summary = JSONReply.string(object["summary"])
                notes = JSONReply.string(object["coaching_notes"])
            }
        }
        if summary == nil, let review = today.coachReview, !review.summary.isEmpty {
            summary = review.summary
        }
        return ThreadSeed.build(
            workoutId: workoutId,
            summary: summary,
            notes: notes,
            exercises: exercises,
            setTargets: today.setTargets,
            reasons: reasons,
            review: today.currentCoachReviewDocument()?.review
        )
    }

    // MARK: - Modifications

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

    /// Clear the on-screen chat when leaving the workout. The saved thread for the workout stays.
    func clearChat() {
        threadWorkoutId = nil
        planSeeded = false
        reviewAppended = false
        mode = .workout
        messages = []
        inputText = ""
        isLoading = false
        pendingModifications = []
        showModificationConfirmation = false
        pendingGoal = nil
        hiddenContext = [:]
        lastGoalCheck = nil
    }
}
