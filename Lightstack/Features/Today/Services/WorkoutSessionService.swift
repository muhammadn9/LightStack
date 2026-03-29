import Foundation

// MARK: - Delegate

protocol WorkoutSessionServiceDelegate: AnyObject {
    func sessionServiceDidGeneratePlan(_ service: WorkoutSessionService, exercises: [Exercise])
    func sessionServiceDidReceiveProgressionNote(_ service: WorkoutSessionService, note: String)
    func sessionServiceDidSaveWorkout(_ service: WorkoutSessionService)
    func sessionServiceDidFail(_ service: WorkoutSessionService, error: Error)
}

// MARK: - Request Type

enum SessionRequestType {
    case planGeneration
    case progressionNote
    case contextSummary
}

// MARK: - WorkoutSessionService

/// Owns the business logic for a single workout session:
/// creating a workout record, adding exercises and sets,
/// computing volume, and finalizing with AI progression note.
final class WorkoutSessionService: GeminiServiceDelegate {

    weak var delegate: WorkoutSessionServiceDelegate?

    private let geminiService: GeminiService
    private let coachPromptService: CoachPromptService
    private let coachContextBuilder: CoachContextBuilder
    private let workoutRepository: WorkoutRepository
    private let monthPlanRepository: MonthPlanRepository
    private let localStorage: LocalStorageService
    private let supabaseService: SupabaseService
    private let validationService: ValidationService
    private let offlineQueueManager: OfflineQueueManager

    private var currentRequestType: SessionRequestType = .planGeneration
    private var currentWorkout: Workout?
    private(set) var currentWorkoutId: UUID?
    private var pendingSummaryExercises: [Exercise] = []
    private var pendingSummarySets: [UUID: [WorkoutSet]] = [:]

    var currentWorkoutCreatedAt: Date? {
        currentWorkout?.createdAt
    }

    var currentWorkoutType: String? {
        currentWorkout?.workoutType
    }

    init(
        geminiService: GeminiService,
        coachPromptService: CoachPromptService,
        coachContextBuilder: CoachContextBuilder,
        workoutRepository: WorkoutRepository,
        monthPlanRepository: MonthPlanRepository,
        localStorage: LocalStorageService,
        supabaseService: SupabaseService,
        validationService: ValidationService,
        offlineQueueManager: OfflineQueueManager
    ) {
        self.geminiService = geminiService
        self.coachPromptService = coachPromptService
        self.coachContextBuilder = coachContextBuilder
        self.workoutRepository = workoutRepository
        self.monthPlanRepository = monthPlanRepository
        self.localStorage = localStorage
        self.supabaseService = supabaseService
        self.validationService = validationService
        self.offlineQueueManager = offlineQueueManager

        self.geminiService.delegate = self
    }

    // MARK: - Generate Plan

    func generatePlan(
        userId: UUID,
        workoutType: String,
        time: Int,
        energy: Int,
        notes: String?
    ) {
        currentRequestType = .planGeneration

        let sanitizedType = validationService.sanitizeLabel(workoutType)
        let sanitizedNotes = notes.map { validationService.sanitize($0) }

        // Create workout record immediately so it's available offline
        let workout = Workout.create(
            userId: userId,
            workoutType: sanitizedType,
            energyLevel: energy,
            timeAvailableMinutes: time
        )
        currentWorkout = workout
        currentWorkoutId = workout.id
        workoutRepository.createWorkout(workout)

        Task { @MainActor in
            // Check rate limit before spending an API call
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

            geminiService.generateContent(systemPrompt: systemPrompt, userMessage: userMessage)
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
        currentRequestType = .progressionNote

        // Store for later summary generation
        pendingSummaryExercises = exercises
        pendingSummarySets = allSets

        // Calculate duration
        guard var workout = currentWorkout else { return }
        let durationMinutes = Int(Date().timeIntervalSince(workout.createdAt) / 60)
        workout.durationMinutes = durationMinutes
        workout.userNote = userNote.map { validationService.sanitize($0) }
        currentWorkout = workout

        Task { @MainActor in
            // Check rate limit before spending an API call
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
                // Rate limit check failed — proceed
            }

            let context = coachContextBuilder.buildContext(userId: userId)
            let systemPrompt = coachPromptService.buildSystemPrompt(profile: context.profile)
            let userMessage = coachPromptService.buildPostSessionMessage(
                exercises: exercises,
                sets: allSets
            )

            geminiService.generateContent(systemPrompt: systemPrompt, userMessage: userMessage)
        }
    }

