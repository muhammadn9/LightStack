import XCTest
@testable import Lightstack

final class SupersetImportEditTests: XCTestCase {

    // MARK: - Parser

    func testExplicitSupersetLabel() throws {
        let json = """
        {"workouts":[{"date":"2026-09-14","name":"Arms","exercises":[
          {"name":"Curl","sets":[{"weight_lbs":30,"reps":10}],"superset":"A"},
          {"name":"Pushdown","sets":[{"weight_lbs":40,"reps":12}],"superset":"A"},
          {"name":"Row","sets":[{"weight_lbs":100,"reps":8}],"superset":"N/A"}]}]}
        """
        let ex = try WorkoutImportParser.parse(json).workouts[0].exercises
        XCTAssertEqual(ex.map(\.supersetLabel), ["A", "A", nil])
    }

    func testCombinedFormOwnerExample() throws {
        let json = """
        {"workouts":[{"date":"2026-09-14","name":"Arms","exercises":[
          {"name":"Ez bar incline skull crushers x incline ez bar close grip press:",
           "sets":["50 x 15 abt 2 rir / 50 x 10 abt 1 rir","60 x 10 abt 2 rir / 60 x 8 abt 1 rir"]}]}]}
        """
        let ex = try WorkoutImportParser.parse(json).workouts[0].exercises
        XCTAssertEqual(ex.count, 2)
        XCTAssertEqual(ex[0].name, "Ez bar incline skull crushers")
        XCTAssertEqual(ex[1].name, "incline ez bar close grip press")
        XCTAssertNotNil(ex[0].supersetLabel)
        XCTAssertEqual(ex[0].supersetLabel, ex[1].supersetLabel)
        XCTAssertEqual(ex[0].sets, [ImportedSet(weightLbs: 50, reps: 15, rir: 2), ImportedSet(weightLbs: 60, reps: 10, rir: 2)])
        XCTAssertEqual(ex[1].sets, [ImportedSet(weightLbs: 50, reps: 10, rir: 1), ImportedSet(weightLbs: 60, reps: 8, rir: 1)])
    }

    func testCombinedNameWithMismatchedPartsStaysOneExercise() throws {
        let json = """
        {"workouts":[{"date":"2026-09-14","name":"A","exercises":[
          {"name":"Curl x Press","sets":[{"weight_lbs":30,"reps":10}]}]}]}
        """
        let ex = try WorkoutImportParser.parse(json).workouts[0].exercises
        XCTAssertEqual(ex.count, 1)
        XCTAssertEqual(ex[0].name, "Curl x Press")
        XCTAssertNil(ex[0].supersetLabel)
    }

    func testParseSetText() {
        XCTAssertEqual(WorkoutImportParser.parseSetText("50 x 15 abt 2 rir"), ImportedSet(weightLbs: 50, reps: 15, rir: 2))
        XCTAssertEqual(WorkoutImportParser.parseSetText("60 x 8 ~1 rir"), ImportedSet(weightLbs: 60, reps: 8, rir: 1))
        XCTAssertEqual(WorkoutImportParser.parseSetText("45 x 12 about 3 RIR"), ImportedSet(weightLbs: 45, reps: 12, rir: 3))
        XCTAssertEqual(WorkoutImportParser.parseSetText("45 x 12"), ImportedSet(weightLbs: 45, reps: 12, rir: nil))
        XCTAssertNil(WorkoutImportParser.parseSetText("garbage"))
    }

    // MARK: - Service grouping

    private func ie(_ n: String, _ label: String?) -> ImportedExercise {
        ImportedExercise(name: n, muscleGroup: "Arms", notes: nil,
                         sets: [ImportedSet(weightLbs: 10, reps: 5, rir: nil)], supersetLabel: label)
    }

    func testAssignGroupsOnePerLabelAndSingletonIgnored() {
        let r = WorkoutImportService.assignGroups([ie("a", "A"), ie("b", "B"), ie("c", "A"), ie("d", "B"), ie("e", "C"), ie("f", nil)])
        XCTAssertEqual(r.map(\.exercise.name), ["a", "c", "b", "d", "e", "f"])
        XCTAssertNotNil(r[0].groupId)
        XCTAssertEqual(r[0].groupId, r[1].groupId)
        XCTAssertEqual(r[2].groupId, r[3].groupId)
        XCTAssertNotEqual(r[0].groupId, r[2].groupId)
        XCTAssertNil(r[4].groupId)
        XCTAssertNil(r[5].groupId)
    }

