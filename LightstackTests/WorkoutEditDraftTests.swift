import XCTest
@testable import Lightstack

final class WorkoutEditDraftTests: XCTestCase {
    private let userId = UUID()

    private func makeWorkout() -> Workout {
        Workout(id: UUID(), userId: userId, localId: "l", date: Date(timeIntervalSince1970: 1_000),
                workoutType: "Push", durationMinutes: 40, energyLevel: 3, timeAvailableMinutes: 60,
                userNote: "note", setupNote: "setup", aiProgressionNote: "ai", plannedSessionId: UUID(),
                syncStatus: .synced, createdAt: Date(timeIntervalSince1970: 500))
    }

    private func makeExercise(_ w: Workout, _ name: String, order: Int) -> Exercise {
        Exercise.create(workoutId: w.id, name: name, muscleGroup: "Chest", orderIndex: order,
                        targetSets: 3, targetReps: nil, targetRir: nil, restSeconds: nil, coachNote: nil)
    }

    private func makeSet(_ ex: Exercise, _ n: Int, w: Double, reps: Int, rir: Int?) -> WorkoutSet {
        WorkoutSet.create(exerciseId: ex.id, setNumber: n, weightLbs: w, reps: reps, rir: rir)
    }

    private func sampleDraft() -> (WorkoutEditDraft, Workout) {
        let w = makeWorkout()
        let e1 = makeExercise(w, "Bench", order: 1)
        let e0 = makeExercise(w, "Dips", order: 0)
        let sets: [UUID: [WorkoutSet]] = [
            e1.id: [makeSet(e1, 2, w: 135.5, reps: 8, rir: 1), makeSet(e1, 1, w: 135, reps: 10, rir: nil)],
            e0.id: [makeSet(e0, 1, w: 0, reps: 12, rir: 2)]
        ]
        return (WorkoutEditDraft(workout: w, exercises: [e1, e0], sets: sets), w)
    }

    func testInitOrdersAndFormats() {
        let (d, w) = sampleDraft()
        XCTAssertEqual(d.name, "Push")
        XCTAssertEqual(d.date, w.date)
        XCTAssertEqual(d.notes, "note")
        XCTAssertEqual(d.exercises.map(\.name), ["Dips", "Bench"])
        XCTAssertEqual(d.exercises[0].sets[0].weight, "BW")
        XCTAssertEqual(d.exercises[1].sets.map(\.reps), ["10", "8"])
        XCTAssertEqual(d.exercises[1].sets.map(\.weight), ["135", "135.5"])
        XCTAssertEqual(d.exercises[1].sets.map(\.rir), ["", "1"])
    }

    func testNilNoteBecomesEmpty() {
        var w = makeWorkout(); w.userNote = nil
        XCTAssertEqual(WorkoutEditDraft(workout: w, exercises: [], sets: [:]).notes, "")
    }

    func testValidDraftHasNoErrors() {
        XCTAssertTrue(sampleDraft().0.validate().isEmpty)
    }

    func testWeightRules() {
        var (d, _) = sampleDraft()
        for ok in ["", "BW", "bw", "0", "45.5"] {
            d.exercises[0].sets[0].weight = ok
            XCTAssertTrue(d.validate().isEmpty, "weight \(ok)")
        }
        for bad in ["-5", "abc"] {
            d.exercises[0].sets[0].weight = bad
            let errs = d.validate()
            XCTAssertEqual(errs.count, 1, "weight \(bad)")
            XCTAssertEqual(errs.first?.field, .weight)
            XCTAssertEqual(errs.first?.exerciseId, d.exercises[0].id)
            XCTAssertEqual(errs.first?.setId, d.exercises[0].sets[0].id)
        }
    }

    func testRepsRules() {
        var (d, _) = sampleDraft()
        d.exercises[0].sets[0].reps = "0"
        XCTAssertTrue(d.validate().isEmpty)
        for bad in ["", "  ", "-1", "2.5", "x"] {
            d.exercises[0].sets[0].reps = bad
            XCTAssertEqual(d.validate().map(\.field), [.reps], "reps '\(bad)'")
        }
    }

