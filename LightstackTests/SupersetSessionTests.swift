import XCTest
@testable import Lightstack

final class SupersetSessionTests: XCTestCase {

    private let workoutId = UUID()

    private func ex(_ name: String, _ idx: Int, group: UUID? = nil, rest: Int? = nil, muscle: String = "Chest") -> Exercise {
        Exercise.create(
            workoutId: workoutId, name: name, muscleGroup: muscle, orderIndex: idx,
            targetSets: 3, targetReps: "10", targetRir: nil, restSeconds: rest, coachNote: nil,
            supersetGroupId: group
        )
    }

    private func set(_ exerciseId: UUID, _ n: Int) -> WorkoutSet {
        WorkoutSet.create(exerciseId: exerciseId, setNumber: n, weightLbs: 50, reps: 10, rir: 2)
    }

    private func pending() -> PendingSetInput { PendingSetInput(weight: "", reps: "", rir: "") }

    // MARK: Rows by round

    func testRowsInterleaveMembersRoundByRound() {
        let a = UUID(), b = UUID()
        let rows = SupersetRounds.rows(
            memberIds: [a, b],
            logged: [a: [set(a, 1)]],
            pending: [a: [pending()], b: [pending(), pending()]]
        )
        XCTAssertEqual(rows.map(\.exerciseId), [a, b, a, b])
        XCTAssertEqual(rows.map(\.round), [0, 0, 1, 1])
        XCTAssertEqual(rows[0].kind, .logged(index: 0))
        XCTAssertEqual(rows[1].kind, .pending(index: 0))
        XCTAssertEqual(rows[2].kind, .pending(index: 0))
        XCTAssertEqual(rows[3].kind, .pending(index: 1))
    }

    func testSingleExerciseRowsAreLoggedThenPending() {
        let a = UUID()
        let rows = SupersetRounds.rows(memberIds: [a], logged: [a: [set(a, 1), set(a, 2)]], pending: [a: [pending()]])
        XCTAssertEqual(rows.map(\.kind), [.logged(index: 0), .logged(index: 1), .pending(index: 0)])
    }

    func testUnevenMembersSkipMissingRows() {
        let a = UUID(), b = UUID()
        let rows = SupersetRounds.rows(memberIds: [a, b], logged: [:], pending: [a: [pending(), pending()], b: [pending()]])
        XCTAssertEqual(rows.map(\.exerciseId), [a, b, a])
    }

    func testPagesCountSupersetOnce() {
        let g = UUID()
        let list = [ex("A", 0), ex("B", 1, group: g), ex("C", 2, group: g)]
        XCTAssertEqual(SupersetGroup.pages(from: list).count, 2)
    }

    // MARK: Rest rule

    func testRestStartsOnlyAfterLastMemberOfSuperset() {
        let g = UUID()
        let list = [ex("A", 0, group: g), ex("B", 1, group: g), ex("C", 2)]
        XCTAssertFalse(SupersetRounds.shouldStartRest(afterLogging: list[0].id, in: list))
        XCTAssertTrue(SupersetRounds.shouldStartRest(afterLogging: list[1].id, in: list))
        XCTAssertTrue(SupersetRounds.shouldStartRest(afterLogging: list[2].id, in: list))
        XCTAssertNil(SupersetRounds.restPlan(afterLogging: list[0].id, in: list))
    }

    func testSupersetRestIsLongestMemberRest() {
        let g = UUID()
        let list = [ex("A", 0, group: g, rest: 60), ex("B", 1, group: g, rest: 120)]
        let plan = SupersetRounds.restPlan(afterLogging: list[1].id, in: list)
        XCTAssertEqual(plan?.seconds, 120)
        XCTAssertEqual(plan?.name, "A + B")
    }

    func testRestDefaultsToNinetyWhenNoMemberHasOne() {
        let g = UUID()
        let list = [ex("A", 0, group: g), ex("B", 1, group: g)]
        XCTAssertEqual(SupersetRounds.restPlan(afterLogging: list[1].id, in: list)?.seconds, 90)
    }

    func testCardioOnlyWithoutRestStartsNothing() {
        let list = [ex("Run", 0, muscle: "Cardio")]
        XCTAssertNil(SupersetRounds.restPlan(afterLogging: list[0].id, in: list))
    }

    func testAddRoundAddsOnePendingRowPerMember() {
        let vm = ActiveWorkoutViewModel()
        let a = ex("A", 0), b = ex("B", 1)
        vm.addRound(for: [a, b])
        XCTAssertEqual(vm.pendingSets[a.id]?.count, 1)
        XCTAssertEqual(vm.pendingSets[b.id]?.count, 1)
    }

    // MARK: Label -> group mapping

