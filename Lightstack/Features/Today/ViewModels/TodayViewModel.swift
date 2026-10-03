import Foundation
import os

/// Phase of the Today tab lifecycle.
enum TodayPhase {
    case setup
    case generating
    case confirmation  // show generated workout before starting
    case active
    case postWorkout
}

/// Coordinates the Today tab's state: loading today's plan,
/// transitioning between setup/active/post states.
final class TodayViewModel: ObservableObject, WorkoutSessionServiceDelegate {

    private let logger = Logger(subsystem: "org.lightstack.app", category: "TodayViewModel")

    @Published var phase: TodayPhase = .setup
    @Published var exercises: [Exercise] = []
    @Published var exerciseListResetToken: Int = 0
    /// Bumped whenever a coach modification rewrites exercise targets, so the
    /// active workout screen can refresh inputs it has already filled in.
    @Published var targetsRevision: Int = 0
    @Published var loggedSets: [UUID: [WorkoutSet]] = [:]
    @Published var aiProgressionNote: String?
    @Published var streak: Int = 0
    @Published var errorMessage: String?
    @Published var isLoadingNote: Bool = false
    @Published var lastPR: PersonalRecord?
    /// Last session's sets per new exercise id (repeat sessions only).
    @Published var previousHints: [UUID: [PreviousSetHint]] = [:]
    /// Coach per-set targets (pyramids, ramps) by exercise id. Session-only.
    @Published var setTargets: [UUID: [SetTarget]] = [:]
    /// Unlogged set rows and clock state handed between the active-workout
    /// screen and session persistence (not published: no view renders them).
    var pendingSetsSnapshot: [UUID: [PendingSetInput]] = [:]
    var timerPaused = false

    let sessionService: WorkoutSessionService
    let workoutRepository: WorkoutRepository
    let prRepository: PRRepository
    let sessionPersistence: WorkoutSessionPersistence
    private(set) var userId: UUID?
    var activeWorkoutElapsed: Int = 0

    init(
        sessionService: WorkoutSessionService,
        workoutRepository: WorkoutRepository,
        prRepository: PRRepository,
        sessionPersistence: WorkoutSessionPersistence
    ) {
        self.sessionService = sessionService
        self.workoutRepository = workoutRepository
        self.prRepository = prRepository
        self.sessionPersistence = sessionPersistence
        sessionService.delegate = self
    }

    func setUserId(_ id: UUID) {
        self.userId = id
        self.streak = workoutRepository.fetchStreak(userId: id)

        // Check for saved workout session
        if let savedState = sessionPersistence.restoreSession() {
            restoreSessionState(savedState)
        }
    }

    /// Sets userId without restoring a saved session (for inline/embedded workout flows).
    func setUserIdSkipRestore(_ id: UUID) {
        self.userId = id
        self.streak = workoutRepository.fetchStreak(userId: id)
    }

    private func restoreSessionState(_ state: WorkoutSessionPersistence.SessionState) {
        // Restore all workout state
        exercises = state.exercises
        loggedSets = state.loggedSets
        previousHints = state.previousHints ?? [:]
        setTargets = state.setTargets ?? [:]
        pendingSetsSnapshot = state.pendingSets ?? [:]
        timerPaused = state.isPaused ?? false
        activeWorkoutElapsed = Self.restoredElapsed(
            saved: state.elapsedSeconds, savedAt: state.savedAt, paused: timerPaused
        )

        if state.phase == "active" {
            phase = .active
        } else if state.phase == "postWorkout" {
            phase = .postWorkout
        }

        // Restore workout in session service
        sessionService.startSession(workout: state.workout, exercises: state.exercises)

        logger.debug("Restored workout session: \(state.exercises.count) exercises, \(state.loggedSets.values.flatMap { $0 }.count) sets")
    }

