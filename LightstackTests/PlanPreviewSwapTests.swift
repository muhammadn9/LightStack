import XCTest
@testable import Lightstack

private final class PlanStubProvider: AIProvider {
    let name = "Stub"
    let rateLimitKey = "stub_rate_limit_\(UUID().uuidString)"
    var isAvailable: Bool { true }
    var nextAvailableTime: Date? { nil }
    let text: String
    init(_ text: String) { self.text = text }
    func markRateLimited(until: Date) {}
    func clearRateLimit() {}
    func generateChat(systemPrompt: String, messages: [ChatMessage], expectsJSON: Bool,
                      completion: @escaping (Result<String, Error>) -> Void) {
        let t = text
        DispatchQueue.main.async { completion(.success(t)) }
    }
}

/// Ranking, swap and discard on the generated-plan preview.
@MainActor
final class PlanPreviewSwapTests: XCTestCase {

    private var stack: OutboxTestStack!

    override func setUp() {
        super.setUp()
        stack = OutboxTestStack()
    }

    // MARK: - Ranking (pure)

    private func hist(_ rows: [(String, String)]) -> [HistoryExercise] {
        HistoryExercise.distinct(rows.map { (name: $0.0, muscleGroup: $0.1) })
    }

    func testHistoryComesFirstThenCatalogSameMuscleExcludingPlan() {
        let result = ExerciseSwapSuggestions.rank(
            replacing: ("Barbell Bench Press", "Chest"),
            planNames: ["Barbell Bench Press", "Incline Dumbbell Press"],
            history: hist([("Squat", "Legs"), ("Cable Flye", "Chest"), ("Incline Dumbbell Press", "Chest"),
                           ("Push-Up", "Chest")])
        )
        let names = result.map(\.name)
        XCTAssertEqual(Array(names.prefix(2)), ["Cable Flye", "Push-Up"], "history first, most recent first")
        XCTAssertTrue(result.prefix(2).allSatisfy(\.isFromHistory))
        XCTAssertFalse(names.contains("Squat"), "other muscle excluded")
        XCTAssertFalse(names.contains("Incline Dumbbell Press"), "plan exercise excluded")
        XCTAssertFalse(names.contains("Barbell Bench Press"), "replaced exercise excluded")
        XCTAssertTrue(result.dropFirst(2).allSatisfy { !$0.isFromHistory })
        XCTAssertEqual(names.filter { $0 == "Cable Flye" }.count, 1, "no duplicates between history and catalog")
        XCTAssertTrue(result.allSatisfy { $0.muscleGroup == "Chest" })
    }

    func testTricepsPlanDoesNotSuggestBiceps() {
        let result = ExerciseSwapSuggestions.rank(
            replacing: ("Cable Triceps Pushdown", "Triceps"), planNames: [], history: hist([("Barbell Curl", "Arms")])
        )
        XCTAssertFalse(result.contains { $0.name == "Barbell Curl" })
        XCTAssertFalse(result.isEmpty)
    }

    func testPrefillWithHistoryUsesLastSessionAndWithoutKeepsOldTargets() {
        let old = Exercise.create(workoutId: UUID(), name: "X", muscleGroup: "Chest", orderIndex: 0,
                                  targetSets: 4, targetReps: "10", targetRir: "2", restSeconds: 90, coachNote: "Target: 135 lbs")
        let with = SwapPrefill.make(previous: [PreviousSetHint(weightLbs: 55, reps: 15, rir: 3),
                                               PreviousSetHint(weightLbs: 60, reps: 12, rir: 2)], replacing: old)
        XCTAssertEqual(with.targetSets, 2)
        XCTAssertEqual(with.targetReps, "15")
        XCTAssertEqual(with.setTargets.map(\.prefillWeight), ["55", "60"])
        XCTAssertEqual(with.coachNote, "Target: 55 lbs")
        let without = SwapPrefill.make(previous: [], replacing: old)
        XCTAssertEqual(without.targetSets, 4)
        XCTAssertEqual(without.targetReps, "10")
        XCTAssertNil(without.coachNote)
        XCTAssertTrue(without.setTargets.isEmpty)
    }

    // MARK: - View model

