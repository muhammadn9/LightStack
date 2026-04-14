import Foundation

// MARK: - Delegate

protocol WorkoutSessionServiceDelegate: AnyObject {
    func sessionServiceDidGeneratePlan(_ service: WorkoutSessionService, exercises: [Exercise])
    func sessionServiceDidReceiveProgressionNote(_ service: WorkoutSessionService, note: String)
    func sessionServiceDidSaveWorkout(_ service: WorkoutSessionService)
    func sessionServiceDidFail(_ service: WorkoutSessionService, error: Error)
}

// MARK: - WorkoutSessionService

/// Owns the business logic for a single workout session:
/// creating a workout record, adding exercises and sets,
/// computing volume, and finalizing with AI progression note.
final class WorkoutSessionService {

    weak var delegate: WorkoutSessionServiceDelegate?

    private let aiServiceManager: AIServiceManager
    private let coachPromptService: CoachPromptService
    private let coachContextBuilder: CoachContextBuilder
    private let workoutRepository: WorkoutRepository
    private let monthPlanRepository: MonthPlanRepository
    private let localStorage: LocalStorageService
    private let supabaseService: SupabaseService
    private let validationService: ValidationService
    private let offlineQueueManager: OfflineQueueManager

    private(set) var currentWorkout: Workout?
    private(set) var currentWorkoutId: UUID?

    var currentWorkoutCreatedAt: Date? {
        currentWorkout?.createdAt
    }

    var currentWorkoutType: String? {
        currentWorkout?.workoutType
    }

    init(
        aiServiceManager: AIServiceManager,
        coachPromptService: CoachPromptService,
        coachContextBuilder: CoachContextBuilder,
        workoutRepository: WorkoutRepository,
        monthPlanRepository: MonthPlanRepository,
        localStorage: LocalStorageService,
        supabaseService: SupabaseService,
        validationService: ValidationService,
        offlineQueueManager: OfflineQueueManager
    ) {
        self.aiServiceManager = aiServiceManager
        self.coachPromptService = coachPromptService
        self.coachContextBuilder = coachContextBuilder
        self.workoutRepository = workoutRepository
        self.monthPlanRepository = monthPlanRepository
        self.localStorage = localStorage
        self.supabaseService = supabaseService
        self.validationService = validationService
        self.offlineQueueManager = offlineQueueManager
    }

    // MARK: - Generate Plan

