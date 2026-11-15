import XCTest
@testable import Lightstack

final class RestPreferenceTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "RestPreferenceTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        UserDefaults.standard.removeObject(forKey: RestPreference.key)
        super.tearDown()
    }

    private func ex(_ name: String, _ idx: Int, group: UUID? = nil, rest: Int? = nil, muscle: String = "Chest") -> Exercise {
        Exercise(id: UUID(), workoutId: UUID(), localId: nil, name: name, muscleGroup: muscle, orderIndex: idx,
                 targetSets: 3, targetReps: "10", targetRir: nil, restSeconds: rest, coachNote: nil,
                 syncStatus: .pending, supersetGroupId: group)
    }

    func testUnsetPreferenceIsNinety() {
        XCTAssertEqual(RestPreference.defaultSeconds(in: defaults), 90)
    }

    func testSetPreferenceIsUsed() {
        defaults.set(180, forKey: RestPreference.key)
        XCTAssertEqual(RestPreference.defaultSeconds(in: defaults), 180)
    }

    func testNewStrengthExercisesStoreNoRestSoTheLiveDefaultApplies() {
        XCTAssertNil(RestPreference.storedSeconds(forMuscleGroup: "Chest"))
        XCTAssertNil(RestPreference.storedSeconds(forMuscleGroup: "Chest", existing: 60))
    }

    func testCardioKeepsExistingRest() {
        XCTAssertNil(RestPreference.storedSeconds(forMuscleGroup: "Cardio"))
        XCTAssertEqual(RestPreference.storedSeconds(forMuscleGroup: "Cardio", existing: 30), 30)
    }

    func testUnprescribedExerciseFollowsTheCurrentDefaultWhenItChanges() {
        let list = [ex("A", 0)]   // nothing prescribed: restSeconds nil
        UserDefaults.standard.set(90, forKey: RestPreference.key)
        XCTAssertEqual(SupersetRounds.manualRestPlan(forPageContaining: list[0].id, in: list)?.seconds, 90)
        UserDefaults.standard.set(300, forKey: RestPreference.key)
        XCTAssertEqual(SupersetRounds.manualRestPlan(forPageContaining: list[0].id, in: list)?.seconds, 300)
        XCTAssertEqual(SupersetRounds.restPlan(afterLogging: list[0].id, in: list)?.seconds, 300)
        XCTAssertEqual(ActiveWorkoutView.restSeconds(for: list[0]), 300)
    }

    // MARK: Releasing an old stamped default

    func testReleasingDropsOnlyTheOldStampedDefault() {
        let stamped = ex("Stamped", 0, rest: 90)
        let prescribed = ex("Prescribed", 1, rest: 150)
        let perSet = ex("PerSet", 2, rest: 90)
        let cardio = ex("Run", 3, rest: 90, muscle: "Cardio")
        let targets: [UUID: [SetTarget]] = [perSet.id: [SetTarget(weight: "100", reps: "5", restSeconds: 180)]]
        let released = RestPreference.releasingStampedRest([stamped, prescribed, perSet, cardio], stamped: 90,
                                                           setTargets: targets)
        XCTAssertEqual(released.map(\.id), [stamped.id])
        XCTAssertNil(released.first?.restSeconds)
    }

    func testReleasingKeepsExercisesWhoseSetTargetsCarryNoRest() {
        let e = ex("A", 0, rest: 90)
        let released = RestPreference.releasingStampedRest([e], stamped: 90,
                                                           setTargets: [e.id: [SetTarget(weight: "100", reps: "5")]])
        XCTAssertEqual(released.count, 1)
    }

    @MainActor
    func testRunningWorkoutFollowsTheSettingAfterItChangesFromTheStampedDefault() {
        let stack = OutboxTestStack(userId: UUID())
        let validation = ValidationService()
        let workouts = WorkoutRepository(localStorage: stack.storage, offlineQueueManager: stack.queue)
        let profiles = ProfileRepository(localStorage: stack.storage,
                                         supabaseService: SupabaseServiceFactory.unreachable(),
                                         offlineQueueManager: stack.queue)
        let months = MonthPlanRepository(localStorage: stack.storage,
                                         supabaseService: SupabaseServiceFactory.unreachable(),
                                         offlineQueueManager: stack.queue)
        let service = WorkoutSessionService(
            aiServiceManager: AIServiceManager(providers: []),
            coachPromptService: CoachPromptService(validationService: validation),
            coachContextBuilder: CoachContextBuilder(profileRepository: profiles, workoutRepository: workouts,
                                                     localStorage: stack.storage, validationService: validation),
            workoutRepository: workouts, monthPlanRepository: months, localStorage: stack.storage,
            validationService: validation, offlineQueueManager: stack.queue)
        let vm = TodayViewModel(sessionService: service, workoutRepository: workouts,
                                prRepository: PRRepository(localStorage: stack.storage, offlineQueueManager: stack.queue),
                                sessionPersistence: WorkoutSessionPersistence())
        let stamped = ex("Stamped", 0, rest: 90), prescribed = ex("Prescribed", 1, rest: 150)
        vm.exercises = [stamped, prescribed]

        let suite = UserDefaults(suiteName: "RestPreferenceTests.reconcile") ?? .standard
        suite.removePersistentDomain(forName: "RestPreferenceTests.reconcile")
        defer { suite.removePersistentDomain(forName: "RestPreferenceTests.reconcile") }
        suite.set(90, forKey: RestPreference.key)
        vm.reconcileRestDefault(defaults: suite)               // first look: records 90, changes nothing
        XCTAssertEqual(vm.exercises[0].restSeconds, 90)
        suite.set(300, forKey: RestPreference.key)             // Settings changed mid-workout
        vm.reconcileRestDefault(defaults: suite)
        XCTAssertNil(vm.exercises[0].restSeconds, "an exercise on the old default follows the new one")
        XCTAssertEqual(vm.exercises[1].restSeconds, 150, "a prescribed rest is untouched")
        XCTAssertEqual(suite.integer(forKey: RestPreference.lastAppliedKey), 300)
    }

    func testRestPlanFallsBackToPreference() {
        UserDefaults.standard.set(150, forKey: RestPreference.key)
        let list = [ex("A", 0)]
        XCTAssertEqual(SupersetRounds.restPlan(afterLogging: list[0].id, in: list)?.seconds, 150)
        XCTAssertEqual(ActiveWorkoutView.restSeconds(for: list[0]), 150)
    }

    func testSupersetUsesLongestMemberRest() {
        UserDefaults.standard.set(90, forKey: RestPreference.key)
        let g = UUID()
        let list = [ex("A", 0, group: g, rest: 150), ex("B", 1, group: g, rest: 240)]
        XCTAssertEqual(SupersetRounds.restPlan(afterLogging: list[1].id, in: list)?.seconds, 240)
        let manual = SupersetRounds.manualRestPlan(forPageContaining: list[0].id, in: list)
        XCTAssertEqual(manual?.seconds, 240)
        XCTAssertEqual(manual?.timerId, list[1].id)
    }

    func testExplicitExerciseRestWinsOverPreference() {
        UserDefaults.standard.set(90, forKey: RestPreference.key)
        let list = [ex("A", 0, rest: 120)]
        XCTAssertEqual(SupersetRounds.restPlan(afterLogging: list[0].id, in: list)?.seconds, 120)
        XCTAssertEqual(ActiveWorkoutView.restSeconds(for: list[0]), 120)
    }

    func testManualRestForCardioUsesPreference() {
        UserDefaults.standard.set(180, forKey: RestPreference.key)
        let list = [ex("Run", 0, muscle: "Cardio")]
        XCTAssertEqual(SupersetRounds.manualRestPlan(forPageContaining: list[0].id, in: list)?.seconds, 180)
    }

    func testCancelRestTimerClearsState() {
        let vm = ActiveWorkoutViewModel()
        var cancelled = 0
        vm.onRestTimerCancel = { cancelled += 1 }
        let id = UUID()
        vm.startRestTimer(for: id, seconds: 60, exerciseName: "A")
        cancelled = 0
        vm.cancelRestTimer(for: [id])
        XCTAssertNil(vm.restTimerTargetDates[id])
        XCTAssertNil(vm.activeRestExerciseId)
        XCTAssertEqual(cancelled, 1)
    }

    func testStartingRestForAnotherExerciseReplacesPrevious() {
        let vm = ActiveWorkoutViewModel()
        let a = UUID(), b = UUID()
        vm.startRestTimer(for: a, seconds: 60, exerciseName: "A")
        vm.startRestTimer(for: b, seconds: 90, exerciseName: "B")
        XCTAssertNil(vm.restTimerTargetDates[a])
        XCTAssertNil(vm.restTimerTotalSeconds[a])
        XCTAssertEqual(vm.restTimerTargetDates.count, 1)
        XCTAssertEqual(vm.activeRestExerciseId, b)
        XCTAssertFalse(vm.isRestRunning(for: [a]))
        XCTAssertTrue(vm.isRestRunning(for: [b]))
        var cancelled = 0
        vm.onRestTimerCancel = { cancelled += 1 }
        vm.cancelRestTimer(for: [a])  // not running: no-op
        XCTAssertEqual(cancelled, 0)
        vm.cancelRestTimer(for: [b])
        XCTAssertTrue(vm.restTimerTargetDates.isEmpty)
        XCTAssertTrue(vm.restTimerTotalSeconds.isEmpty)
        XCTAssertNil(vm.activeRestExerciseId)
        XCTAssertEqual(cancelled, 1)
    }

    func testPlanPromptIncludesPreference() {
        let service = CoachPromptService(validationService: ValidationService())
        let prompt = service.buildSystemPrompt(profile: nil, task: .plan, restSeconds: 180)
        XCTAssertTrue(prompt.contains("preferred rest: 180 s"))
        XCTAssertFalse(service.buildSystemPrompt(profile: nil, task: .chat, restSeconds: 180).contains("preferred rest"))
    }

    func testLocalRestCommandSetsExplicitRest() {
        let list = [ex("Bench Press", 0)]
        let cmd = LocalChatCommandParser.parse("rest 2 min on bench press", exercises: list, knownNames: [])
        guard case .modifyExercise(_, _, _, _, let newRest, _, _, _)? = cmd?.modifications.first else {
            return XCTFail("Expected a modify command")
        }
        XCTAssertEqual(newRest, 120)
    }
}
