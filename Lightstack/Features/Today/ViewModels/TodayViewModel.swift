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
    private(set) var userId: UUID?

    init(
        sessionService: WorkoutSessionService,
        workoutRepository: WorkoutRepository,
        prRepository: PRRepository
    ) {
        self.sessionService = sessionService
        self.workoutRepository = workoutRepository
        self.prRepository = prRepository
        sessionService.delegate = self
    }

    func setUserId(_ id: UUID) {
        self.userId = id
        self.streak = workoutRepository.fetchStreak(userId: id)
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
}
