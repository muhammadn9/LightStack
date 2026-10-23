import XCTest
@testable import Lightstack

private final class LAStubProvider: AIProvider {
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

/// Live Activity: session -> content mapping, -/+ steps, and the button actions on a real session.
@MainActor
final class LiveActivityTests: XCTestCase {

    private var stack: OutboxTestStack!

    override func setUp() {
        super.setUp()
        stack = OutboxTestStack()
    }

    private func exercise(_ name: String, sets: Int, order: Int = 0, rest: Int? = 90) -> Exercise {
        Exercise.create(workoutId: UUID(), name: name, muscleGroup: "Chest", orderIndex: order,
                        targetSets: sets, targetReps: "8", targetRir: "2", restSeconds: rest, coachNote: nil)
    }

    private func pending(_ w: String, _ r: String, _ rir: String = "2") -> PendingSetInput {
        PendingSetInput(weight: w, reps: r, rir: rir)
    }

    private func state(_ exercises: [Exercise], logged: [UUID: [WorkoutSet]] = [:],
                       pending: [UUID: [PendingSetInput]], targets: [UUID: [SetTarget]] = [:],
                       restId: UUID? = nil, restDates: [UUID: Date] = [:], now: Date = Date()) -> LightstackWorkoutAttributes.ContentState {
        LiveActivityMapper.contentState(
            exercises: exercises, loggedSets: logged, pendingSets: pending, setTargets: targets,
            activeRestExerciseId: restId, restTargetDates: restDates, elapsedSeconds: 125,
            isPaused: false, unit: "lb", now: now)
    }

    // MARK: - State mapping

    func testMapsCurrentSetAndNextExercise() {
        let bench = exercise("Barbell Bench Press", sets: 3)
        let fly = exercise("Cable Fly", sets: 3, order: 1)
        let logged = [bench.id: [WorkoutSet.create(exerciseId: bench.id, setNumber: 1, weightLbs: 135, reps: 8, rir: 2)]]
        let pend = [bench.id: [pending("140", "8"), pending("140", "8")], fly.id: [pending("30", "12")]]
        let targets = [bench.id: [SetTarget(), SetTarget(weight: "140", reps: "8", rir: "2", role: .top)]]

        let s = state([bench, fly], logged: logged, pending: pend, targets: targets)

        XCTAssertEqual(s.exerciseName, "Barbell Bench Press")
        XCTAssertEqual(s.setNumber, 2)
        XCTAssertEqual(s.totalSets, 3)
        XCTAssertEqual(s.setLabel, "Top set")
        XCTAssertEqual(s.weightText, "140")
        XCTAssertEqual(s.reps, 8)
        XCTAssertEqual(s.rir, 2)
        XCTAssertEqual(s.nextExercise, "Cable Fly")
        XCTAssertTrue(s.canLog)
        XCTAssertNil(s.restEndDate)
        XCTAssertFalse(s.allDone)
        XCTAssertEqual(s.setKey, "\(bench.id.uuidString):1")
        XCTAssertEqual(Int(Date().timeIntervalSince(s.elapsedAnchor).rounded()), 125)
    }

    func testRestEndOnlyWhileInFuture() {
        let bench = exercise("Barbell Bench Press", sets: 2)
        let now = Date()
        let running = state([bench], pending: [bench.id: [pending("135", "8")]],
                            restId: bench.id, restDates: [bench.id: now.addingTimeInterval(60)], now: now)
        XCTAssertEqual(running.restEndDate, now.addingTimeInterval(60))
        let expired = state([bench], pending: [bench.id: [pending("135", "8")]],
                            restId: bench.id, restDates: [bench.id: now.addingTimeInterval(-1)], now: now)
        XCTAssertNil(expired.restEndDate)
    }

    func testAllDoneWhenNothingPending() {
        let bench = exercise("Barbell Bench Press", sets: 1)
        let s = state([bench], pending: [bench.id: []])
        XCTAssertTrue(s.allDone)
        XCTAssertFalse(s.canLog)
    }

    func testBlankRowFallsBackToPreviousHint() {
        let bench = exercise("Barbell Bench Press", sets: 1)
        var row = pending("", "", "")
        row.previous = PreviousSetHint(weightLbs: 125, reps: 10, rir: 1)
        let s = state([bench], pending: [bench.id: [row]])
        XCTAssertEqual(s.weightText, "125")
        XCTAssertEqual(s.reps, 10)
        XCTAssertEqual(s.rir, 1)
    }

    // MARK: - Steps

    func testPlateStepFollowsEquipment() {
        XCTAssertEqual(LiveActivityMapper.steppedWeight(135, exerciseName: "Barbell Bench Press", direction: 1), 140)
        XCTAssertEqual(LiveActivityMapper.steppedWeight(135, exerciseName: "Leg Press Machine", direction: -1), 130)
        XCTAssertEqual(LiveActivityMapper.steppedWeight(50, exerciseName: "Incline Dumbbell Press", direction: 1), 52.5)
        XCTAssertEqual(LiveActivityMapper.steppedWeight(30, exerciseName: "Cable Fly", direction: -1), 27.5)
    }

    func testWeightNeverGoesBelowZeroAndZeroReadsBodyweight() {
        XCTAssertEqual(LiveActivityMapper.steppedWeight(2.5, exerciseName: "Cable Curl", direction: -1), 0)
        XCTAssertEqual(LiveActivityMapper.steppedWeight(0, exerciseName: "Barbell Row", direction: -1), 0)
        XCTAssertEqual(LiveActivityMapper.weightString(0), "BW")
        XCTAssertEqual(LiveActivityMapper.weightString(62.5), "62.5")
        XCTAssertEqual(LiveActivityMapper.weightString(135), "135")
    }

