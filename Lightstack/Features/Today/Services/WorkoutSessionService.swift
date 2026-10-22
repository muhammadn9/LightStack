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
    /// Called just before `sessionServiceDidGeneratePlan` with the coach's structure review
    /// (verdict, summary, the changes it proposed and whether each was applied, deterministic safeguards).
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
        var history: ExerciseHistoryIndex
        var energy: Int
        var coach: PlanCoachContext
        var draft: [DraftExercise]
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
        offlineQueueManager: OfflineQueueManager
    ) {
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
        let resolvedFocus = CoachPreferences.resolvedFocus(override: focus, profileGoals: context.profile?.primaryGoals ?? [])

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
                feedbackFor: { ExerciseFeedbackStore.shared.feedback(forExercise: $0) })
            let coach = PlanCoachContext(
                focus: resolvedFocus, restPreference: RestPreference.defaultSeconds,
                nextTargets: CoachReviewStore.nextTargets(from: context.recentReviews),
                recency: context.muscleRecency, now: Date())
            let lastExercises = context.recentSessions.first.flatMap { context.recentSessionSets[$0.id] } ?? []
            let draft = PlanDraftBuilder.build(
                lastSessionExercises: lastExercises, history: history, energy: resolvedEnergy,
                feedback: sessionFeedback, coach: coach, timeMinutes: resolvedTime)

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
                coach: CoachPromptService.PlanPromptExtras(
                    focus: resolvedFocus, constraints: sanitizedConstraints, draft: draft,
                    estimatedMinutes: draft.isEmpty ? nil : PlanDraftBuilder.estimatedMinutes(draft),
                    reviews: context.recentReviews, recency: context.muscleRecency, now: coach.now)
            )

            planContext = PlanState(userId: userId, history: history, energy: resolvedEnergy, coach: coach, draft: draft)
            CoachDebugStore.shared.recordRequest(
                userId: userId, workoutType: sanitizedType, model: aiServiceManager.activeProviderName,
                systemPromptName: "plan", systemPromptLength: systemPrompt.count, userMessage: userMessage)

            aiServiceManager.generateChat(
                systemPrompt: systemPrompt,
                messages: [ChatMessage(role: .user, content: userMessage)],
                options: .forTask(.plan)
            ) { [weak self] result in
                guard let self = self else { return }
                // Cancelled or replaced while the AI was thinking: drop the result.
                guard self.currentWorkoutId == pendingWorkout.id else { return }
                switch result {
                case .success(let responseText):
                    self.handleWorkoutPlanResponse(responseText)
                case .failure(let error):
                    self.discardUnsavedPlanWorkout()
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
        let logged = exercises.filter { $0.trackingType != .cardio }.map { ex in
            LoggedExercise(
                name: ex.name, muscleGroup: ex.muscleGroup,
                sets: (allSets[ex.id] ?? []).sorted { $0.setNumber < $1.setNumber }.map { HistorySet($0) })
        }

        Task { @MainActor in
            let context = coachContextBuilder.buildContext(
                userId: userId, workoutType: workoutType, includeHistory: true, excludingWorkoutId: workoutId)
            let history = ExerciseHistoryIndex(
                sessions: context.recentSessions, exercises: context.recentSessionSets,
                loggedSets: context.recentLoggedSets, bestSets: context.bestSets,
                feedbackFor: { ExerciseFeedbackStore.shared.feedback(forExercise: $0) })
            let focus = CoachPreferences.resolvedFocus(profileGoals: context.profile?.primaryGoals ?? [])
            let analysis = SessionAnalyzer.analyze(
                logged: logged, prescription: prescription, energy: energy, userNote: workout.userNote,
                reasons: document.inSessionReasons, previous: context.recentReviews, history: history, focus: focus)
            let systemPrompt = coachPromptService.buildSystemPrompt(profile: context.profile, task: .postWorkout)
            let userMessage = coachPromptService.buildPostWorkoutMessage(
                workoutType: workoutType,
                exercises: exercises,
                sets: allSets,
                previousSummary: context.rollingSummary,
                analysis: analysis,
                previousReviews: context.recentReviews,
                userNote: workout.userNote
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
                let review = SessionAnalyzer.merge(analysis, model: model, workoutType: workoutType)
                if !analysis.exercises.isEmpty {
                    self.reviewStore.recordReview(review, prescription: prescription, for: workoutId)
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

    /// The model's review, or its prose reply wrapped as an overall read.
    static func modelReview(from text: String) -> ModelReview? {
        if let parsed = ModelReview.parse(text) { return parsed }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("{"), !trimmed.hasPrefix("[") else { return nil }
        return ModelReview(exercises: [], overallRead: String(trimmed.prefix(600)), recurringFlags: [])
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
                muscleGroup = WorkoutSessionService.inferMuscleGroup(name)
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
                restSeconds: RestPreference.seconds(forMuscleGroup: muscleGroup, existing: restSeconds),
                coachNote: weightStr.isEmpty ? nil : "Target: \(weightStr)"
            )
            exercises.append(exercise)
            orderIndex += 1
        }

        return exercises
    }

    // MARK: - JSON Parser

    func parseWorkoutPlanJSON(_ text: String) -> ParsedPlan? {
        guard let workoutId = currentWorkoutId else { return nil }
        return Self.plan(
            fromPlanJSON: text,
            workoutId: workoutId,
            sanitizeLabel: { self.validationService.sanitizeLabel($0) }
        )
    }

    /// A decoded plan: the exercises plus the coach's per-set targets (keyed by exercise id;
    /// only exercises that came with `set_targets` have an entry).
    struct ParsedPlan {
        var exercises: [Exercise]
        var setTargets: [UUID: [SetTarget]]
        /// Form cues the coach attached to exercises with known form issues, keyed by exercise id.
        var cues: [UUID: String] = [:]
    }

    /// Pure plan-JSON decoding, kept separate so it can be tested without a session.
    static func exercises(
        fromPlanJSON text: String,
        workoutId: UUID,
        sanitizeLabel: (String) -> String
    ) -> [Exercise]? {
        plan(fromPlanJSON: text, workoutId: workoutId, sanitizeLabel: sanitizeLabel)?.exercises
    }

    /// Weight text for the exercise-level "Target:" note when only per-set targets exist:
    /// the heaviest set's weight, with " lbs" added to a bare number.
    private static func topWeight(of targets: [SetTarget]) -> String? {
        let best = targets.compactMap { t -> (Double, String)? in
            guard let raw = t.weight?.trimmingCharacters(in: .whitespaces), !raw.isEmpty,
                  let value = Double(t.prefillWeight) else { return nil }
            return (value, raw)
        }.max { $0.0 < $1.0 }
        guard let raw = best?.1 else { return nil }
        return Double(raw) != nil ? "\(raw) lbs" : raw
    }

    static func plan(
        fromPlanJSON text: String,
        workoutId: UUID,
        sanitizeLabel: (String) -> String
    ) -> ParsedPlan? {
        let logger = Logger(subsystem: "org.lightstack.app", category: "WorkoutSessionService")

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
            logger.error("JSON parse failed: \(String(describing: error))")
            return nil
        }

        guard !decoded.exercises.isEmpty else { return nil }

        // Same "superset" label within the plan -> same new group id.
        let usable = decoded.exercises.filter {
            !sanitizeLabel($0.name).isEmpty && $0.sets > 0
        }
        let groupIds = SupersetGroup.groupIds(forLabels: usable.map(\.superset))

        var exercises: [Exercise] = []
        var perSetTargets: [UUID: [SetTarget]] = [:]
        var cues: [UUID: String] = [:]
        for (index, aiEx) in usable.enumerated() {
            let name = sanitizeLabel(aiEx.name)
            let targets = aiEx.setTargets.map { SetTarget(weight: $0.weight, reps: $0.reps, rir: $0.rir) }
            let topSet = targets.max { (Double($0.prefillWeight) ?? 0) < (Double($1.prefillWeight) ?? 0) }

            // Preserve "Target: {weight}" prefix convention that
            // ActiveWorkoutViewModel.prefillWeightValue depends on
            let exerciseWeight = aiEx.targetWeight.flatMap { $0.isEmpty ? nil : $0 } ?? topWeight(of: targets)
            let weightNote = exerciseWeight.map { "Target: \($0)" }
            let mergedNote: String?
            switch (weightNote, aiEx.coachNote) {
            case let (w?, c?): mergedNote = "\(w) — \(c)"
            case let (w?, nil): mergedNote = w
            case let (nil, c?): mergedNote = c
            case (nil, nil):    mergedNote = nil
            }

            let muscleGroup = aiEx.muscleGroup.isEmpty ? inferMuscleGroup(name) : aiEx.muscleGroup

            let exercise = Exercise.create(
                workoutId: workoutId,
                name: name,
                muscleGroup: muscleGroup,
                orderIndex: index,
                targetSets: aiEx.sets,
                targetReps: aiEx.reps ?? topSet?.reps,
                targetRir: aiEx.rir ?? topSet?.rir,
                restSeconds: RestPreference.seconds(forMuscleGroup: muscleGroup, existing: aiEx.restSeconds),
                coachNote: mergedNote,
                supersetGroupId: groupIds[index]
            )
            exercises.append(exercise)
            if !targets.isEmpty { perSetTargets[exercise.id] = targets }
            if let cue = aiEx.cue?.trimmingCharacters(in: .whitespacesAndNewlines), !cue.isEmpty {
                cues[exercise.id] = sanitizeLabel(cue)
            }
        }
        // Members of a label are pulled together; out-of-range groups are dropped.
        exercises = SupersetGroup.normalized(exercises)
        guard !exercises.isEmpty else { return nil }
        let kept = Set(exercises.map(\.id))
        return ParsedPlan(exercises: exercises, setTargets: perSetTargets.filter { kept.contains($0.key) },
                          cues: cues.filter { kept.contains($0.key) })
    }

    // MARK: - Response Handlers

    private func handleWorkoutPlanResponse(_ text: String) {
        let review = CoachPlanReview.parse(fromReply: text)
        // Primary path: JSON
        if let parsed = parseWorkoutPlanJSON(text) {
            logger.debug("JSON parse succeeded: \(parsed.exercises.count) exercises")
            completePlan(parsed, review: review, raw: text)
            return
        }
        if let userId = planContext?.userId {
            CoachDebugStore.shared.recordResponse(userId: userId, raw: text, adjustments: ["Plan JSON could not be parsed"])
        }
        // Fallback: markdown table (zero regression during rollout)
        logger.debug("JSON parse failed, attempting markdown fallback")
        let fallback = parseExerciseTable(text)
        if !fallback.isEmpty {
            logger.debug("Markdown fallback succeeded: \(fallback.count) exercises")
            finalizePlan(fallback)
            return
        }
        // Last resort: the app's own draft from the last session, so a flaky reply never blocks a workout.
        if let state = planContext, !state.draft.isEmpty, let workoutId = currentWorkoutId {
            let parsed = PlanDraftBuilder.parsedPlan(from: state.draft, workoutId: workoutId)
            let note = CoachPlanReview(
                verdict: .sound, summary: "The coach's review was unavailable, so this plan is built from your last session.",
                changes: [])
            completePlan(parsed, review: note, raw: text)
            return
        }
        discardUnsavedPlanWorkout()
        delegate?.sessionServiceDidFail(self, error: NSError(
            domain: "WorkoutSessionService", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Could not parse workout plan from AI response"]
        ))
    }

    /// Applies the app's numbers and the coach's review edits, tells the delegate, saves the plan.
    private func completePlan(_ parsed: ParsedPlan, review: CoachPlanReview?, raw: String) {
        let applied = applyProgression(to: parsed, changes: review?.changes ?? [])
        let final = CoachPlanReview(
            verdict: review?.verdict ?? .sound, summary: review?.summary ?? "",
            changes: applied.changes.isEmpty ? (review?.changes ?? []) : applied.changes,
            safeguards: applied.safeguards)
        if let userId = planContext?.userId {
            CoachDebugStore.shared.recordResponse(
                userId: userId, raw: raw, adjustments: applied.adjustments + final.logLines, review: final.isEmpty ? nil : final)
        }
        delegate?.sessionServiceDidBuildEvidence(self, evidence: applied.evidence)
        if !final.isEmpty { delegate?.sessionServiceDidBuildCoachReview(self, review: final) }
        finalizePlan(applied.exercises, setTargets: applied.setTargets, review: final.isEmpty ? nil : final)
    }

    /// The app's own numbers replace the AI's where history exists; guardrails cover the rest.
    private func applyProgression(to parsed: ParsedPlan, changes: [PlanChange]) -> AppliedPlan {
        guard let context = planContext else {
            return AppliedPlan(exercises: parsed.exercises, setTargets: parsed.setTargets, evidence: [:], adjustments: [])
        }
        let storage = localStorage
        let userId = context.userId
        return PlanProgressionApplier.apply(
            plan: parsed,
            history: context.history,
            energy: context.energy,
            feedback: sessionFeedback,
            bestLookup: { name in
                storage.fetchPersonalRecord(userId: userId, exerciseName: name).map { PersonalRecord(from: $0).weightLbs }
            },
            coach: context.coach,
            changes: changes
        )
    }

    /// Forget the in-memory workout of a generation that produced no plan. Nothing was
    /// saved locally or queued for it, so there is nothing else to remove.
    private func discardUnsavedPlanWorkout() {
        currentWorkout = nil
        currentWorkoutId = nil
    }

    /// The plan succeeded: only now is the workout saved (and queued), followed by its
    /// exercises. The workout is brand new, so there is nothing to clear first.
    private func finalizePlan(_ exercises: [Exercise], setTargets: [UUID: [SetTarget]] = [:], review: CoachPlanReview? = nil) {
        if var workout = currentWorkout {
            // The prescription and the structure review ride along in the coach document.
            let prescription = CoachReviewStore.prescription(exercises: exercises, targets: setTargets)
            if !prescription.isEmpty || review != nil {
                var document = CoachReviewDocument()
                document.prescription = prescription
                document.planReview = review
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

private struct WorkoutPlanResponse: Decodable {
    let exercises: [AIExercise]
    let coachingNotes: String?
    enum CodingKeys: String, CodingKey {
        case exercises
        case coachingNotes = "coaching_notes"
    }
}

/// One entry of `set_targets`. Values may arrive as strings or numbers.
private struct AISetTarget: Decodable {
    let weight: String?
    let reps: String?
    let rir: String?
    enum CodingKeys: String, CodingKey { case weight, reps, rir }

    private static func text(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return s.isEmpty ? nil : s }
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return String(format: "%g", d) }
        return nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weight = Self.text(c, .weight)
        reps = Self.text(c, .reps)
        rir = Self.text(c, .rir)
    }
}

private struct AIExercise: Decodable {
    let name: String
    let muscleGroup: String
    let sets: Int
    /// Optional per-set targets; empty when absent or malformed. When present, `sets` is their count.
    let setTargets: [AISetTarget]
    let targetWeight: String?
    let reps: String?
    let rir: String?
    let restSeconds: Int?
    let coachNote: String?
    /// A form cue, only for known form issues.
    let cue: String?
    /// Optional label; exercises sharing one form a superset.
    let superset: String?
    enum CodingKeys: String, CodingKey {
        case name, sets, reps, rir, superset, cue
        case setTargets   = "set_targets"
        case muscleGroup  = "muscle_group"
        case targetWeight = "target_weight"
        case restSeconds  = "rest_seconds"
        case coachNote    = "coach_note"
    }
}

extension AIExercise {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        muscleGroup = (try? c.decodeIfPresent(String.self, forKey: .muscleGroup)) ?? ""
        // A malformed set_targets must not sink the whole plan: fall back to the single fields.
        let targets = (try? c.decodeIfPresent([AISetTarget].self, forKey: .setTargets)) ?? []
        setTargets = targets
        // The review format omits "sets" for kept exercises (the app fills the numbers).
        sets = targets.isEmpty ? ((try? c.decodeIfPresent(Int.self, forKey: .sets)) ?? 3) : targets.count
        targetWeight = try c.decodeIfPresent(String.self, forKey: .targetWeight)
        reps = try c.decodeIfPresent(String.self, forKey: .reps)
        rir = try c.decodeIfPresent(String.self, forKey: .rir)
        restSeconds = try c.decodeIfPresent(Int.self, forKey: .restSeconds)
        coachNote = try c.decodeIfPresent(String.self, forKey: .coachNote)
        cue = try c.decodeIfPresent(String.self, forKey: .cue)
        superset = try c.decodeIfPresent(String.self, forKey: .superset)
    }
}