    func testAssignGroupsCapsAtFour() {
        let r = WorkoutImportService.assignGroups((1...6).map { ie("e\($0)", "A") })
        XCTAssertEqual(r.compactMap(\.groupId).count, 4)
        XCTAssertNil(r[4].groupId)
        XCTAssertNil(r[5].groupId)
    }

    // MARK: - Edit draft

    private func makeDraft(grouped: [Bool]) -> (WorkoutEditDraft, Workout, UUID) {
        let w = Workout(id: UUID(), userId: UUID(), localId: "l", date: Date(), workoutType: "Arms",
                        durationMinutes: nil, energyLevel: nil, timeAvailableMinutes: nil, userNote: nil,
                        setupNote: nil, aiProgressionNote: nil, plannedSessionId: nil,
                        syncStatus: .synced, createdAt: Date())
        let gid = UUID()
        var exs: [Exercise] = []
        var sets: [UUID: [WorkoutSet]] = [:]
        for (i, g) in grouped.enumerated() {
            let e = Exercise.create(workoutId: w.id, name: "E\(i)", muscleGroup: "Arms", orderIndex: i,
                                    targetSets: 1, targetReps: nil, targetRir: nil, restSeconds: nil,
                                    coachNote: nil, supersetGroupId: g ? gid : nil)
            exs.append(e)
            sets[e.id] = [WorkoutSet.create(exerciseId: e.id, setNumber: 1, weightLbs: 10, reps: 5, rir: nil)]
        }
        return (WorkoutEditDraft(workout: w, exercises: exs, sets: sets), w, gid)
    }

    func testDraftPreservesGroup() throws {
        let (d, w, gid) = makeDraft(grouped: [true, true, false])
        XCTAssertNotNil(d.supersetLabel(for: d.exercises[0].id))
        let built = try XCTUnwrap(d.build(for: w))
        XCTAssertEqual(built.exercises.map(\.supersetGroupId), [gid, gid, nil])
    }

    func testRemovingMemberDissolvesGroup() throws {
        var (d, w, _) = makeDraft(grouped: [true, true, false])
        d.removeExercise(d.exercises[0].id)
        XCTAssertNil(d.exercises[0].supersetGroupId)
        XCTAssertNil(d.supersetLabel(for: d.exercises[0].id))
        let built = try XCTUnwrap(d.build(for: w))
        XCTAssertTrue(built.exercises.allSatisfy { $0.supersetGroupId == nil })
    }

    func testRemovingAllSetsOfMemberDissolvesOnBuild() throws {
        var (d, w, _) = makeDraft(grouped: [true, true, false])
        d.removeSet(exerciseId: d.exercises[1].id, setId: d.exercises[1].sets[0].id)
        let built = try XCTUnwrap(d.build(for: w))
        XCTAssertTrue(built.exercises.allSatisfy { $0.supersetGroupId == nil })
    }

    func testAddedExerciseUngrouped() {
        var (d, _, _) = makeDraft(grouped: [true, true])
        d.addExercise(name: "New", muscleGroup: "Arms")
        XCTAssertNil(d.exercises.last?.supersetGroupId)
    }

    // MARK: - Detail grouping

    func testDetailSectionsAndRounds() {
        let (d, w, _) = makeDraft(grouped: [true, true, false])
        let exs = d.exercises.compactMap(\.original)
        let sections = WorkoutDetailGrouping.sections(from: exs)
        XCTAssertEqual(sections.count, 2)
        if case .superset(let m) = sections[0] { XCTAssertEqual(m.count, 2) } else { XCTFail("expected superset") }
        _ = w
        let a = [WorkoutSet.create(exerciseId: UUID(), setNumber: 1, weightLbs: 1, reps: 1, rir: nil),
                 WorkoutSet.create(exerciseId: UUID(), setNumber: 2, weightLbs: 1, reps: 1, rir: nil)]
        let b = [WorkoutSet.create(exerciseId: UUID(), setNumber: 1, weightLbs: 1, reps: 1, rir: nil)]
        let rounds = WorkoutDetailGrouping.rounds(setsByMember: [a, b])
        XCTAssertEqual(rounds.map(\.count), [2, 1])
    }
}