    func testRirRules() {
        var (d, _) = sampleDraft()
        for ok in ["", "0", "10"] {
            d.exercises[0].sets[0].rir = ok
            XCTAssertTrue(d.validate().isEmpty, "rir \(ok)")
        }
        for bad in ["11", "-1", "1.5", "x"] {
            d.exercises[0].sets[0].rir = bad
            XCTAssertEqual(d.validate().map(\.field), [.rir], "rir \(bad)")
        }
    }

    func testBuildNilWhenInvalid() {
        var (d, w) = sampleDraft()
        d.exercises[0].sets[0].reps = ""
        XCTAssertNil(d.build(for: w))
    }

    func testBuildRoundTrip() throws {
        let (d, w) = sampleDraft()
        let built = try XCTUnwrap(d.build(for: w))
        XCTAssertEqual(built.workout.id, w.id)
        XCTAssertEqual(built.workout.workoutType, "Push")
        XCTAssertEqual(built.workout.durationMinutes, 40)
        XCTAssertEqual(built.workout.userNote, "note")
        XCTAssertEqual(built.exercises.map(\.name), ["Dips", "Bench"])
        XCTAssertEqual(built.exercises.map(\.orderIndex), [0, 1])
        XCTAssertEqual(built.exercises.map(\.targetSets), [1, 2])
        XCTAssertTrue(built.exercises.allSatisfy { $0.workoutId == w.id })
        let bench = built.exercises[1]
        let sets = try XCTUnwrap(built.sets[bench.id])
        XCTAssertEqual(sets.map(\.setNumber), [1, 2])
        XCTAssertEqual(sets.map(\.weightLbs), [135, 135.5])
        XCTAssertEqual(sets.map(\.reps), [10, 8])
        XCTAssertEqual(sets.map(\.rir), [nil, 1])
        XCTAssertTrue(sets.allSatisfy { $0.recordedAt == w.date && !$0.isPR && $0.exerciseId == bench.id })
        XCTAssertEqual(built.sets[built.exercises[0].id]?.first?.weightLbs, 0)
    }

    func testBuildGivesFreshIds() throws {
        let w = makeWorkout()
        let e = makeExercise(w, "Bench", order: 0)
        let s = makeSet(e, 1, w: 100, reps: 5, rir: 2)
        let d = WorkoutEditDraft(workout: w, exercises: [e], sets: [e.id: [s]])
        let built = try XCTUnwrap(d.build(for: w))
        XCTAssertNotEqual(built.exercises[0].id, e.id)
        XCTAssertNotEqual(built.sets[built.exercises[0].id]?.first?.id, s.id)
    }

    func testBuildNameDateNotes() throws {
        var (d, w) = sampleDraft()
        d.name = "   "
        d.notes = "  "
        d.date = Date(timeIntervalSince1970: 9_999)
        let built = try XCTUnwrap(d.build(for: w))
        XCTAssertEqual(built.workout.workoutType, "Workout")
        XCTAssertNil(built.workout.userNote)
        XCTAssertEqual(built.workout.date, Date(timeIntervalSince1970: 9_999))
        XCTAssertEqual(built.sets.values.flatMap { $0 }.first?.recordedAt, Date(timeIntervalSince1970: 9_999))
        w.userNote = nil
    }

    func testBuildDropsExercisesWithoutSets() throws {
        var (d, w) = sampleDraft()
        d.exercises[0].sets = []
        let built = try XCTUnwrap(d.build(for: w))
        XCTAssertEqual(built.exercises.map(\.name), ["Bench"])
        XCTAssertEqual(built.exercises[0].orderIndex, 0)
    }

    func testEmpty() {
        var (d, _) = sampleDraft()
        XCTAssertFalse(d.isEmpty)
        for i in d.exercises.indices { d.exercises[i].sets = [] }
        XCTAssertTrue(d.isEmpty)
        XCTAssertTrue(d.validate().isEmpty)
    }

