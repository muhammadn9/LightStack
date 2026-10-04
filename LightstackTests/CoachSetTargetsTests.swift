import XCTest
@testable import Lightstack

final class CoachSetTargetsTests: XCTestCase {

    private let parser = WorkoutModificationJSONParser()

    private func json(_ modification: String) -> String {
        "```json\n{\"modifications\": [\(modification)]}\n```"
    }

    // MARK: - Parser

    func testModifyParsesSetsArrayAndInfersCount() throws {
        let result = try parser.parse(json("""
        {"action":"modify","name":"DB Press","note":"Drive up",
         "sets":[{"weight":"40 lbs","reps":"8","rir":"2"},
                 {"weight":"45 lbs","reps":"8","rir":"1-2"},
                 {"weight":"50 lbs","reps":"6","rir":"0-1"}]}
        """))
        guard case .modifyExercise(_, let sets, _, _, _, _, let note, let perSet) = result[0] else {
            return XCTFail("Expected .modifyExercise")
        }
        XCTAssertEqual(sets, 3)
        XCTAssertEqual(note, "Drive up")
        XCTAssertEqual(perSet.count, 3)
        XCTAssertEqual(perSet[1], SetTarget(weight: "45 lbs", reps: "8", rir: "1-2"))
    }

    func testExplicitSetCountWinsOverInference() throws {
        let result = try parser.parse(json("""
        {"action":"modify","name":"X","new_target_sets":4,"sets":[{"weight":"10 lbs"}]}
        """))
        guard case .modifyExercise(_, let sets, _, _, _, _, _, let perSet) = result[0] else {
            return XCTFail("Expected .modifyExercise")
        }
        XCTAssertEqual(sets, 4)
        XCTAssertEqual(perSet.count, 1)
    }

    func testAddAndReplaceInferTargetSetsFromSets() throws {
        let result = try parser.parse(json("""
        {"action":"add","name":"Fly","muscle_group":"Chest","sets":[{"weight":"20 lbs"},{"weight":"25 lbs"}]},
        {"action":"replace","old_name":"A","new_name":"B","muscle_group":"Back","sets":[{"reps":"10"},{"reps":"8"},{"reps":"6"}]}
        """))
        guard case .addExercise(_, _, let addSets, _, _, _, _, _, let addPerSet) = result[0],
              case .replaceExercise(_, _, _, let repSets, _, _, _, _, _, let repPerSet) = result[1] else {
            return XCTFail("Unexpected cases")
        }
        XCTAssertEqual(addSets, 2)
        XCTAssertEqual(addPerSet.count, 2)
        XCTAssertEqual(repSets, 3)
        XCTAssertEqual(repPerSet.count, 3)
    }

    func testSetFieldsAreLenient() throws {
        let result = try parser.parse(json("""
        {"action":"modify","name":"X",
         "sets":[{"weight":45,"reps":8,"rir":1.5},
                 {"weight":"N/A","reps":null,"rir":""},
                 {}]}
        """))
        guard case .modifyExercise(_, _, _, _, _, _, _, let perSet) = result[0] else {
            return XCTFail("Expected .modifyExercise")
        }
        XCTAssertEqual(perSet.count, 3)
        XCTAssertEqual(perSet[0], SetTarget(weight: "45", reps: "8", rir: "1.5"))
        XCTAssertEqual(perSet[1], SetTarget())
        XCTAssertEqual(perSet[2], SetTarget())
    }

    func testMalformedSetsIsIgnoredNotFatal() throws {
        let result = try parser.parse(json("""
        {"action":"modify","name":"X","new_target_sets":3,"sets":"heavy"}
        """))
        guard case .modifyExercise(_, let sets, _, _, _, _, _, let perSet) = result[0] else {
            return XCTFail("Expected .modifyExercise")
        }
        XCTAssertEqual(sets, 3)
        XCTAssertTrue(perSet.isEmpty)
    }

    func testNoSetsKeyLeavesEmptyArray() throws {
        let result = try parser.parse(json("""
        {"action":"modify","name":"X","new_target_sets":3}
        """))
        guard case .modifyExercise(_, _, _, _, _, _, _, let perSet) = result[0] else {
            return XCTFail("Expected .modifyExercise")
        }
        XCTAssertTrue(perSet.isEmpty)
    }

    // MARK: - SetTarget prefill

    func testSetTargetPrefillParsing() {
        let t = SetTarget(weight: "45 lbs", reps: "8-10", rir: "1-2")
        XCTAssertEqual(t.prefillWeight, "45")
        XCTAssertEqual(t.prefillReps, "8")
        XCTAssertEqual(t.prefillRir, "1")
        XCTAssertEqual(SetTarget(weight: "Bodyweight").prefillWeight, "BW")
        XCTAssertEqual(SetTarget().prefillRir, "")
    }

