import XCTest
@testable import Lightstack

/// Replies with a fixed result to every AI request.
private final class FixedProvider: AIProvider {
    let name = "Fixed"
    let rateLimitKey = "fixed_rate_limit_\(UUID().uuidString)"
    var isAvailable: Bool { true }
    var nextAvailableTime: Date? { nil }
    let result: Result<String, Error>
    init(_ result: Result<String, Error>) { self.result = result }
    func markRateLimited(until: Date) {}
    func clearRateLimit() {}
    func generateChat(systemPrompt: String, messages: [ChatMessage], expectsJSON: Bool,
                      completion: @escaping (Result<String, Error>) -> Void) {
        let r = result
        DispatchQueue.main.async { completion(r) }
    }
}

private struct Unreachable: Error {}

/// A history-only split name goes through the coach plan path; Freestyle starts empty and finishes with a review.
@MainActor
final class GymTodayFlowTests: XCTestCase {

    private var stack: OutboxTestStack!

    override func setUp() {
        super.setUp()
        stack = OutboxTestStack()
    }

    private func makeViewModel(reply: Result<String, Error>) -> TodayViewModel {
        let validation = ValidationService()
        let workouts = WorkoutRepository(localStorage: stack.storage, offlineQueueManager: stack.queue)
        let profiles = ProfileRepository(localStorage: stack.storage, supabaseService: SupabaseServiceFactory.unreachable(),
                                         offlineQueueManager: stack.queue)
        let months = MonthPlanRepository(localStorage: stack.storage, supabaseService: SupabaseServiceFactory.unreachable(),
                                         offlineQueueManager: stack.queue)
        let service = WorkoutSessionService(
            aiServiceManager: AIServiceManager(providers: [FixedProvider(reply)]),
            coachPromptService: CoachPromptService(validationService: validation),
            coachContextBuilder: CoachContextBuilder(profileRepository: profiles, workoutRepository: workouts,
                                                     localStorage: stack.storage, validationService: validation),
            workoutRepository: workouts, monthPlanRepository: months, localStorage: stack.storage,
            validationService: validation, offlineQueueManager: stack.queue)
        let vm = TodayViewModel(sessionService: service, workoutRepository: workouts,
                                prRepository: PRRepository(localStorage: stack.storage, offlineQueueManager: stack.queue),
                                sessionPersistence: WorkoutSessionPersistence())
        vm.setUserIdSkipRestore(stack.userId)
        return vm
    }

    /// A finished past session of `type` with the given lifts, `daysAgo` days back.
    private func seedSession(_ type: String, daysAgo: Int, lifts: [(String, String, Double, Int)]) {
        var w = Workout.create(userId: stack.userId, workoutType: type, energyLevel: 7, timeAvailableMinutes: 45)
        w.date = Date().addingTimeInterval(-86_400 * Double(daysAgo))
        stack.storage.saveWorkout(w)
        var exercises: [Exercise] = []
        for (index, lift) in lifts.enumerated() {
            exercises.append(Exercise.create(workoutId: w.id, name: lift.0, muscleGroup: lift.1, orderIndex: index,
                                             targetSets: 2, targetReps: "\(lift.3)", targetRir: "2", restSeconds: 60, coachNote: nil))
        }
        stack.storage.saveExercises(exercises, workoutId: w.id)
        for (index, exercise) in exercises.enumerated() {
            for n in 1...2 {
                stack.storage.saveSet(WorkoutSet.create(exerciseId: exercise.id, setNumber: n, weightLbs: lifts[index].2,
                                                        reps: lifts[index].3, rir: 2), exerciseId: exercise.id)
            }
        }
    }

    private func waitForPhase(_ vm: TodayViewModel, _ phase: TodayPhase) async {
        for _ in 0..<120 where vm.phase != phase { try? await Task.sleep(nanoseconds: 50_000_000) }
    }