    func saveSessionState() {
        guard phase == .active || phase == .postWorkout,
              let workout = sessionService.currentWorkout else {
            return
        }

        sessionPersistence.saveSession(
            workout: workout,
            exercises: exercises,
            loggedSets: loggedSets,
            phase: phase,
            userNote: nil,
            elapsedSeconds: activeWorkoutElapsed,
            previousHints: previousHints,
            setTargets: setTargets,
            pendingSets: pendingSetsSnapshot,
            isPaused: timerPaused
        )
    }

    /// Elapsed time to resume from: the saved value plus however long the app
    /// was closed, unless the clock was paused.
    static func restoredElapsed(saved: Int, savedAt: Date?, paused: Bool, now: Date = Date()) -> Int {
        guard !paused, let savedAt = savedAt else { return saved }
        return saved + max(0, Int(now.timeIntervalSince(savedAt)))
    }

    func generatePlan(workoutType: String, time: Int, energy: Int, notes: String?) {
        guard let userId = userId else {
            errorMessage = "Sign in required to generate a workout."
            return
        }
        phase = .generating
        errorMessage = nil
        sessionService.generatePlan(
            userId: userId,
            workoutType: workoutType,
            time: time,
            energy: energy,
            notes: notes
        )
    }

    func logSet(_ workoutSet: WorkoutSet, exerciseId: UUID) -> Bool {
        sessionService.logSet(workoutSet, exerciseId: exerciseId)
        var sets = loggedSets[exerciseId] ?? []
        var mutableSet = workoutSet

        // Check for PR
        guard let userId = userId,
              let exercise = exercises.first(where: { $0.id == exerciseId }) else {
            sets.append(mutableSet)
            loggedSets[exerciseId] = sets
            return false
        }

        // Skip PR check for zero-rep sets (nothing was actually lifted)
        if workoutSet.reps > 0, let pr = prRepository.checkAndRecordPR(
            userId: userId,
            exerciseName: exercise.name,
            weightLbs: workoutSet.weightLbs,
            reps: workoutSet.reps,
            workoutId: sessionService.currentWorkoutId
        ) {
            // Mark this set as a PR
            mutableSet.isPR = true
            lastPR = pr

            // Update in local storage
            workoutRepository.updateSet(mutableSet)

            // Auto-dismiss PR toast after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.lastPR = nil
            }

            sets.append(mutableSet)
            loggedSets[exerciseId] = sets
            return true
        }