    // MARK: - Summaries

    func testTitlesAndDetailLines() throws {
        let mod = WorkoutModification.modifyExercise(
            name: "Dumbbell Shoulder Press", newTargetSets: 3, newTargetReps: nil, newTargetRir: nil,
            newRest: nil, newTargetWeight: nil, note: "Smooth reps",
            sets: [SetTarget(weight: "40 lbs", reps: "8", rir: "2"), SetTarget(weight: "45 lbs", reps: "8", rir: "1-2")]
        )
        XCTAssertEqual(mod.title, "Modify · Dumbbell Shoulder Press")
        XCTAssertEqual(mod.detailLines, ["Set 1 · 40 lbs × 8 · RIR 2", "Set 2 · 45 lbs × 8 · RIR 1-2"])
        XCTAssertEqual(mod.noteText, "Smooth reps")

        let rep = WorkoutModification.replaceExercise(
            oldName: "A", newName: "B", muscleGroup: "Back", targetSets: 3, targetReps: "10",
            targetRir: "2", restSeconds: nil, targetWeight: "100 lbs", note: nil
        )
        XCTAssertEqual(rep.title, "Replace · A → B")
        XCTAssertEqual(rep.detailLines.first, "3 sets · 10 reps · RIR 2 · 100 lbs")
        XCTAssertNil(rep.noteText)
        XCTAssertEqual(WorkoutModification.removeExercise(name: "Z").title, "Remove · Z")
    }

    func testAppliedSummaryCompactsWeights() {
        let mod = WorkoutModification.modifyExercise(
            name: "Dumbbell Shoulder Press", newTargetSets: 3, newTargetReps: nil, newTargetRir: nil,
            newRest: nil, newTargetWeight: nil, note: nil,
            sets: [SetTarget(weight: "40 lbs"), SetTarget(weight: "45 lbs"), SetTarget(weight: "50 lbs")]
        )
        XCTAssertEqual(mod.appliedSummary, "✓ Updated Dumbbell Shoulder Press: 3 sets — 40 / 45 / 50 lbs")
        XCTAssertEqual(CoachChatViewModel.confirmationText(for: [mod, .removeExercise(name: "Fly")]),
                       "✓ Updated Dumbbell Shoulder Press: 3 sets — 40 / 45 / 50 lbs\n✓ Removed Fly")
    }

    // MARK: - Per-position prefill

    private func exercise(sets: Int) -> Exercise {
        Exercise.create(
            workoutId: UUID(), name: "DB Press", muscleGroup: "Shoulders", orderIndex: 0,
            targetSets: sets, targetReps: "10", targetRir: "3", restSeconds: 90, coachNote: "Target: 30 lbs"
        )
    }

    func testRefreshPrefillsEachRowByPosition() {
        let vm = ActiveWorkoutViewModel()
        let ex = exercise(sets: 3)
        let targets = [
            SetTarget(weight: "40 lbs", reps: "8", rir: "2"),
            SetTarget(weight: "45 lbs", reps: "8", rir: "1-2"),
            SetTarget(weight: "50 lbs", reps: "6", rir: "0-1")
        ]
        vm.setTargetsProvider = { $0 == ex.id ? targets : nil }
        vm.prefillTargets(for: ex)
        vm.refreshTargets(for: ex)

        let rows = vm.pendingSets[ex.id] ?? []
        XCTAssertEqual(rows.map(\.weight), ["40", "45", "50"])
        XCTAssertEqual(rows.map(\.reps), ["8", "8", "6"])
        XCTAssertEqual(rows.map(\.rir), ["2", "1", "0"])
    }

