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
        XCTAssertEqual(RestPreference.seconds(forMuscleGroup: "Chest", existing: 60, in: defaults), 180)
    }

    func testCardioKeepsExistingRest() {
        defaults.set(180, forKey: RestPreference.key)
        XCTAssertNil(RestPreference.seconds(forMuscleGroup: "Cardio", in: defaults))
        XCTAssertEqual(RestPreference.seconds(forMuscleGroup: "Cardio", existing: 30, in: defaults), 30)
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