    func generatePlan(
        userId: UUID,
        workoutType: String,
        time: Int,
        energy: Int,
        notes: String?
    ) {
        let sanitizedType = validationService.sanitizeLabel(workoutType)
        let sanitizedNotes = notes.map { validationService.sanitize($0) }

        // Pre-build the workout value so it's ready the moment rate limit passes.
        // Do NOT create the record yet — creating it before the rate-limit check
        // would leave phantom workouts in history if the check fails.
        let pendingWorkout = Workout.create(
            userId: userId,
            workoutType: sanitizedType,
            energyLevel: energy,
            timeAvailableMinutes: time,
            setupNote: sanitizedNotes?.isEmpty == false ? sanitizedNotes : nil
        )

        Task { @MainActor in
            // Rate limit check before any writes or API calls
            do {
                let allowed = try await supabaseService.checkRateLimit(userId: userId)
                if !allowed {
                    let error = NSError(
                        domain: "WorkoutSessionService",
                        code: 429,
                        userInfo: [NSLocalizedDescriptionKey: "Too many AI requests. Please wait a moment before trying again."]
                    )
                    delegate?.sessionServiceDidFail(self, error: error)
                    return
                }
            } catch {
                // Rate limit check failed (network issue) — proceed and let Gemini decide
            }

            // Write the workout record only after passing rate limit
            currentWorkout = pendingWorkout
            currentWorkoutId = pendingWorkout.id
            workoutRepository.createWorkout(pendingWorkout)

            let context = coachContextBuilder.buildContext(userId: userId, workoutType: sanitizedType)
            let systemPrompt = coachPromptService.buildSystemPrompt(profile: context.profile)
            let userMessage = coachPromptService.buildWorkoutRequestMessage(
                workoutType: sanitizedType,
                time: time,
                energy: energy,
                notes: sanitizedNotes,
                rollingSummary: context.rollingSummary,
                recentSessions: context.recentSessions,
                recentSessionExercises: context.recentSessionSets
            )

            aiServiceManager.generateChat(
                systemPrompt: systemPrompt,
                messages: [ChatMessage(role: .user, content: userMessage)]
            ) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let responseText):
                    self.handleWorkoutPlanResponse(responseText)
                case .failure(let error):
                    self.delegate?.sessionServiceDidFail(self, error: error)
                }
            }
        }
    }

    // MARK: - Start Session

    func startSession(workout: Workout, exercises: [Exercise]) {
        currentWorkout = workout
        currentWorkoutId = workout.id
        workoutRepository.saveExercises(exercises, workoutId: workout.id)
    }

    // MARK: - Log Set

    func logSet(_ workoutSet: WorkoutSet, exerciseId: UUID) {
        workoutRepository.saveSet(workoutSet, exerciseId: exerciseId)
    }

    // MARK: - Finish Session

    func finishSession(
        userId: UUID,
        userNote: String?,
        exercises: [Exercise],
        allSets: [UUID: [WorkoutSet]]
    ) {
        guard var workout = currentWorkout else { return }
        let durationMinutes = Int(Date().timeIntervalSince(workout.createdAt) / 60)
        workout.durationMinutes = durationMinutes
        workout.userNote = userNote.map { validationService.sanitize($0) }
        currentWorkout = workout

        // Persist duration immediately — if the app is backgrounded/killed while
        // waiting for the AI note, the duration is already saved in Core Data.
        workoutRepository.updateWorkout(workout)

        Task { @MainActor in
            do {
                let allowed = try await supabaseService.checkRateLimit(userId: userId)
                if !allowed {
                    // Rate-limited — let user stay on PostWorkoutView without an AI note
                    self.handleProgressionNoteResponse("")
                    return
                }
            } catch {
                // Rate limit check failed — proceed without blocking
            }

            let context = coachContextBuilder.buildContext(userId: userId)
            let systemPrompt = coachPromptService.buildSystemPrompt(profile: context.profile)
            let userMessage = coachPromptService.buildPostSessionMessage(
                exercises: exercises,
                sets: allSets
            )

            aiServiceManager.generateChat(
                systemPrompt: systemPrompt,
                messages: [ChatMessage(role: .user, content: userMessage)]
            ) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let responseText):
                    self.handleProgressionNoteResponse(responseText)
                case .failure:
                    // AI call failed — let user stay on PostWorkoutView without an AI note
                    self.handleProgressionNoteResponse("")
                }
            }
        }
    }

    // MARK: - Save Completed Workout

    func saveCompletedWorkout(
        userNote: String?,
        aiNote: String?,
        exercises: [Exercise],
        sets: [UUID: [WorkoutSet]]
    ) {
        guard var workout = currentWorkout else { return }
        workout.userNote = userNote.map { validationService.sanitize($0) }
        workout.aiProgressionNote = aiNote
        workout.syncStatus = .pending
        currentWorkout = workout
        workoutRepository.updateWorkout(workout)

        // Reconcile: delete any Core Data exercises that were removed by the user
        let storedExercises = workoutRepository.fetchExercises(workoutId: workout.id)
        let finalIds = Set(exercises.map { $0.id })
        for ex in storedExercises where !finalIds.contains(ex.id) {
            workoutRepository.deleteExercise(ex.id)
        }

        markMatchingPlannedSessionCompleted(workout: workout)

        let workoutType = workout.workoutType
        let userId = workout.userId

        if !exercises.isEmpty {
            generateContextSummary(
                userId: userId,
                workoutType: workoutType,
                exercises: exercises,
                sets: sets
            )
        }

        delegate?.sessionServiceDidSaveWorkout(self)
    }

    // MARK: - Planned Session Completion

    private func markMatchingPlannedSessionCompleted(workout: Workout) {
        guard let plan = monthPlanRepository.fetchActivePlan(userId: workout.userId) else { return }
        let sessions = monthPlanRepository.fetchSessions(monthPlanId: plan.id)
        let today = Calendar.current.startOfDay(for: Date())

        guard let match = sessions.first(where: { session in
            !session.isRestDay
            && !session.completed
            && session.workoutType.lowercased() == workout.workoutType.lowercased()
            && Calendar.current.isDate(session.plannedDate, inSameDayAs: today)
        }) else { return }

        monthPlanRepository.markSessionCompleted(match, workoutId: workout.id)
    }

    // MARK: - Context Summary Generation

    private func generateContextSummary(
        userId: UUID,
        workoutType: String,
        exercises: [Exercise],
        sets: [UUID: [WorkoutSet]]
    ) {
        let context = coachContextBuilder.buildContext(userId: userId)
        let systemPrompt = coachPromptService.buildSystemPrompt(profile: context.profile)
        let userMessage = coachPromptService.buildContextSummaryMessage(
            workoutType: workoutType,
            exercises: exercises,
            sets: sets
        )

        aiServiceManager.generateChat(
            systemPrompt: systemPrompt,
            messages: [ChatMessage(role: .user, content: userMessage)]
        ) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let summaryText):
                let existing = self.localStorage.fetchContextSummary(userId: userId, workoutType: workoutType)
                let sessionsCovered = existing.map { Int($0.sessionsCovered) + 1 } ?? 1

                let summary = AIContextSummary.create(
                    userId: userId,
                    workoutType: workoutType,
                    summaryText: summaryText,
                    sessionsCovered: sessionsCovered
                )
                self.localStorage.saveContextSummary(summary)

                Task {
                    do {
                        try await self.supabaseService.upsertContextSummary(summary)
                    } catch {
                        await self.offlineQueueManager.enqueue(.upsertContextSummary, payload: summary)
                    }
                }
            case .failure(let error):
                print("WorkoutSessionService: Context summary generation failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Parse Exercise Table

    /// Parse markdown table into Exercise structs.
    /// Detects column positions from the header row so it handles both:
    ///   | Exercise | Sets | Target Weight | Reps | RIR | Rest |
    ///   | Muscle Group | Exercise | Sets | Target Weight | Reps | RIR | Rest |
    /// Defensive parsing — returns empty array on malformed output, never crashes.
    func parseExerciseTable(_ text: String) -> [Exercise] {
        guard let workoutId = currentWorkoutId else { return [] }

        let lines = text.components(separatedBy: .newlines)
        var exercises: [Exercise] = []
        var orderIndex = 0

        // Column indices — set to defaults for old format, overridden by header detection
        var nameCol = 0
        var muscleCol: Int? = nil
        var setsCol = 1
        var weightCol = 2
        var repsCol = 3
        var rirCol = 4
        var restCol = 5
        var headerParsed = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("|") && trimmed.hasSuffix("|") else { continue }

            let columns = trimmed
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }

            guard columns.count >= 4 else { continue }

            // Skip separator rows
            if columns.contains(where: { $0.hasPrefix("-") }) { continue }

            // Header row: detect column indices once
            if !headerParsed {
                let lower = columns.map { $0.lowercased() }
                if lower.contains(where: { $0.contains("exercise") || $0.contains("sets") || $0.contains("movement") }) {
                    for (i, col) in lower.enumerated() {
                        if col.contains("exercise") || col.contains("movement") { nameCol = i }
                        else if col.contains("muscle") || col.contains("group")  { muscleCol = i }
                        else if col.contains("set")                               { setsCol = i }
                        else if col.contains("weight") || col.contains("target")  { weightCol = i }
                        else if col.contains("rep")                               { repsCol = i }
                        else if col.contains("rir")                               { rirCol = i }
                        else if col.contains("rest")                              { restCol = i }
                    }
                    headerParsed = true
                    continue
                }
            }

            guard columns.count > nameCol else { continue }
            let rawName = columns[nameCol]
            guard !rawName.isEmpty, !rawName.contains("---") else { continue }

            let name = validationService.sanitizeLabel(rawName)
            guard !name.isEmpty else { continue }

            let setsStr   = columns.count > setsCol   ? columns[setsCol]   : ""
            let weightStr = columns.count > weightCol  ? columns[weightCol] : ""
            let repsStr   = columns.count > repsCol    ? columns[repsCol]   : ""
            let rirStr    = columns.count > rirCol     ? columns[rirCol]    : ""
            let restStr   = columns.count > restCol    ? columns[restCol]   : ""

            // Use Muscle Group column when present, otherwise infer from name
            let muscleGroup: String
            if let mc = muscleCol, columns.count > mc, !columns[mc].isEmpty {
                muscleGroup = columns[mc]
            } else {
                muscleGroup = inferMuscleGroup(name)
            }

            let targetSets = parseFirstInt(setsStr)
            guard let targetSets, targetSets > 0 else { continue }
            let restSeconds = parseRestSeconds(restStr)

            let exercise = Exercise.create(
                workoutId: workoutId,
                name: name,
                muscleGroup: muscleGroup,
                orderIndex: orderIndex,
                targetSets: targetSets,
                targetReps: repsStr.isEmpty ? nil : repsStr,
                targetRir: rirStr.isEmpty ? nil : rirStr,
                restSeconds: restSeconds,
                coachNote: weightStr.isEmpty ? nil : "Target: \(weightStr)"
            )
            exercises.append(exercise)
            orderIndex += 1
        }

        return exercises
    }

    // MARK: - JSON Parser

    func parseWorkoutPlanJSON(_ text: String) -> [Exercise]? {
        guard let workoutId = currentWorkoutId else { return nil }

        // Strip accidental markdown code-fences some providers emit
        var jsonString = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonString.hasPrefix("```") {
            let lines = jsonString.components(separatedBy: .newlines)
            jsonString = lines.dropFirst().dropLast().joined(separator: "\n")
        }

        guard let data = jsonString.data(using: .utf8) else { return nil }

        let decoded: WorkoutPlanResponse
        do {
            decoded = try JSONDecoder().decode(WorkoutPlanResponse.self, from: data)
        } catch {
            print("[WorkoutSessionService] JSON parse failed: \(error)")
            return nil
        }

        guard !decoded.exercises.isEmpty else { return nil }

        var exercises: [Exercise] = []
        for (index, aiEx) in decoded.exercises.enumerated() {
            let name = validationService.sanitizeLabel(aiEx.name)
            guard !name.isEmpty, aiEx.sets > 0 else { continue }

            // Preserve "Target: {weight}" prefix convention that
            // ActiveWorkoutViewModel.prefillWeightValue depends on
            let weightNote = aiEx.targetWeight.flatMap { $0.isEmpty ? nil : "Target: \($0)" }
            let mergedNote: String?
            switch (weightNote, aiEx.coachNote) {
            case let (w?, c?): mergedNote = "\(w) — \(c)"
            case let (w?, nil): mergedNote = w
            case let (nil, c?): mergedNote = c
            case (nil, nil):    mergedNote = nil
            }

            let muscleGroup = aiEx.muscleGroup.isEmpty ? inferMuscleGroup(name) : aiEx.muscleGroup

            exercises.append(Exercise.create(
                workoutId: workoutId,
                name: name,
                muscleGroup: muscleGroup,
                orderIndex: index,
                targetSets: aiEx.sets,
                targetReps: aiEx.reps,
                targetRir: aiEx.rir,
                restSeconds: aiEx.restSeconds,
                coachNote: mergedNote
            ))
        }
        return exercises.isEmpty ? nil : exercises
    }

    // MARK: - Response Handlers

    private func handleWorkoutPlanResponse(_ text: String) {
        // Primary path: JSON
        if let exercises = parseWorkoutPlanJSON(text) {
            print("[WorkoutSessionService] JSON parse succeeded: \(exercises.count) exercises")
            finalizePlan(exercises)
            return
        }
        // Fallback: markdown table (zero regression during rollout)
        print("[WorkoutSessionService] JSON parse failed, attempting markdown fallback")
        let fallback = parseExerciseTable(text)
        guard !fallback.isEmpty else {
            delegate?.sessionServiceDidFail(self, error: NSError(
                domain: "WorkoutSessionService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Could not parse workout plan from AI response"]
            ))
            return
        }
        print("[WorkoutSessionService] Markdown fallback succeeded: \(fallback.count) exercises")
        finalizePlan(fallback)
    }

    private func finalizePlan(_ exercises: [Exercise]) {
        if let workoutId = currentWorkoutId {
            workoutRepository.deleteExercises(forWorkoutId: workoutId)
            workoutRepository.saveExercises(exercises, workoutId: workoutId)
        }
        delegate?.sessionServiceDidGeneratePlan(self, exercises: exercises)
    }

    private func handleProgressionNoteResponse(_ text: String) {
        delegate?.sessionServiceDidReceiveProgressionNote(self, note: text)
    }

    // MARK: - Private Helpers

    private func parseFirstInt(_ str: String) -> Int? {
        guard let range = str.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(str[range])
    }

    private func parseRestSeconds(_ str: String) -> Int? {
        guard let value = parseFirstInt(str) else { return nil }
        if str.lowercased().contains("min") {
            return value * 60
        }
        return value
    }

    private func inferMuscleGroup(_ exerciseName: String) -> String {
        let lower = exerciseName.lowercased()
        if lower.contains("bench") || lower.contains("chest") || lower.contains("fly") || lower.contains("push") {
            return "Chest"
        } else if lower.contains("row") || lower.contains("pull") || lower.contains("lat") || lower.contains("back") {
            return "Back"
        } else if lower.contains("squat") || lower.contains("leg") || lower.contains("lunge") || lower.contains("calf") || lower.contains("hamstring") || lower.contains("quad") {
            return "Legs"
        } else if lower.contains("shoulder") || lower.contains("delt") || lower.contains("lateral raise") || lower.contains("overhead press") || lower.contains("ohp") {
            return "Shoulders"
        } else if lower.contains("curl") || lower.contains("bicep") {
            return "Biceps"
        } else if lower.contains("tricep") || lower.contains("extension") || lower.contains("skull") || lower.contains("dip") {
            return "Triceps"
        } else if lower.contains("deadlift") {
            return "Back"
        } else if lower.contains("press") {
            return "Chest"
        }
        return "General"
    }
}

// MARK: - JSON Models

private struct WorkoutPlanResponse: Decodable {
    let exercises: [AIExercise]
    let coachingNotes: String?
    enum CodingKeys: String, CodingKey {
        case exercises
        case coachingNotes = "coaching_notes"
    }
}

private struct AIExercise: Decodable {
    let name: String
    let muscleGroup: String
    let sets: Int
    let targetWeight: String?
    let reps: String?
    let rir: String?
    let restSeconds: Int?
    let coachNote: String?
    enum CodingKeys: String, CodingKey {
        case name, sets, reps, rir
        case muscleGroup  = "muscle_group"
        case targetWeight = "target_weight"
        case restSeconds  = "rest_seconds"
        case coachNote    = "coach_note"
    }
}
