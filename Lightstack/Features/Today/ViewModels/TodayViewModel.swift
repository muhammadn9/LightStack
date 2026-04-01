import Foundation

/// Phase of the Today tab lifecycle.
enum TodayPhase {
    case setup
    case generating
    case active
    case postWorkout
}

/// Coordinates the Today tab's state: loading today's plan,
/// transitioning between setup/active/post states.
final class TodayViewModel: ObservableObject, WorkoutSessionServiceDelegate {

    @Published var phase: TodayPhase = .setup
    @Published var exercises: [Exercise] = []
    @Published var loggedSets: [UUID: [WorkoutSet]] = [:]
    @Published var aiProgressionNote: String?
    @Published var streak: Int = 0
    @Published var errorMessage: String?
    @Published var isLoadingNote: Bool = false
    @Published var lastPR: PersonalRecord?

    let sessionService: WorkoutSessionService
    let workoutRepository: WorkoutRepository
    let prRepository: PRRepository
    let sessionPersistence: WorkoutSessionPersistence
    private(set) var userId: UUID?

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

    private func restoreSessionState(_ state: WorkoutSessionPersistence.SessionState) {
        // Restore all workout state
        exercises = state.exercises
        loggedSets = state.loggedSets

        if state.phase == "active" {
            phase = .active
        } else if state.phase == "postWorkout" {
            phase = .postWorkout
        }

        // Restore workout in session service
        sessionService.startSession(workout: state.workout, exercises: state.exercises)

        print("[TodayViewModel] Restored workout session: \(state.exercises.count) exercises, \(loggedSets.values.flatMap { $0 }.count) sets")
    }

    func saveSessionState() {
        guard phase == .active || phase == .postWorkout,
              let workout = sessionService.currentWorkoutCreatedAt.map({ _ in
                  // Build workout from current state
                  Workout.create(
                      userId: userId ?? UUID(),
                      workoutType: sessionService.currentWorkoutType ?? "Unknown",
                      energyLevel: 5,
                      timeAvailableMinutes: 60
                  )
              }) else {
            return
        }

        sessionPersistence.saveSession(
            workout: workout,
            exercises: exercises,
            loggedSets: loggedSets,
            phase: phase,
            userNote: nil
        )
    }

    func generatePlan(workoutType: String, time: Int, energy: Int, notes: String?) {
        guard let userId = userId else { return }
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

        if let pr = prRepository.checkAndRecordPR(
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
        aiProgressionNote = nil
        errorMessage = nil
        isLoadingNote = false
        if let userId = userId {
            streak = workoutRepository.fetchStreak(userId: userId)
        }

        // Clear saved session when resetting to setup
        sessionPersistence.clearSession()
    }

    // MARK: - WorkoutSessionServiceDelegate

    func sessionServiceDidGeneratePlan(_ service: WorkoutSessionService, exercises: [Exercise]) {
        self.exercises = exercises
        self.phase = .active
    }

    func sessionServiceDidReceiveProgressionNote(_ service: WorkoutSessionService, note: String) {
        self.aiProgressionNote = note
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
        case .addExercise(let name, let muscleGroup, let targetSets, let targetReps, let targetRir, let restSeconds, let note):
            let newExercise = Exercise.create(
                workoutId: workoutId,
                name: name,
                muscleGroup: muscleGroup,
                orderIndex: exercises.count,
                targetSets: targetSets,
                targetReps: targetReps,
                targetRir: targetRir,
                restSeconds: restSeconds,
                coachNote: note
            )
            exercises.append(newExercise)
            sessionService.startSession(workout: sessionService.currentWorkoutCreatedAt.map {
                Workout.create(userId: userId ?? UUID(), workoutType: sessionService.currentWorkoutType ?? "", energyLevel: 5, timeAvailableMinutes: 60)
            }!, exercises: exercises)

        case .removeExercise(let name):
            if let index = exercises.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
                let exerciseId = exercises[index].id
                exercises.remove(at: index)
                if !preserveLoggedSets || loggedSets[exerciseId]?.isEmpty ?? true {
                    loggedSets.removeValue(forKey: exerciseId)
                }
                // Note: Already-logged sets are preserved in the dictionary if preserveLoggedSets is true
            }

        case .modifyExercise(let name, let newTargetSets, let newTargetReps, let newTargetRir, let newRest, let note):
            if let index = exercises.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
                var exercise = exercises[index]
                if let sets = newTargetSets {
                    exercise.targetSets = sets
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
                if let note = note {
                    exercise.coachNote = (exercise.coachNote ?? "") + " " + note
                }
                exercises[index] = exercise
            }

        case .replaceExercise(let oldName, let newName, let muscleGroup, let targetSets, let targetReps, let targetRir, let restSeconds, let note):
            if let index = exercises.firstIndex(where: { $0.name.lowercased() == oldName.lowercased() }) {
                let oldExerciseId = exercises[index].id
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
                    coachNote: note
                )

                exercises[index] = newExercise

                // Remove logged sets for old exercise unless preserving
                if !preserveLoggedSets || loggedSets[oldExerciseId]?.isEmpty ?? true {
                    loggedSets.removeValue(forKey: oldExerciseId)
                }
            }
        }

        // Save state after modification
        saveSessionState()
    }
}