    private func makeViewModel(plan: String) async -> TodayViewModel {
        let validation = ValidationService()
        let workouts = WorkoutRepository(localStorage: stack.storage, offlineQueueManager: stack.queue)
        let profiles = ProfileRepository(localStorage: stack.storage,
                                         supabaseService: SupabaseServiceFactory.unreachable(),
                                         offlineQueueManager: stack.queue)
        let months = MonthPlanRepository(localStorage: stack.storage,
                                         supabaseService: SupabaseServiceFactory.unreachable(),
                                         offlineQueueManager: stack.queue)
        let service = WorkoutSessionService(
            aiServiceManager: AIServiceManager(providers: [PlanStubProvider(plan)]),
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

    private func seedPastLift(_ name: String, group: String, sets: [(Double, Int)]) {
        var w = Workout.create(userId: stack.userId, workoutType: "Old", energyLevel: nil, timeAvailableMinutes: nil)
        w.date = Date().addingTimeInterval(-86_400 * 3)
        stack.storage.saveWorkout(w)
        let e = Exercise.create(workoutId: w.id, name: name, muscleGroup: group, orderIndex: 0,
                                targetSets: sets.count, targetReps: "8", targetRir: nil, restSeconds: 60, coachNote: nil)
        stack.storage.saveExercises([e], workoutId: w.id)
        for (i, s) in sets.enumerated() {
            stack.storage.saveSet(WorkoutSet.create(exerciseId: e.id, setNumber: i + 1, weightLbs: s.0, reps: s.1, rir: 2),
                                  exerciseId: e.id)
        }
    }

    private let plan = """
    {"exercises": [
     {"name": "Barbell Bench Press", "muscle_group": "Chest", "sets": 3, "reps": "8", "target_weight": "135 lbs", "superset": "A"},
     {"name": "Incline Dumbbell Press", "muscle_group": "Chest", "sets": 3, "reps": "10", "superset": "A"},
     {"name": "Overhead Press", "muscle_group": "Shoulders", "sets": 3, "reps": "8"}]}
    """

    private func generate(_ vm: TodayViewModel) async {
        vm.generatePlan(workoutType: "Push", time: 45, energy: 3, notes: nil)
        for _ in 0..<100 where vm.phase != .confirmation { try? await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(vm.phase, .confirmation)
    }

    func testSwapKeepsPositionSupersetAndPrefillsFromHistory() async {
        seedPastLift("Cable Flye", group: "Chest", sets: [(30, 12), (35, 10)])
        let vm = await makeViewModel(plan: plan)
        await generate(vm)
        let old = vm.exercises[1]
        let group = old.supersetGroupId
        let candidates = vm.swapCandidates(forExerciseId: old.id)
        XCTAssertEqual(candidates.first?.name, "Cable Flye")
        XCTAssertEqual(candidates.first?.previous.count, 2)

        let newId = vm.swapExercise(id: old.id, toName: "Cable Flye", muscleGroup: "Chest")
        XCTAssertNotNil(newId)
        XCTAssertEqual(vm.exercises.map(\.name), ["Barbell Bench Press", "Cable Flye", "Overhead Press"])
        XCTAssertEqual(vm.exercises[1].supersetGroupId, group)
        XCTAssertEqual(vm.exercises[1].orderIndex, old.orderIndex)
        XCTAssertEqual(vm.exercises[1].targetSets, 2)
        XCTAssertEqual(vm.previousHints[vm.exercises[1].id]?.count, 2)
        XCTAssertEqual(vm.setTargets[vm.exercises[1].id]?.map(\.prefillWeight), ["30", "35"])
        let stored = stack.storage.fetchExercises(workoutId: old.workoutId).compactMap(\.name)
        XCTAssertTrue(stored.contains("Cable Flye"))
        XCTAssertFalse(stored.contains("Incline Dumbbell Press"))
    }

    func testSwapToNeverLoggedLiftKeepsOldTargetsWithoutWeight() async {
        let vm = await makeViewModel(plan: plan)
        await generate(vm)
        let old = vm.exercises[2]
        vm.swapExercise(id: old.id, toName: "Arnold Press", muscleGroup: "Shoulders")
        XCTAssertEqual(vm.exercises[2].name, "Arnold Press")
        XCTAssertEqual(vm.exercises[2].targetSets, 3)
        XCTAssertEqual(vm.exercises[2].targetReps, "8")
        XCTAssertNil(vm.exercises[2].coachNote)
        XCTAssertNil(vm.previousHints[vm.exercises[2].id])
    }

    func testDiscardLeavesNoWorkoutAndNothingRemote() async {
        let vm = await makeViewModel(plan: plan)
        await generate(vm)
        let workoutId = vm.sessionService.currentWorkoutId
        XCTAssertNotNil(workoutId)
        XCTAssertEqual(stack.storage.fetchRecentWorkouts(userId: stack.userId, limit: 50).count, 1)

        vm.discardPlanPreview()

        XCTAssertEqual(vm.phase, .setup)
        XCTAssertTrue(vm.exercises.isEmpty)
        XCTAssertNil(vm.sessionService.currentWorkoutId)
        XCTAssertEqual(stack.storage.fetchRecentWorkouts(userId: stack.userId, limit: 50).count, 0)
        XCTAssertNil(WorkoutSessionPersistence().restoreSession(), "relaunch must not resurrect the plan")
        await stack.queue.waitForSubmissions()
        await stack.flushAll()
        XCTAssertTrue(stack.remote.workouts.isEmpty, "no workout may remain remotely")
        XCTAssertTrue(stack.remote.exercises.isEmpty)
    }
}