    func testAddSetCopiesLast() {
        var (d, _) = sampleDraft()
        let id = d.exercises[1].id
        d.addSet(to: id)
        let sets = d.exercises[1].sets
        XCTAssertEqual(sets.count, 3)
        XCTAssertEqual(sets[2].weight, sets[1].weight)
        XCTAssertEqual(sets[2].reps, sets[1].reps)
        XCTAssertEqual(sets[2].rir, sets[1].rir)
        XCTAssertNotEqual(sets[2].id, sets[1].id)
    }

    func testAddSetToEmptyExercise() {
        var (d, _) = sampleDraft()
        d.exercises[0].sets = []
        d.addSet(to: d.exercises[0].id)
        let s = d.exercises[0].sets[0]
        XCTAssertEqual([s.weight, s.reps, s.rir], ["", "", ""])
    }

    func testRemoveSetAndExercise() {
        var (d, _) = sampleDraft()
        let ex = d.exercises[1]
        d.removeSet(exerciseId: ex.id, setId: ex.sets[0].id)
        XCTAssertEqual(d.exercises[1].sets.count, 1)
        d.removeExercise(ex.id)
        XCTAssertEqual(d.exercises.map(\.name), ["Dips"])
    }

    func testAddExercise() {
        var (d, _) = sampleDraft()
        d.addExercise(name: "Fly", muscleGroup: "Chest")
        let e = d.exercises.last
        XCTAssertEqual(e?.name, "Fly")
        XCTAssertEqual(e?.muscleGroup, "Chest")
        XCTAssertEqual(e?.sets.count, 1)
        XCTAssertEqual(e?.sets.first?.reps, "")
        XCTAssertEqual(d.validate().map(\.field), [.reps])
    }

    func testBuildPreservesUneditedData() throws {
        let w = makeWorkout()
        var e = makeExercise(w, "Bench", order: 0)
        e.coachNote = "Target: 135 lbs"; e.targetReps = "8-10"; e.targetRir = "2"; e.restSeconds = 90
        var s = makeSet(e, 1, w: 135, reps: 8, rir: 2)
        s.userFeedback = "felt heavy"
        var c = makeExercise(w, "Run", order: 1)
        c.muscleGroup = "Cardio"
        var cs = makeSet(c, 1, w: 0, reps: 0, rir: nil)
        cs.durationSeconds = 1200; cs.distanceMiles = 2.5; cs.inclineLevel = 3
        var d = WorkoutEditDraft(workout: w, exercises: [e, c], sets: [e.id: [s], c.id: [cs]])
        d.exercises[0].sets[0].reps = "9"
        d.addSet(to: d.exercises[0].id)
        let built = try XCTUnwrap(d.build(for: w))
        let be = built.exercises[0]
        XCTAssertEqual(be.coachNote, "Target: 135 lbs")
        XCTAssertEqual(be.targetReps, "8-10")
        XCTAssertEqual(be.targetRir, "2")
        XCTAssertEqual(be.restSeconds, 90)
        XCTAssertEqual(be.targetSets, 2)
        let bs = try XCTUnwrap(built.sets[be.id])
        XCTAssertEqual(bs[0].reps, 9)
        XCTAssertEqual(bs[0].userFeedback, "felt heavy")
        XCTAssertNil(bs[1].userFeedback)
        XCTAssertNil(bs[1].durationSeconds)
        XCTAssertNil(bs[1].distanceMiles)
        XCTAssertNil(bs[1].inclineLevel)
        let cardio = try XCTUnwrap(built.sets[built.exercises[1].id]?.first)
        XCTAssertEqual(cardio.durationSeconds, 1200)
        XCTAssertEqual(cardio.distanceMiles, 2.5)
        XCTAssertEqual(cardio.inclineLevel, 3)
    }

    func testAddedExerciseHasNoCarriedData() throws {
        var (d, w) = sampleDraft()
        d.addExercise(name: "Fly", muscleGroup: "Chest")
        d.exercises[2].sets[0].reps = "10"
        let built = try XCTUnwrap(d.build(for: w))
        XCTAssertNil(built.exercises[2].coachNote)
        XCTAssertNil(built.sets[built.exercises[2].id]?.first?.userFeedback)
    }
}
