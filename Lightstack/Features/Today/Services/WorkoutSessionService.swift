import Foundation
import os

// MARK: - Delegate

protocol WorkoutSessionServiceDelegate: AnyObject {
    func sessionServiceDidGeneratePlan(_ service: WorkoutSessionService, exercises: [Exercise], setTargets: [UUID: [SetTarget]])
    func sessionServiceDidReceiveProgressionNote(_ service: WorkoutSessionService, note: String)
    func sessionServiceDidSaveWorkout(_ service: WorkoutSessionService)
    func sessionServiceDidFail(_ service: WorkoutSessionService, error: Error)
    /// Called just before `sessionServiceDidGeneratePlan` with per-exercise evidence (keyed by exercise id).
    func sessionServiceDidBuildEvidence(_ service: WorkoutSessionService, evidence: [UUID: ExerciseEvidence])
    /// Called just before `sessionServiceDidGeneratePlan` with the coach's plan: summary, one decision per lift,
    /// the checks that ran and the recency heads-up.
    func sessionServiceDidBuildCoachReview(_ service: WorkoutSessionService, review: CoachPlanReview)
}

extension WorkoutSessionServiceDelegate {
    func sessionServiceDidBuildEvidence(_ service: WorkoutSessionService, evidence: [UUID: ExerciseEvidence]) {}
    func sessionServiceDidBuildCoachReview(_ service: WorkoutSessionService, review: CoachPlanReview) {}
}

// MARK: - WorkoutSessionService

/// Owns the business logic for a single workout session:
/// creating a workout record, adding exercises and sets,
/// computing volume, and finalizing with AI progression note.
final class WorkoutSessionService {

    private let logger = Logger(subsystem: "org.lightstack.app", category: "WorkoutSessionService")

    weak var delegate: WorkoutSessionServiceDelegate?

    private let aiServiceManager: AIServiceManager
    private let coachPromptService: CoachPromptService
    private let coachContextBuilder: CoachContextBuilder
    private let workoutRepository: WorkoutRepository
    private let monthPlanRepository: MonthPlanRepository
    private let localStorage: LocalStorageService
    private let validationService: ValidationService
    private let offlineQueueManager: OfflineQueueManager
    private let goalStore: CoachGoalStore

    private(set) var currentWorkout: Workout?
    private(set) var currentWorkoutId: UUID?

    /// Rolling summary from the merged post-workout AI call, held until the
    /// athlete actually saves the workout (a discarded workout stores nothing).
    private var pendingSummary: (userId: UUID, workoutType: String, text: String)?
    private var summaryWantedFor: (userId: UUID, workoutType: String)?
    private var finishToken = UUID()

    /// Fallback feedback for exercises whose last session has none of its own. The UI records
    /// feedback per exercise (`ExerciseFeedbackStore`), which `generatePlan` reads into the history.
    var sessionFeedback: SessionFeedback?

    /// What the plan response needs once it arrives.
    private struct PlanState {
        var userId: UUID
        var workoutId: UUID
        var history: ExerciseHistoryIndex
        var energy: Int
        var minutes: Int
        var coach: PlanCoachContext
        var draft: [DraftExercise]
        var goalItems: [GoalPlanItem]
        var memory: CoachMemoryIndex
    }
    private var planContext: PlanState?