    func testRepsStepIsClamped() {
        XCTAssertEqual(LiveActivityMapper.steppedReps(8, direction: 1), 9)
        XCTAssertEqual(LiveActivityMapper.steppedReps(0, direction: -1), 0)
        XCTAssertEqual(LiveActivityMapper.steppedReps(100, direction: 1), 100)
    }

    // MARK: - Actions on a session

    private func makeToday() -> TodayViewModel {
        let validation = ValidationService()
        let workouts = WorkoutRepository(localStorage: stack.storage, offlineQueueManager: stack.queue)
        let profiles = ProfileRepository(localStorage: stack.storage,
                                         supabaseService: SupabaseServiceFactory.unreachable(),
                                         offlineQueueManager: stack.queue)
        let months = MonthPlanRepository(localStorage: stack.storage,
                                         supabaseService: SupabaseServiceFactory.unreachable(),
                                         offlineQueueManager: stack.queue)
        let plan = """
        {"exercises": [
         {"name": "Barbell Bench Press", "muscle_group": "Chest", "sets": 3, "reps": "8", "target_weight": "135 lbs"},
         {"name": "Cable Fly", "muscle_group": "Chest", "sets": 2, "reps": "12", "target_weight": "30 lbs"}]}
        """
        let service = WorkoutSessionService(
            aiServiceManager: AIServiceManager(providers: [LAStubProvider(plan)]),
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

    private func startedSession() async -> (TodayViewModel, ActiveWorkoutViewModel) {
        let today = makeToday()
        today.generatePlan(workoutType: "Push", time: 45, energy: 3, notes: nil)
        for _ in 0..<100 where today.phase != .confirmation { try? await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(today.phase, .confirmation)
        today.confirmAndStartWorkout()
        let active = ActiveWorkoutViewModel()
        active.setTargetsProvider = { [weak today] id in today?.setTargets[id] }
        for exercise in today.exercises { active.prefillTargets(for: exercise) }
        return (today, active)
    }

    private func currentKey(_ today: TodayViewModel, _ active: ActiveWorkoutViewModel) -> String {
        state(today.exercises, logged: active.loggedSets, pending: active.pendingSets, targets: today.setTargets).setKey
    }

    func testWeightAndRepsButtonsEditTheCurrentPendingRow() async {
        let (today, active) = await startedSession()
        let first = today.exercises[0]
        let key = currentKey(today, active)
        let startWeight = Double(active.pendingSets[first.id]?[0].weight ?? "") ?? -1
        let startReps = Int(active.pendingSets[first.id]?[0].reps ?? "") ?? -1

        XCTAssertTrue(LiveActivityActions.apply(.weightUp, setKey: key, active: active, today: today))
        XCTAssertEqual(Double(active.pendingSets[first.id]?[0].weight ?? ""), startWeight + 5)
        XCTAssertTrue(LiveActivityActions.apply(.repsDown, setKey: key, active: active, today: today))
        XCTAssertEqual(Int(active.pendingSets[first.id]?[0].reps ?? ""), startReps - 1)
    }

    func testStaleTapIsIgnored() async {
        let (today, active) = await startedSession()
        let before = active.pendingSets
        XCTAssertFalse(LiveActivityActions.apply(.weightUp, setKey: "old:0", active: active, today: today))
        XCTAssertFalse(LiveActivityActions.apply(.logSet, setKey: "old:0", active: active, today: today))
        XCTAssertEqual(active.pendingSets[today.exercises[0].id]?.map(\.weight),
                       before[today.exercises[0].id]?.map(\.weight))
        XCTAssertTrue(active.loggedSets.isEmpty)
    }

    func testLogSetRunsTheNormalPathStartsRestAndAdvances() async {
        let (today, active) = await startedSession()
        let first = today.exercises[0]
        let key = currentKey(today, active)
        let pendingBefore = active.pendingSets[first.id]?.count ?? 0

        XCTAssertTrue(LiveActivityActions.apply(.logSet, setKey: key, active: active, today: today))

        XCTAssertEqual(active.loggedSets[first.id]?.count, 1)
        XCTAssertEqual(today.loggedSets[first.id]?.count, 1, "authoritative copy updated like the in-app button")
        XCTAssertEqual(active.pendingSets[first.id]?.count, pendingBefore - 1)
        XCTAssertEqual(active.activeRestExerciseId, first.id, "rest timer started")
        let stored = stack.storage.fetchSets(exerciseId: first.id)
        XCTAssertEqual(stored.count, 1, "persisted through the session service")

        let next = state(today.exercises, logged: active.loggedSets, pending: active.pendingSets,
                         targets: today.setTargets, restId: active.activeRestExerciseId,
                         restDates: active.restTimerTargetDates)
        XCTAssertEqual(next.setNumber, 2)
        XCTAssertNotNil(next.restEndDate)

        XCTAssertTrue(LiveActivityActions.apply(.skipRest, setKey: next.setKey, active: active, today: today))
        XCTAssertNil(active.activeRestExerciseId)
        XCTAssertFalse(LiveActivityActions.apply(.skipRest, setKey: next.setKey, active: active, today: today),
                       "nothing to skip")
    }
}