    func testGroupIdsShareIdPerLabel() {
        let ids = SupersetGroup.groupIds(forLabels: ["A", nil, "a", "B", "B", "C"])
        XCTAssertEqual(ids[0], ids[2])
        XCTAssertNil(ids[1])
        XCTAssertEqual(ids[3], ids[4])
        XCTAssertNotNil(ids[0])
        XCTAssertNotEqual(ids[0], ids[3])
        XCTAssertNil(ids[5], "a label used once is not a superset")
    }

    func testGenerationJSONMapsLabelsToGroupsAndPullsMembersTogether() throws {
        let json = """
        {"exercises":[
          {"name":"Bench","muscle_group":"Chest","sets":3,"superset":"A"},
          {"name":"Squat","muscle_group":"Legs","sets":3},
          {"name":"Row","muscle_group":"Back","sets":3,"superset":"A"}
        ],"coaching_notes":"x"}
        """
        let list = try XCTUnwrap(WorkoutSessionService.exercises(fromPlanJSON: json, workoutId: workoutId, sanitizeLabel: { $0 }))
        XCTAssertEqual(list.map(\.name), ["Bench", "Row", "Squat"])
        XCTAssertEqual(list.map(\.orderIndex), [0, 1, 2])
        XCTAssertNotNil(list[0].supersetGroupId)
        XCTAssertEqual(list[0].supersetGroupId, list[1].supersetGroupId)
        XCTAssertNil(list[2].supersetGroupId)
    }

    func testGenerationJSONWithoutSupersetKeyHasNoGroups() throws {
        let json = #"{"exercises":[{"name":"Bench","muscle_group":"Chest","sets":3}],"coaching_notes":""}"#
        let list = try XCTUnwrap(WorkoutSessionService.exercises(fromPlanJSON: json, workoutId: workoutId, sanitizeLabel: { $0 }))
        XCTAssertNil(list[0].supersetGroupId)
    }

    func testModificationJSONLabelsProduceOneGroupPerLabel() throws {
        let text = """
        ```json
        {"modifications":[
          {"action":"add","name":"Curl","muscle_group":"Biceps","target_sets":3,"superset":"x"},
          {"action":"add","name":"Pushdown","muscle_group":"Triceps","target_sets":3,"superset":"X"},
          {"action":"add","name":"Plank","muscle_group":"Core","target_sets":3}
        ]}
        ```
        """
        let mods = try WorkoutModificationJSONParser().parse(text)
        XCTAssertEqual(mods.count, 4)
        guard case .groupSuperset(let names) = mods[3] else { return XCTFail("expected superset group") }
        XCTAssertEqual(names, ["Curl", "Pushdown"])
    }

    func testModificationJSONSingleLabelIsIgnored() throws {
        let text = """
        ```json
        {"modifications":[{"action":"add","name":"Curl","muscle_group":"Biceps","target_sets":3,"superset":"x"}]}
        ```
        """
        XCTAssertEqual(try WorkoutModificationJSONParser().parse(text).count, 1)
    }

    func testGroupSupersetModificationLinksNamedExercises() {
        let list = [ex("A", 0), ex("B", 1), ex("C", 2)]
        let grouped = SupersetGroup.group(ids: [list[0].id, list[2].id], in: list)
        XCTAssertEqual(grouped?.map(\.name), ["A", "C", "B"])
        XCTAssertEqual(grouped?[0].supersetGroupId, grouped?[1].supersetGroupId)
        XCTAssertNotNil(grouped?[0].supersetGroupId)
        XCTAssertNil(grouped?[2].supersetGroupId)
        XCTAssertNil(SupersetGroup.group(ids: [list[0].id], in: list))
    }

    // MARK: Repeat session

    func testFreshGroupIdsCopyGroupsWithNewIds() {
        let g = UUID()
        let list = [ex("A", 0), ex("B", 1, group: g), ex("C", 2, group: g)]
        let ids = SupersetGroup.freshGroupIds(copying: list)
        XCTAssertNil(ids[0])
        XCTAssertNotNil(ids[1])
        XCTAssertEqual(ids[1], ids[2])
        XCTAssertNotEqual(ids[1], g)
    }

    func testFreshGroupIdsDropInvalidGroups() {
        let list = [ex("A", 0, group: UUID()), ex("B", 1)]
        XCTAssertEqual(SupersetGroup.freshGroupIds(copying: list).compactMap { $0 }.count, 0)
    }

    // MARK: Finish reconcile guard

    func testReconcileNeverDeletesExerciseWithLoggedSets() {
        let kept = ex("Kept", 0), withSets = ex("Logged", 1), empty = ex("Empty", 2)
        let doomed = WorkoutSessionService.exerciseIdsToDelete(
            stored: [kept, withSets, empty],
            keeping: [kept.id],
            hasLoggedSets: { $0 == withSets.id }
        )
        XCTAssertEqual(doomed, [empty.id])
    }
}
