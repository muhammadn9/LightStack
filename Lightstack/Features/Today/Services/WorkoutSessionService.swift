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
    /// Expected format: | Exercise | Sets | Target Weight | Reps | RIR | Rest |
    /// Defensive parsing — returns empty array on malformed output, never crashes.
    func parseExerciseTable(_ text: String) -> [Exercise] {
        guard let workoutId = currentWorkoutId else { return [] }

        // Use .newlines to handle both \n and \r\n line endings from API responses
        let lines = text.components(separatedBy: .newlines)
        var exercises: [Exercise] = []
        var orderIndex = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            guard trimmed.hasPrefix("|") && trimmed.hasSuffix("|") else { continue }

            let columns = trimmed
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }

            guard columns.count >= 4 else { continue }
            if columns[0].lowercased().contains("exercise") { continue }
            if columns[0].contains("---") { continue }

            let rawName = columns[0]
            guard !rawName.isEmpty, !rawName.contains("---") else { continue }

            // Sanitize AI-generated exercise names before storing
            let name = validationService.sanitizeLabel(rawName)
            guard !name.isEmpty else { continue }

            let setsStr = columns.count > 1 ? columns[1] : ""
            let weightStr = columns.count > 2 ? columns[2] : ""
            let repsStr = columns.count > 3 ? columns[3] : ""
            let rirStr = columns.count > 4 ? columns[4] : ""
            let restStr = columns.count > 5 ? columns[5] : ""

            let targetSets = parseFirstInt(setsStr)
            // Skip rows that have no valid set count — these are section headers
            // (e.g. "Quads/Glutes (form focus)") not actual exercises
            guard let targetSets = targetSets, targetSets > 0 else { continue }
            let restSeconds = parseRestSeconds(restStr)

            let exercise = Exercise.create(
                workoutId: workoutId,
                name: name,
                muscleGroup: inferMuscleGroup(name),
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

    // MARK: - Response Handlers

    private func handleWorkoutPlanResponse(_ text: String) {
        let exercises = parseExerciseTable(text)
        if exercises.isEmpty {
            let error = NSError(domain: "WorkoutSessionService", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Could not parse workout plan from AI response"])
            delegate?.sessionServiceDidFail(self, error: error)
            return
        }
        if let workoutId = currentWorkoutId {
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