    func testHistoryOnlyNameBuildsAPlanFromItsLastSession() async {
        seedSession("Arm Day", daysAgo: 3, lifts: [("Barbell Curl", "Arms", 65, 10), ("Skull Crusher", "Arms", 55, 10)])
        seedSession("Push", daysAgo: 1, lifts: [("Bench Press", "Chest", 135, 8)])
        let vm = makeViewModel(reply: .failure(Unreachable()))
        XCTAssertEqual(vm.historyWorkoutNames(excluding: ["Push", "Pull", "Legs"]), ["Arm Day"])

        // The coach cannot be reached: the app's own plan from the log still comes back.
        vm.generatePlan(workoutType: "Arm Day", time: 45, energy: 3, notes: nil)
        await waitForPhase(vm, .confirmation)

        XCTAssertEqual(vm.phase, .confirmation)
        XCTAssertEqual(vm.sessionService.currentWorkoutType, "Arm Day")
        let names = vm.exercises.map(\.name)
        XCTAssertTrue(names.contains("Barbell Curl"), "Plan should build on the last Arm Day: \(names)")
        XCTAssertTrue(names.contains("Skull Crusher"), "Plan should build on the last Arm Day: \(names)")
        XCTAssertFalse(names.contains("Bench Press"), "Another type's session must not leak in")
    }

    func testHistoryNameLookupIsCaseInsensitiveAndNeverOffersFreestyle() async {
        seedSession("arm day", daysAgo: 2, lifts: [("Barbell Curl", "Arms", 65, 10)])
        seedSession("Freestyle", daysAgo: 1, lifts: [("Bench Press", "Chest", 135, 8)])
        let vm = makeViewModel(reply: .failure(Unreachable()))
        XCTAssertEqual(vm.historyWorkoutNames(excluding: ["Push"]), ["arm day"])
        XCTAssertNotNil(vm.lastSessionInfo(ofType: "Arm Day"))
        XCTAssertEqual(vm.lastSessionInfo(ofType: "Arm Day")?.exerciseCount, 1)
        XCTAssertNil(vm.lastSessionInfo(ofType: "Core Day"))
    }

    func testFreestyleStartsEmptyAndLive() {
        let vm = makeViewModel(reply: .failure(Unreachable()))
        vm.startFreestyle()
        XCTAssertEqual(vm.phase, .active)
        XCTAssertTrue(vm.exercises.isEmpty)
        XCTAssertEqual(vm.sessionService.currentWorkoutType, "Freestyle")
        XCTAssertTrue(vm.opensExercisePickerOnStart)
        XCTAssertEqual(stack.storage.fetchRecentWorkouts(userId: stack.userId, limit: 10).count, 1)
        XCTAssertNotNil(WorkoutSessionPersistence().restoreSession(), "A relaunch must find the Freestyle session")
        vm.discardWorkout()
        XCTAssertEqual(vm.phase, .setup)
        XCTAssertEqual(stack.storage.fetchRecentWorkouts(userId: stack.userId, limit: 10).count, 0)
    }

    func testFreestyleAddsExercisesInOrderPrefilledFromLastSession() {
        seedSession("Push", daysAgo: 2, lifts: [("Bench Press", "Chest", 135, 8), ("Lat Pulldown", "Back", 120, 10)])
        let vm = makeViewModel(reply: .failure(Unreachable()))
        vm.startFreestyle()
        let first = vm.addExerciseManually(name: "Lat Pulldown", muscleGroup: "Back")
        let second = vm.addExerciseManually(name: "Bench Press", muscleGroup: "Chest", afterPageIndex: 0)
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(vm.exercises.map(\.name), ["Lat Pulldown", "Bench Press"])
        XCTAssertEqual(vm.previousHints[vm.exercises[1].id]?.first?.weightLbs, 135)
        XCTAssertEqual(vm.exercises[0].targetReps, "10")
        vm.discardWorkout()
    }

    func testFreestyleFinishesWithAReviewAndNoPlan() async {
        let reply = #"{"note": "Good session.", "summary": "Freestyle chest day."}"#
        let vm = makeViewModel(reply: .success(reply))
        vm.startFreestyle()
        guard let id = vm.addExerciseManually(name: "Bench Press", muscleGroup: "Chest") else {
            return XCTFail("Exercise was not added")
        }
        let set = WorkoutSet.create(exerciseId: id, setNumber: 1, weightLbs: 135, reps: 8, rir: 2)
        XCTAssertNotNil(vm.sessionService.currentWorkoutId)
        _ = vm.logSet(set, exerciseId: id)
        vm.finishWorkout(userNote: nil)
        for _ in 0..<120 where vm.isLoadingNote { try? await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(vm.phase, .postWorkout)
        XCTAssertFalse(vm.isLoadingNote)
        let review = vm.currentCoachReviewDocument()?.review
        XCTAssertNotNil(review, "A Freestyle workout gets the same coach review")
        XCTAssertEqual(review?.exercises.map(\.name), ["Bench Press"])
        XCTAssertFalse((review?.overallRead ?? "").isEmpty)
    }
}