    /// Reads and writes the coach's per-workout document (`Workout.aiProgressionNote`).
    let reviewStore: CoachReviewStore

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
        validationService: ValidationService,
        offlineQueueManager: OfflineQueueManager,
        goalStore: CoachGoalStore = .shared
    ) {
        self.goalStore = goalStore
        self.aiServiceManager = aiServiceManager
        self.coachPromptService = coachPromptService
        self.coachContextBuilder = coachContextBuilder
        self.workoutRepository = workoutRepository
        self.monthPlanRepository = monthPlanRepository
        self.localStorage = localStorage
        self.validationService = validationService
        self.offlineQueueManager = offlineQueueManager
        self.reviewStore = CoachReviewStore(workoutRepository: workoutRepository)
    }

    // MARK: - Coach document

    /// Prescription as it stands when the athlete starts the workout (after any swaps in the preview).
    func recordStartedPlan(exercises: [Exercise], setTargets: [UUID: [SetTarget]]) {
        guard let id = currentWorkoutId else { return }
        let prescription = CoachReviewStore.prescription(exercises: exercises, targets: setTargets)
        guard !prescription.isEmpty else { return }
        if reviewStore.recordPrescription(prescription, for: id) { refreshCurrentWorkoutNote() }
    }

    /// The athlete's answer to "why was that short?" for an exercise of the workout in progress.
    @discardableResult
    func recordInSessionReason(exercise: String, reason: String) -> Bool {
        guard let id = currentWorkoutId else { return false }
        let saved = reviewStore.recordInSessionReason(exercise: exercise, reason: reason, workoutId: id)
        if saved { refreshCurrentWorkoutNote() }
        return saved
    }

    /// The document is written straight to storage; keep the in-memory copy from overwriting it.
    private func refreshCurrentWorkoutNote() {
        guard var workout = currentWorkout,
              let stored = workoutRepository.fetchWorkout(id: workout.id) else { return }
        workout.aiProgressionNote = stored.aiProgressionNote
        currentWorkout = workout
    }

    // MARK: - Generate Plan

    /// - Parameters:
    ///   - time: minutes available. nil = the athlete's usual (median of recent sessions).
    ///   - energy: 1...10. nil = neutral.
    ///   - notes: free text. nil = none.
    ///   - constraints: e.g. "incline smith not available", "fasted". nil = none.
    ///   - focus: nil = the stored preference, else the profile goal, else hypertrophy.
    func generatePlan(
        userId: UUID,
        workoutType: String,
        time: Int? = nil,
        energy: Int? = nil,
        notes: String? = nil,
        constraints: String? = nil,
        focus: CoachFocus? = nil
    ) {
        let sanitizedType = validationService.sanitizeLabel(workoutType)
        let sanitizedNotes = notes.map { validationService.sanitize($0) }
        let sanitizedConstraints = constraints.map { validationService.sanitize($0) }.flatMap { $0.isEmpty ? nil : $0 }

        // Hands-off defaults: usual session length, neutral energy, the profile goal.
        let context = coachContextBuilder.buildContext(userId: userId, workoutType: sanitizedType)
        let resolvedTime = time ?? context.medianSessionMinutes ?? CoachPreferences.fallbackMinutes
        let resolvedEnergy = energy ?? CoachPreferences.neutralEnergy
        let resolvedFocus = CoachPreferences.resolvedFocus(override: focus)

        // Pre-build the workout value. It is only held in memory (so the plan parser
        // has a workout id) and is NOT saved or queued until the plan succeeds: a
        // failed, refused or cancelled generation must leave no empty workout behind.
        let pendingWorkout = Workout.create(
            userId: userId,
            workoutType: sanitizedType,
            energyLevel: resolvedEnergy,
            timeAvailableMinutes: resolvedTime,
            setupNote: sanitizedNotes?.isEmpty == false ? sanitizedNotes : nil
        )

        // Set synchronously so a cancel right after this call cannot be overtaken by the task below.
        currentWorkout = pendingWorkout
        currentWorkoutId = pendingWorkout.id

        Task { @MainActor in
            // The per-user AI rate limit is enforced server-side by the ai-proxy
            // Edge Function; a refusal arrives as the generation error below.
            let history = ExerciseHistoryIndex(
                sessions: context.recentSessions, exercises: context.recentSessionSets,
                loggedSets: context.recentLoggedSets, bestSets: context.bestSets,
                feedbackFor: ExerciseFeedbackStore.reader(workouts: context.recentSessions,
                                                          fallback: { ExerciseFeedbackStore.shared.deviceFeedback(forExercise: $0) }))
            // Active goals: the app's numbers and today's step; an attempt due today lifts the rails for that lift.
            let planNow = Date()
            let goalRepository = workoutRepository
            let goalItems = GoalPlanner.items(
                goals: goalStore.activeGoals(for: userId),
                history: { name in
                    Self.goalHistory(goalRepository, userId: userId, exercise: name, now: planNow)
                },
                now: planNow)
            // Low fuel (only judged when the athlete shares nutrition): the top weights may not rise today.
            let fuelAssessment = FuelRules.assess(fuel: context.fuel, meals: context.meals)
            let coach = PlanCoachContext(
                focus: resolvedFocus, restPreference: RestPreference.defaultSeconds,
                nextTargets: CoachReviewStore.nextTargets(from: context.recentReviews),
                recency: context.muscleRecency, now: planNow,
                goalAllowances: GoalPlanner.allowances(goalItems),
                fuelHold: fuelAssessment.isLow ? fuelAssessment : nil)
            let fuelBlock = coachPromptService.fuelBlock(context.fuel)
            let mealsBlock = coachPromptService.mealsBlock(context.meals)
            let lastExercises = context.recentSessions.first.flatMap { context.recentSessionSets[$0.id] } ?? []
            let draft = PlanDraftBuilder.build(
                lastSessionExercises: lastExercises, history: history, energy: resolvedEnergy,
                feedback: sessionFeedback, coach: coach, timeMinutes: resolvedTime)

            // Goals that matter for this workout, and memory for them and for this type's other lifts.
            let baselineLifts = draft.map { CoachLiftRef(name: $0.name, muscle: $0.muscleGroup) }
            let relevantGoals = GoalPlanner.relevant(goalItems, lifts: baselineLifts)
            var memoryLifts = relevantGoals.map { CoachLiftRef(name: $0.goal.exerciseName, muscle: "") }
            for lift in context.memory.lifts(forWorkoutType: sanitizedType)
            where !memoryLifts.contains(where: { ExerciseNameResolver.isMatch($0.name, lift.name) }) {
                memoryLifts.append(lift)
            }
            let recencyWarning = PlanDraftBuilder.recencyWarning(for: draft, coach: coach)
            let systemPrompt = coachPromptService.buildSystemPrompt(
                profile: context.profile, task: .plan, restSeconds: RestPreference.defaultSeconds)
            let userMessage = coachPromptService.buildWorkoutRequestMessage(
                workoutType: sanitizedType,
                time: resolvedTime,
                energy: resolvedEnergy,
                notes: sanitizedNotes,
                rollingSummary: context.rollingSummary,
                recentSessions: context.recentSessions,
                recentSessionExercises: context.recentSessionSets,
                recentLoggedSets: context.recentLoggedSets,
                bestSets: context.bestSets,
                exerciseLibrary: localStorage.fetchExerciseNameStats(userId: userId).map(\.name),
                coach: CoachPromptService.PlanPromptExtras(
                    focus: resolvedFocus, constraints: sanitizedConstraints, draft: draft,
                    estimatedMinutes: draft.isEmpty ? nil : PlanDraftBuilder.estimatedMinutes(draft),
                    reviews: context.recentReviews, recency: context.muscleRecency, now: coach.now,
                    recencyNote: recencyWarning?.promptNote,
                    briefs: context.briefs(matching: draft), muscleLoad: context.muscleLoad,
                    usualMinutes: context.usualMinutes,
                    fuelBlock: fuelBlock, mealsBlock: mealsBlock,
                    memory: context.memory, memoryLifts: memoryLifts,
                    goalsBlock: coachPromptService.goalsBlock(relevantGoals, now: planNow))
            )

            planContext = PlanState(userId: userId, workoutId: pendingWorkout.id, history: history, energy: resolvedEnergy,
                                    minutes: resolvedTime, coach: coach, draft: draft, goalItems: goalItems,
                                    memory: context.memory)
            var planOptions = AIRequestOptions.forTask(.plan)
            planOptions.schema = CoachPromptService.planResponseSchema
            CoachDebugStore.shared.recordRequest(
                userId: userId, workoutType: sanitizedType, model: aiServiceManager.activeProviderName,
                systemPromptName: "plan", systemPromptLength: systemPrompt.count, userMessage: userMessage,
                nutritionShared: CoachPreferences.shareNutritionSummary,
                mealsShared: CoachPreferences.sharePreWorkoutMeals,
                fuelBlock: fuelBlock, mealsBlock: mealsBlock,
                scorecard: CoachScorecard.compute(memory: context.memory).line)

            aiServiceManager.generateChat(
                systemPrompt: systemPrompt,
                messages: [ChatMessage(role: .user, content: userMessage)],
                options: planOptions
            ) { [weak self] result in
                guard let self = self else { return }
                // Cancelled or replaced while the AI was thinking: drop the result.
                guard self.currentWorkoutId == pendingWorkout.id else { return }
                switch result {
                case .success(let responseText):
                    self.handleWorkoutPlanResponse(responseText)
                case .failure(let error):
                    // The coach could not be reached: the app's own plan from the log still works.
                    if let state = self.planContext, !state.draft.isEmpty {
                        self.completePlan(reply: nil, raw: "(no reply: \(error.localizedDescription))")
                    } else {
                        self.discardUnsavedPlanWorkout()
                        self.delegate?.sessionServiceDidFail(self, error: error)
                    }
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

    /// Re-attach to a workout restored from saved session state. Its exercises
    /// are already in storage, so unlike `startSession` nothing is saved —
    /// re-saving here created a duplicate copy on every app relaunch.
    func resumeSession(workout: Workout) {
        currentWorkout = workout
        currentWorkoutId = workout.id
    }

    /// Forget the current workout once it has been saved or discarded, so it is
    /// no longer treated as in progress.
    func clearCurrentWorkout() {
        currentWorkout = nil
        currentWorkoutId = nil
        // A saved workout may still be waiting for its summary; a discarded one is not.
        pendingSummary = nil
        if summaryWantedFor == nil { finishToken = UUID() }
    }

    // MARK: - Log Set

    func logSet(_ workoutSet: WorkoutSet, exerciseId: UUID) {
        workoutRepository.saveSet(workoutSet, exerciseId: exerciseId)
    }

    // MARK: - Finish Session

    /// Whole minutes for a finished workout. Prefers the active timer (excludes paused time),
    /// falls back to time since creation. Rounds, and never returns 0 so it isn't read as "no duration".
    static func durationMinutes(activeSeconds: Int?, createdAt: Date, now: Date = Date()) -> Int {
        let seconds: Double
        if let activeSeconds, activeSeconds > 0 {
            seconds = Double(activeSeconds)
        } else {
            seconds = max(0, now.timeIntervalSince(createdAt))
        }
        return max(1, Int((seconds / 60).rounded()))
    }

    /// - Parameter prescribedTargets: the per-set targets on screen (used for prescribed-vs-actual);
    ///   the prescription stored when the workout started is the fallback.
    func finishSession(
        userId: UUID,
        userNote: String?,
        exercises: [Exercise],
        allSets: [UUID: [WorkoutSet]],
        activeSeconds: Int? = nil,
        prescribedTargets: [UUID: [SetTarget]] = [:]
    ) {
        guard var workout = currentWorkout else { return }
        workout.durationMinutes = Self.durationMinutes(activeSeconds: activeSeconds, createdAt: workout.createdAt)
        workout.userNote = userNote.map { validationService.sanitize($0) }
        // The coach document (prescription, in-session answers) lives in storage; keep it.
        if let stored = workoutRepository.fetchWorkout(id: workout.id) { workout.aiProgressionNote = stored.aiProgressionNote }
        currentWorkout = workout

        // Persist duration immediately — if the app is backgrounded/killed while
        // waiting for the AI note, the duration is already saved in Core Data.
        workoutRepository.updateWorkout(workout)

        // One AI call returns the structured review; Swift's rules back it up.
        let token = UUID()
        finishToken = token
        pendingSummary = nil
        summaryWantedFor = nil
        let workoutType = workout.workoutType
        let workoutId = workout.id
        let energy = workout.energyLevel ?? CoachPreferences.neutralEnergy
        let document = CoachReviewDocument.parse(workout.aiProgressionNote) ?? CoachReviewDocument()
        let fresh = CoachReviewStore.prescription(exercises: exercises, targets: prescribedTargets)
        let prescription = document.prescription.map { stored in
            fresh.first { ExerciseNameResolver.isMatch($0.name, stored.name) } ?? stored
        } + fresh.filter { f in !document.prescription.contains { ExerciseNameResolver.isMatch($0.name, f.name) } }
        // Goals met by a logged set today are marked achieved now and mentioned in the review.
        let achievedGoals = GoalPlanner.achieved(
            goals: goalStore.activeGoals(for: userId), exercises: exercises, sets: allSets)
        for goal in achievedGoals { goalStore.setStatus(.achieved, goalId: goal.id, for: userId) }
        let logged = exercises.filter { $0.trackingType != .cardio }.map { ex in
            LoggedExercise(
                name: ex.name, muscleGroup: ex.muscleGroup,
                sets: (allSets[ex.id] ?? []).sorted { $0.setNumber < $1.setNumber }.map { HistorySet($0) },
                // Flagged when logged, i.e. against the PR as it stood before today (the stored PR is
                // overwritten mid-workout, so the analyzer cannot compare against it at the end).
                hitPR: (allSets[ex.id] ?? []).contains { $0.isPR && $0.reps > 0 })
        }

        Task { @MainActor in
            let context = coachContextBuilder.buildContext(
                userId: userId, workoutType: workoutType, includeHistory: true, excludingWorkoutId: workoutId,
                fuelAt: workout.createdAt)
            let history = ExerciseHistoryIndex(
                sessions: context.recentSessions, exercises: context.recentSessionSets,
                loggedSets: context.recentLoggedSets, bestSets: context.bestSets,
                feedbackFor: ExerciseFeedbackStore.reader(workouts: context.recentSessions,
                                                          fallback: { ExerciseFeedbackStore.shared.deviceFeedback(forExercise: $0) }))
            let focus = CoachPreferences.resolvedFocus()
            let analysis = SessionAnalyzer.analyze(
                logged: logged, prescription: prescription, energy: energy, userNote: workout.userNote,
                reasons: document.inSessionReasons, previous: context.recentReviews, history: history, focus: focus,
                now: Date(), fuel: FuelRules.assess(fuel: context.fuel, meals: context.meals))
            // The coach's last note per lift: shown to the model to rewrite, and kept if it does not.
            let previousNotes: [String: String] = analysis.exercises.reduce(into: [:]) { result, a in
                if let note = context.memory.note(for: a.name) { result[a.name] = note }
            }
            let systemPrompt = coachPromptService.buildSystemPrompt(profile: context.profile, task: .postWorkout)
            let userMessage = coachPromptService.buildPostWorkoutMessage(
                workoutType: workoutType,
                exercises: exercises,
                sets: allSets,
                previousSummary: context.rollingSummary,
                analysis: analysis,
                previousReviews: context.recentReviews,
                userNote: workout.userNote,
                previousNotes: previousNotes,
                achievedGoals: achievedGoals,
                fuelBlock: coachPromptService.fuelBlock(context.fuel),
                mealsBlock: coachPromptService.mealsBlock(context.meals)
            )

            aiServiceManager.generateChat(
                systemPrompt: systemPrompt,
                messages: [ChatMessage(role: .user, content: userMessage)],
                expectsJSON: true,
                options: .forTask(.postWorkout)
            ) { [weak self] result in
                guard let self = self else { return }
                var model: ModelReview?
                if case .success(let responseText) = result { model = Self.modelReview(from: responseText) }
                var review = SessionAnalyzer.merge(analysis, model: model, workoutType: workoutType, previousNotes: previousNotes)
                if !achievedGoals.isEmpty {
                    review.overallRead = GoalPlanner.read(review.overallRead, withAchieved: achievedGoals)
                }
                if !analysis.exercises.isEmpty {
                    self.reviewStore.recordReview(review, prescription: prescription, analysis: analysis, for: workoutId)
                    self.refreshCurrentWorkoutNote()
                }
                if self.finishToken == token, !exercises.isEmpty, !analysis.exercises.isEmpty {
                    self.receiveSummary(
                        userId: userId, workoutType: workoutType,
                        text: SessionAnalyzer.rollingSummary(review: review, workoutType: workoutType, previous: context.rollingSummary))
                }
                // Only a model-written review is shown; a rules-only one just drives next session's targets.
                var shown = CoachReviewDocument()
                shown.review = review
                self.handleProgressionNoteResponse(review.aiAuthored ? (shown.displayText ?? "") : "")
            }
        }
    }

    /// The best working set of each of the lift's sessions in the last half year, for goal checks.
    static func goalHistory(_ repository: WorkoutRepository, userId: UUID, exercise: String,
                            now: Date = Date()) -> [GoalAssessor.Point] {
        let cutoff = now.addingTimeInterval(-180 * 86_400)
        var sessions: [HistorySession] = []
        for workout in repository.fetchRecentWorkouts(userId: userId, limit: 80) where workout.date >= cutoff {
            var sets: [HistorySet] = []
            for item in repository.fetchExercises(workoutId: workout.id)
            where item.trackingType != .cardio && ExerciseNameResolver.isMatch(item.name, exercise) {
                let logged = repository.fetchSets(exerciseId: item.id).sorted { $0.setNumber < $1.setNumber }
                sets += logged.map { HistorySet($0.weightLbs, $0.reps, rir: $0.rir) }
            }
            if !sets.isEmpty { sessions.append(HistorySession(date: workout.date, sets: sets)) }
        }
        return GoalAssessor.topPoints(from: sessions)
    }

    /// The model's review, or its prose reply wrapped as an overall read.
    static func modelReview(from text: String) -> ModelReview? {
        if let parsed = ModelReview.parse(text) { return parsed }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("{"), !trimmed.hasPrefix("[") else { return nil }
        return ModelReview(exercises: [], overallRead: InputSanitizer.clipAtWord(trimmed, limit: 600), recurringFlags: [])
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
        // Keep the coach document in storage (prescription, review); a plain note only fills in
        // when there is no review, and is stored as a legacy note.
        if let stored = workoutRepository.fetchWorkout(id: workout.id) { workout.aiProgressionNote = stored.aiProgressionNote }
        let document = CoachReviewDocument.parse(workout.aiProgressionNote)
        if document?.review == nil, let aiNote, !aiNote.isEmpty {
            var legacy = document ?? CoachReviewDocument()
            legacy.legacyNote = aiNote
            workout.aiProgressionNote = legacy.encoded() ?? aiNote
        }
        workout.syncStatus = .pending
        currentWorkout = workout
        workoutRepository.updateWorkout(workout)

        // Reconcile: delete any Core Data exercises that were removed by the user
        let storedExercises = workoutRepository.fetchExercises(workoutId: workout.id)
        let finalIds = Set(exercises.map { $0.id })
        let doomed = Self.exerciseIdsToDelete(
            stored: storedExercises,
            keeping: finalIds,
            hasLoggedSets: { id in
                !(sets[id]?.isEmpty ?? true) || !self.workoutRepository.fetchSets(exerciseId: id).isEmpty
            }
        )
        for id in doomed {
            workoutRepository.deleteExercise(id)
        }

        markMatchingPlannedSessionCompleted(workout: workout)

        let workoutType = workout.workoutType
        let userId = workout.userId

        // The summary came with the post-workout note; store it now that the
        // workout is saved (or as soon as it arrives, if it is still on its way).
        if !exercises.isEmpty {
            summaryWantedFor = (userId, workoutType)
            if let pending = pendingSummary {
                pendingSummary = nil
                storeSummary(userId: pending.userId, workoutType: pending.workoutType, text: pending.text)
            }
        }

        delegate?.sessionServiceDidSaveWorkout(self)
    }

    /// Exercises that have at least one logged set. Others were never worked and are
    /// dropped when the workout finishes.
    static func exercisesWithLoggedSets(_ exercises: [Exercise], sets: [UUID: [WorkoutSet]]) -> [Exercise] {
        exercises.filter { !(sets[$0.id]?.isEmpty ?? true) }
    }

    /// Stored exercises that may be deleted at finish: not in the final list AND with no
    /// logged sets. An exercise with sets is real history and is never deleted here.
    static func exerciseIdsToDelete(
        stored: [Exercise],
        keeping finalIds: Set<UUID>,
        hasLoggedSets: (UUID) -> Bool
    ) -> [UUID] {
        stored.filter { !finalIds.contains($0.id) && !hasLoggedSets($0.id) }.map(\.id)
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

    private func receiveSummary(userId: UUID, workoutType: String, text: String) {
        if let wanted = summaryWantedFor, wanted.userId == userId, wanted.workoutType == workoutType {
            summaryWantedFor = nil
            storeSummary(userId: userId, workoutType: workoutType, text: text)
        } else {
            pendingSummary = (userId, workoutType, text)
        }
    }

    private func storeSummary(userId: UUID, workoutType: String, text: String) {
        let existing = localStorage.fetchContextSummary(userId: userId, workoutType: workoutType)
        let sessionsCovered = existing.map { Int($0.sessionsCovered) + 1 } ?? 1

        let summary = AIContextSummary.create(
            userId: userId,
            workoutType: workoutType,
            summaryText: text,
            sessionsCovered: sessionsCovered
        )
        localStorage.saveContextSummary(summary)

        offlineQueueManager.submit(
            .upsertContextSummary, payload: summary, recordKey: "\(userId.uuidString)|\(workoutType)"
        )
    }

    // MARK: - Response Handlers

    /// Turns the coach's reply into the plan: the engine's numbers, the coach's decisions, the checks.
    private func handleWorkoutPlanResponse(_ text: String) {
        let reply = CoachPlanReply.parse(text)
        if reply == nil, let userId = planContext?.userId {
            CoachDebugStore.shared.recordResponse(userId: userId, raw: text, adjustments: ["The reply could not be read as a plan"])
        }
        completePlan(reply: reply, raw: text)
    }

    /// Applies the decisions (nil reply = the app's own plan), tells the delegate, saves the plan.
    private func completePlan(reply: CoachPlanReply?, raw: String) {
        guard let state = planContext else {
            discardUnsavedPlanWorkout()
            delegate?.sessionServiceDidFail(self, error: Self.planError)
            return
        }
        if reply == nil && state.draft.isEmpty {
            discardUnsavedPlanWorkout()
            delegate?.sessionServiceDidFail(self, error: Self.planError)
            return
        }
        let storage = localStorage
        let userId = state.userId
        let context = PlanDecisionContext(
            workoutId: state.workoutId, draft: state.draft, history: state.history, coach: state.coach, energy: state.energy,
            feedback: sessionFeedback, timeMinutes: state.minutes, goalItems: state.goalItems, memory: state.memory,
            canonicalName: { name in
                let stats = storage.fetchExerciseNameStats(userId: userId)
                return ExerciseNameResolver.canonicalName(for: name, existing: stats.map { ($0.name, $0.setCount) })
            },
            sanitizeLabel: { [validationService] in validationService.sanitizeLabel($0) })
        let applied = CoachDecisionApplier.apply(reply: reply, context: context)
        guard !applied.exercises.isEmpty else {
            discardUnsavedPlanWorkout()
            delegate?.sessionServiceDidFail(self, error: Self.planError)
            return
        }
        CoachDebugStore.shared.recordResponse(
            userId: userId, raw: raw, adjustments: applied.adjustments + applied.review.logLines,
            review: applied.review, reasons: applied.reasons.isEmpty ? nil : applied.reasons)
        delegate?.sessionServiceDidBuildEvidence(self, evidence: applied.evidence)
        if !applied.review.isEmpty { delegate?.sessionServiceDidBuildCoachReview(self, review: applied.review) }
        finalizePlan(applied.exercises, setTargets: applied.setTargets, review: applied.review.isEmpty ? nil : applied.review,
                     applied: applied)
    }

    private static let planError = NSError(
        domain: "WorkoutSessionService", code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Could not build a workout plan"])

    /// Forget the in-memory workout of a generation that produced no plan. Nothing was
    /// saved locally or queued for it, so there is nothing else to remove.
    private func discardUnsavedPlanWorkout() {
        currentWorkout = nil
        currentWorkoutId = nil
    }

    /// The plan succeeded: only now is the workout saved (and queued), followed by its
    /// exercises. The workout is brand new, so there is nothing to clear first.
    private func finalizePlan(_ exercises: [Exercise], setTargets: [UUID: [SetTarget]] = [:], review: CoachPlanReview? = nil,
                              applied: AppliedPlan? = nil) {
        if var workout = currentWorkout {
            // The prescription and the coach's plan ride along in the coach document.
            let prescription = CoachReviewStore.prescription(exercises: exercises, targets: setTargets)
            if !prescription.isEmpty || review != nil {
                var document = CoachReviewDocument()
                document.prescription = prescription
                document.planReview = review
                // The coach's calls and why, so the next plan can see how they turned out.
                if let applied {
                    document.decisions = CoachReviewStore.decisions(
                        prescription: prescription, exercises: exercises, lifts: applied.review.decisions,
                        evidence: applied.evidence, energy: planContext?.energy, engineOnly: applied.review.engineOnly)
                }
                workout.aiProgressionNote = document.encoded()
                currentWorkout = workout
            }
            workoutRepository.createWorkout(workout)
            workoutRepository.saveExercises(exercises, workoutId: workout.id)
            // Regenerating replaces earlier unstarted plans for the same day.
            StaleWorkoutCleanup(localStorage: localStorage, workoutRepository: workoutRepository)
                .removeSupersededPlans(userId: workout.userId, newPlanId: workout.id)
        }
        delegate?.sessionServiceDidGeneratePlan(self, exercises: exercises, setTargets: setTargets)
    }

    private func handleProgressionNoteResponse(_ text: String) {
        let clean = extractProgressionNote(from: text)
        delegate?.sessionServiceDidReceiveProgressionNote(self, note: clean)
    }

    /// Extracts a plain-prose progression note from the AI response.
    ///
    /// Input shapes handled:
    /// - Plain prose (happy path): trimmed and returned as-is.
    /// - Fenced JSON (```json { ... } ```): fences stripped, then JSON decoded.
    /// - Bare JSON object/array: decoded directly.
    /// - JSON that decodes but has no usable `coaching_notes`: returns "".
    /// - Anything that looks like JSON but cannot be decoded: returns "".
    private func extractProgressionNote(from text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Strip markdown code fences if present
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            trimmed = lines.dropFirst().dropLast().joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // If it doesn't look like JSON, it's plain prose — pass through
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else {
            return trimmed
        }

        // Looks like JSON — attempt to extract coaching_notes
        guard let data = trimmed.data(using: .utf8) else {
            logger.warning("Progression note looked like JSON but couldn't be encoded to data — hiding card")
            return ""
        }

        // Try to decode as the known workout plan schema (has coaching_notes key)
        if let decoded = try? JSONDecoder().decode(ProgressionNoteEnvelope.self, from: data),
           let note = decoded.coachingNotes, !note.isEmpty {
            logger.debug("Progression note extracted from JSON coaching_notes field")
            return note.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try to decode as a bare JSON string value
        if let decoded = try? JSONDecoder().decode(String.self, from: data), !decoded.isEmpty {
            logger.debug("Progression note extracted from bare JSON string")
            return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        logger.warning("Progression note was JSON but coaching_notes couldn't be extracted — hiding card")
        return ""
    }

    // MARK: - Private Helpers

    static func inferMuscleGroup(_ exerciseName: String) -> String {
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

/// Minimal envelope for defensive parsing of a progression note response that
/// accidentally came back as JSON (matches the workout-plan schema's top-level keys).
private struct ProgressionNoteEnvelope: Decodable {
    let coachingNotes: String?
    enum CodingKeys: String, CodingKey {
        case coachingNotes = "coaching_notes"
    }
}