        sets.append(mutableSet)
        loggedSets[exerciseId] = sets
        return false
    }

    func finishWorkout(userNote: String?) {
        guard let userId = userId else { return }
        isLoadingNote = true
        phase = .postWorkout
        sessionService.finishSession(
            userId: userId,
            userNote: userNote,
            exercises: exercises,
            allSets: loggedSets
        )
    }

    func saveWorkout(userNote: String?) {
        sessionService.saveCompletedWorkout(
            userNote: userNote,
            aiNote: aiProgressionNote,
            exercises: exercises,
            sets: loggedSets
        )
    }

    func loggedSetsForExercise(_ exerciseId: UUID) -> [WorkoutSet] {
        loggedSets[exerciseId] ?? []
    }

    var sessionDurationMinutes: Int? {
        guard let workout = sessionService.currentWorkoutCreatedAt else { return nil }
        let minutes = Int(Date().timeIntervalSince(workout) / 60)
        return minutes > 0 ? minutes : nil
    }

    func resetToSetup() {
        phase = .setup
        exercises = []
        loggedSets = [:]
        previousHints = [:]
        setTargets = [:]
        pendingSetsSnapshot = [:]
        timerPaused = false
        aiProgressionNote = nil
        errorMessage = nil
        isLoadingNote = false
        activeWorkoutElapsed = 0
        if let userId = userId {
            streak = workoutRepository.fetchStreak(userId: userId)
        }

        // Clear saved session when resetting to setup
        sessionPersistence.clearSession()
        sessionService.clearCurrentWorkout()
    }

    /// Cancel the in-progress workout: delete it and its logged sets from storage
    /// so it never appears in History, recompute any PRs it set, then reset.
    func discardWorkout() {
        if let workout = sessionService.currentWorkout {
            let exerciseNames = Set(exercises.map(\.name))
            workoutRepository.deleteWorkout(workout)
            if let userId = userId {
                for name in exerciseNames {
                    prRepository.recalculatePR(userId: userId, exerciseName: name)
                }
            }
        }
        resetToSetup()
    }

    // MARK: - WorkoutSessionServiceDelegate

    func sessionServiceDidGeneratePlan(_ service: WorkoutSessionService, exercises: [Exercise]) {
        guard !exercises.isEmpty else {
            self.errorMessage = "Couldn't build a workout. Please try again."
            self.phase = .setup
            return
        }
        self.exercises = exercises
        self.exerciseListResetToken += 1
        self.phase = .confirmation
    }

    func confirmAndStartWorkout() {
        activeWorkoutElapsed = 0
        phase = .active
    }

    /// Load a previous workout's exercises as a new workout plan, skipping AI generation.
    /// Creates a fresh workout record and jumps straight to the confirmation screen.
    func loadExistingWorkout(exercises: [Exercise], workoutType: String) {
        guard let userId = userId else { return }
        let newWorkout = Workout.create(userId: userId, workoutType: workoutType, energyLevel: nil, timeAvailableMinutes: nil)
        // Re-create exercises bound to the new workout id, preserving targets
        let newExercises = exercises.enumerated().map { index, ex in
            Exercise.create(
                workoutId: newWorkout.id,
                name: ex.name,
                muscleGroup: ex.muscleGroup,
                orderIndex: index,
                targetSets: ex.targetSets,
                targetReps: ex.targetReps,
                targetRir: ex.targetRir,
                restSeconds: ex.restSeconds,
                coachNote: ex.coachNote
            )
        }
        workoutRepository.createWorkout(newWorkout)
        sessionService.startSession(workout: newWorkout, exercises: newExercises)
        self.exercises = newExercises
        phase = .confirmation
    }

    /// Most recent past workout of this type that has at least one logged set.
    func lastSession(ofType type: String) -> Workout? {
        guard let userId = userId else { return nil }
        let wanted = type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return nil }
        let currentId = sessionService.currentWorkoutId
        let candidates = workoutRepository.fetchRecentWorkouts(userId: userId, limit: 60)
            .filter { $0.id != currentId }
            .filter { $0.workoutType.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(wanted) == .orderedSame }
            .sorted { $0.date > $1.date }
        return candidates.first { workout in
            workoutRepository.fetchExercises(workoutId: workout.id).contains { exercise in
                !workoutRepository.fetchSets(exerciseId: exercise.id).isEmpty
            }
        }
    }

    /// Start a new workout from the last session of this type, skipping AI.
    /// Last session's numbers become grey hints on the set rows.
    func repeatLastSession(ofType type: String) {
        guard let userId = userId, let source = lastSession(ofType: type) else { return }
        let newWorkout = Workout.create(userId: userId, workoutType: source.workoutType, energyLevel: nil, timeAvailableMinutes: nil)
        let sourceExercises = workoutRepository.fetchExercises(workoutId: source.id)
            .sorted { $0.orderIndex < $1.orderIndex }

        var hints: [UUID: [PreviousSetHint]] = [:]
        var newExercises: [Exercise] = []
        for (index, ex) in sourceExercises.enumerated() {
            let sets = workoutRepository.fetchSets(exerciseId: ex.id)
                .sorted { $0.setNumber < $1.setNumber }
            let first = sets.first
            let coachNote: String? = first.map { set in
                set.weightLbs == 0 ? "Target: BW" : "Target: \(String(format: "%g", set.weightLbs)) lbs"
            }
            let newExercise = Exercise.create(
                workoutId: newWorkout.id,
                name: ex.name,
                muscleGroup: ex.muscleGroup,
                orderIndex: index,
                targetSets: sets.isEmpty ? ex.targetSets : sets.count,
                targetReps: first.map { String($0.reps) } ?? ex.targetReps,
                targetRir: ex.targetRir,
                restSeconds: ex.restSeconds,
                coachNote: coachNote
            )
            if newExercise.trackingType == .strength, !sets.isEmpty {
                hints[newExercise.id] = sets.map {
                    PreviousSetHint(weightLbs: $0.weightLbs, reps: $0.reps, rir: $0.rir)
                }
            }
            newExercises.append(newExercise)
        }

        workoutRepository.createWorkout(newWorkout)
        sessionService.startSession(workout: newWorkout, exercises: newExercises)
        self.exercises = newExercises
        self.previousHints = hints
        phase = .confirmation
    }

    func sessionServiceDidReceiveProgressionNote(_ service: WorkoutSessionService, note: String) {
        self.aiProgressionNote = note.isEmpty ? nil : note
        self.isLoadingNote = false
    }

    func sessionServiceDidSaveWorkout(_ service: WorkoutSessionService) {
        resetToSetup()
    }

    func sessionServiceDidFail(_ service: WorkoutSessionService, error: Error) {
        self.errorMessage = error.localizedDescription
        self.isLoadingNote = false
        if phase == .generating {
            phase = .setup
        }
    }

    // MARK: - Workout Modifications

    /// Apply a workout modification while preserving already-logged sets.
    func applyModification(_ modification: WorkoutModification, preserveLoggedSets: Bool) {
        guard let workoutId = sessionService.currentWorkoutId else { return }

        switch modification {
        case .addExercise(let name, let muscleGroup, let targetSets, let targetReps, let targetRir, let restSeconds, let targetWeight, let note, let perSet):
            let newExercise = Exercise.create(
                workoutId: workoutId,
                name: name,
                muscleGroup: muscleGroup,
                orderIndex: exercises.count,
                targetSets: targetSets,
                targetReps: targetReps,
                targetRir: targetRir,
                restSeconds: restSeconds,
                coachNote: Self.coachNote(nil, weight: targetWeight, note: note)
            )
            exercises.append(newExercise)
            storeSetTargets(perSet, for: newExercise.id)
            // Save the new exercise to the repository
            workoutRepository.saveExercises([newExercise], workoutId: workoutId)

        case .removeExercise(let name):
            if let index = exercises.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
                let exerciseId = exercises[index].id
                let removedName = exercises[index].name
                exercises.remove(at: index)
                if !preserveLoggedSets || loggedSets[exerciseId]?.isEmpty ?? true {
                    purgeExercise(id: exerciseId, name: removedName)
                }
                setTargets[exerciseId] = nil
                // Note: Already-logged sets are preserved (in memory and storage) if preserveLoggedSets is true
            }

        case .modifyExercise(let name, let newTargetSets, let newTargetReps, let newTargetRir, let newRest, let newTargetWeight, let note, let perSet):
            if let index = exercises.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
                var exercise = exercises[index]
                if let sets = newTargetSets ?? (perSet.isEmpty ? nil : perSet.count) {
                    exercise.targetSets = sets
                }
                if !perSet.isEmpty {
                    storeSetTargets(perSet, for: exercise.id)
                } else if newTargetReps != nil || newTargetRir != nil || newTargetWeight != nil {
                    // A new single target supersedes any earlier per-set plan.
                    setTargets[exercise.id] = nil
                }
                if let reps = newTargetReps {
                    exercise.targetReps = reps
                }
                if let rir = newTargetRir {
                    exercise.targetRir = rir
                }
                if let rest = newRest {
                    exercise.restSeconds = rest
                }
                if newTargetWeight != nil || note != nil {
                    exercise.coachNote = Self.coachNote(exercise.coachNote, weight: newTargetWeight, note: note)
                }
                exercises[index] = exercise
            }

        case .replaceExercise(let oldName, let newName, let muscleGroup, let targetSets, let targetReps, let targetRir, let restSeconds, let targetWeight, let note, let perSet):
            if let index = exercises.firstIndex(where: { $0.name.lowercased() == oldName.lowercased() }) {
                let oldExerciseId = exercises[index].id
                let oldName = exercises[index].name
                let orderIndex = exercises[index].orderIndex

                // Create new exercise
                let newExercise = Exercise.create(
                    workoutId: workoutId,
                    name: newName,
                    muscleGroup: muscleGroup,
                    orderIndex: orderIndex,
                    targetSets: targetSets,
                    targetReps: targetReps,
                    targetRir: targetRir,
                    restSeconds: restSeconds,
                    coachNote: Self.coachNote(nil, weight: targetWeight, note: note)
                )

                exercises[index] = newExercise
                setTargets[oldExerciseId] = nil
                storeSetTargets(perSet, for: newExercise.id)

                // Remove logged sets for old exercise unless preserving
                if !preserveLoggedSets || loggedSets[oldExerciseId]?.isEmpty ?? true {
                    purgeExercise(id: oldExerciseId, name: oldName)
                }
            }
        }

        // Save state after modification
        saveSessionState()
        // Tell the active workout screen its already-filled inputs are stale.
        targetsRevision += 1
    }

    /// Stores per-set targets for an exercise, replacing any earlier ones. Empty clears.
    private func storeSetTargets(_ targets: [SetTarget], for exerciseId: UUID) {
        setTargets[exerciseId] = targets.isEmpty ? nil : targets
    }

    /// `coachNote` doubles as the target-weight carrier — generation writes
    /// "Target: 135 lbs" into it, since `Exercise` has no weight column. Rebuild
    /// the note so a new weight replaces the old `Target:` segment instead of
    /// being appended after it, which left two contradictory targets on screen.
    static func coachNote(_ existing: String?, weight: String?, note: String?) -> String? {
        var segments = (existing ?? "")
            .components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if let weight = weight, !weight.isEmpty {
            segments.removeAll { $0.lowercased().hasPrefix("target:") }
            segments.insert("Target: \(weight)", at: 0)
        }
        if let note = note, !note.isEmpty, !segments.contains(note) {
            segments.append(note)
        }

        let joined = segments.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }

    // MARK: - Manual Exercise Management

    func addExerciseManually(name: String, muscleGroup: String) {
        guard let workoutId = sessionService.currentWorkoutId else { return }
        let newExercise = Exercise.create(
            workoutId: workoutId,
            name: name,
            muscleGroup: muscleGroup,
            orderIndex: exercises.count,
            targetSets: 3,
            targetReps: "8-12",
            targetRir: "2",
            restSeconds: 90,
            coachNote: nil
        )
        exercises.append(newExercise)
        workoutRepository.saveExercises([newExercise], workoutId: workoutId)
        saveSessionState()
    }

    func removeExercise(at id: UUID) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        let name = exercises[index].name
        exercises.remove(at: index)
        purgeExercise(id: id, name: name)
        saveSessionState()
    }

    /// Forgets an exercise: drops its logged sets, deletes it (and its sets, via
    /// cascade) from storage, and rebuilds its PR if any sets were lost.
    private func purgeExercise(id: UUID, name: String) {
        let hadSets = !(loggedSets[id]?.isEmpty ?? true)
        loggedSets.removeValue(forKey: id)
        workoutRepository.deleteExercise(id)
        if hadSets, let userId = userId {
            prRepository.recalculatePR(userId: userId, exerciseName: name)
            if lastPR?.exerciseName == name { lastPR = nil }
        }
    }

    /// Deletes a single logged set everywhere (memory, storage, Supabase) and
    /// rebuilds the exercise's PR so a PR earned by this set doesn't linger.
    func deleteLoggedSet(_ workoutSet: WorkoutSet, exerciseId: UUID) {
        loggedSets[exerciseId]?.removeAll { $0.id == workoutSet.id }
        workoutRepository.deleteSet(workoutSet)
        if let userId = userId,
           let exercise = exercises.first(where: { $0.id == exerciseId }) {
            prRepository.recalculatePR(userId: userId, exerciseName: exercise.name)
            if lastPR?.exerciseName == exercise.name { lastPR = nil }
        }
        saveSessionState()
    }
}