    func testMissingFieldsAndRowsFallBackToExerciseTargets() {
        let vm = ActiveWorkoutViewModel()
        let ex = exercise(sets: 3)
        vm.setTargetsProvider = { _ in [SetTarget(weight: "40 lbs", reps: nil, rir: nil)] }
        vm.refreshTargets(for: ex)

        let rows = vm.pendingSets[ex.id] ?? []
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].weight, "40")
        XCTAssertEqual(rows[0].reps, "10")
        XCTAssertEqual(rows[0].rir, "3")
        XCTAssertEqual(rows[2].weight, "30")
    }

    func testPositionCountsLoggedSets() {
        let vm = ActiveWorkoutViewModel()
        let ex = exercise(sets: 3)
        vm.setTargetsProvider = { _ in
            [SetTarget(weight: "40 lbs"), SetTarget(weight: "45 lbs"), SetTarget(weight: "50 lbs")]
        }
        vm.loggedSets[ex.id] = [WorkoutSet.create(exerciseId: ex.id, setNumber: 1, weightLbs: 40, reps: 8, rir: 2)]
        vm.refreshTargets(for: ex)
        XCTAssertEqual((vm.pendingSets[ex.id] ?? []).map(\.weight), ["45", "50"])
    }

    func testNoProviderKeepsExistingBehaviour() {
        let vm = ActiveWorkoutViewModel()
        let ex = exercise(sets: 2)
        vm.refreshTargets(for: ex)
        XCTAssertEqual((vm.pendingSets[ex.id] ?? []).map(\.weight), ["30", "30"])
    }

    func testHintRowsKeepHintButTakeCoachText() {
        let vm = ActiveWorkoutViewModel()
        let ex = exercise(sets: 2)
        vm.previousHints[ex.id] = [PreviousSetHint(weightLbs: 35, reps: 8, rir: 2)]
        vm.syncPendingSets(for: ex)
        XCTAssertNotNil(vm.pendingSets[ex.id]?.first?.previous)

        vm.setTargetsProvider = { _ in [SetTarget(weight: "40 lbs", reps: "8", rir: "2"), SetTarget(weight: "45 lbs")] }
        vm.refreshTargets(for: ex)
        let rows = vm.pendingSets[ex.id] ?? []
        XCTAssertNotNil(rows[0].previous)
        XCTAssertEqual(rows[0].weight, "40")
        XCTAssertNil(rows[1].previous)
        XCTAssertEqual(rows[1].weight, "45")
    }

    // MARK: - Session state

    func testSessionStateDecodesWithoutSetTargetsField() throws {
        let workout = Workout.create(userId: UUID(), workoutType: "Push", energyLevel: nil, timeAvailableMinutes: nil)
        let ex = exercise(sets: 3)
        let state = WorkoutSessionPersistence.SessionState(
            workout: workout, exercises: [ex], loggedSets: [:], phase: "active",
            startTime: Date(), userNote: nil, elapsedSeconds: 0, previousHints: nil,
            setTargets: [ex.id: [SetTarget(weight: "40 lbs", reps: "8", rir: "2")]],
            pendingSets: nil, savedAt: nil, isPaused: nil
        )

        let roundTrip = try JSONDecoder().decode(WorkoutSessionPersistence.SessionState.self,
                                                 from: JSONEncoder().encode(state))
        XCTAssertEqual(roundTrip.setTargets?[ex.id]?.first?.weight, "40 lbs")

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        object.removeValue(forKey: "setTargets")
        let legacy = try JSONDecoder().decode(WorkoutSessionPersistence.SessionState.self,
                                              from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.setTargets)
        XCTAssertEqual(legacy.exercises.count, 1)
    }

    // MARK: - Relaunch persistence

    func testRestoredElapsedAddsTimeClosedWhenRunning() {
        let savedAt = Date(timeIntervalSince1970: 1_000)
        let now = savedAt.addingTimeInterval(240)
        XCTAssertEqual(TodayViewModel.restoredElapsed(saved: 400, savedAt: savedAt, paused: false, now: now), 640)
    }

    func testRestoredElapsedIgnoresGapWhenPaused() {
        let savedAt = Date(timeIntervalSince1970: 1_000)
        let now = savedAt.addingTimeInterval(240)
        XCTAssertEqual(TodayViewModel.restoredElapsed(saved: 400, savedAt: savedAt, paused: true, now: now), 400)
    }

    func testPendingSetsRoundTripThroughSessionState() throws {
        let workout = Workout.create(userId: UUID(), workoutType: "Push", energyLevel: nil, timeAvailableMinutes: nil)
        let exerciseId = UUID()
        let rows = [PendingSetInput(weight: "110", reps: "5", rir: "2"), PendingSetInput(weight: "160", reps: "3", rir: "1")]
        let state = WorkoutSessionPersistence.SessionState(
            workout: workout, exercises: [], loggedSets: [:], phase: "active",
            startTime: workout.createdAt, userNote: nil, elapsedSeconds: 60,
            previousHints: nil, setTargets: nil, pendingSets: [exerciseId: rows],
            savedAt: Date(), isPaused: false
        )
        let decoded = try JSONDecoder().decode(WorkoutSessionPersistence.SessionState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.pendingSets?[exerciseId]?.map(\.weight), ["110", "160"])
    }
}