    // MARK: - Save Completed Workout

    func saveCompletedWorkout(userNote: String?, aiNote: String?) {
        guard var workout = currentWorkout else { return }
        workout.userNote = userNote.map { validationService.sanitize($0) }
        workout.aiProgressionNote = aiNote
        workout.syncStatus = .pending
        currentWorkout = workout
        workoutRepository.updateWorkout(workout)

        // Mark today's planned session as completed if it matches
        markMatchingPlannedSessionCompleted(workout: workout)

        // Trigger background context summary generation
        let exercises = pendingSummaryExercises
        let sets = pendingSummarySets
        let workoutType = workout.workoutType
        let userId = workout.userId
        pendingSummaryExercises = []
        pendingSummarySets = [:]

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
        // Use a separate GeminiService instance to avoid delegate conflict
        let summaryGemini = GeminiService()
        let context = coachContextBuilder.buildContext(userId: userId)
        let systemPrompt = coachPromptService.buildSystemPrompt(profile: context.profile)
        let userMessage = coachPromptService.buildContextSummaryMessage(
            workoutType: workoutType,
            exercises: exercises,
            sets: sets
        )

        summaryGemini.generateChatAsync(
            systemPrompt: systemPrompt,
            messages: [ChatMessage(role: .user, content: userMessage)]
        ) { [weak self] result in
            switch result {
            case .success(let summaryText):
                guard let self = self else { return }
                let existing = self.localStorage.fetchContextSummary(userId: userId, workoutType: workoutType)
                let sessionsCovered = (existing != nil ? Int(existing!.sessionsCovered) : 0) + 1

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
                        self.offlineQueueManager.enqueue(.upsertContextSummary, payload: summary)
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

        let lines = text.components(separatedBy: "\n")
        var exercises: [Exercise] = []
        var orderIndex = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip non-table lines
            guard trimmed.hasPrefix("|") && trimmed.hasSuffix("|") else { continue }

            // Split columns
            let columns = trimmed
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }

            // Skip header row and separator row
            guard columns.count >= 4 else { continue }
            if columns[0].lowercased().contains("exercise") { continue }
            if columns[0].contains("---") { continue }

            let name = columns[0]
            guard !name.isEmpty, !name.contains("---") else { continue }

            let setsStr = columns.count > 1 ? columns[1] : ""
            let weightStr = columns.count > 2 ? columns[2] : ""
            let repsStr = columns.count > 3 ? columns[3] : ""
            let rirStr = columns.count > 4 ? columns[4] : ""
            let restStr = columns.count > 5 ? columns[5] : ""

            let targetSets = parseFirstInt(setsStr)
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

    // MARK: - GeminiServiceDelegate

    func geminiService(_ service: GeminiService, didReceiveResponse text: String) {
        switch currentRequestType {
        case .planGeneration:
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

        case .progressionNote:
            delegate?.sessionServiceDidReceiveProgressionNote(self, note: text)

        case .contextSummary:
            // Handled by async callback, not delegate
            break
        }
    }

    func geminiService(_ service: GeminiService, didFailWith error: Error) {
        delegate?.sessionServiceDidFail(self, error: error)
    }

    // MARK: - Private Helpers

    private func parseFirstInt(_ str: String) -> Int? {
        let digits = str.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return Int(digits)
    }

    private func parseRestSeconds(_ str: String) -> Int? {
        guard let value = parseFirstInt(str) else { return nil }
        // If the string contains "min", multiply by 60
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
