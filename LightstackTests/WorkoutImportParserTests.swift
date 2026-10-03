import XCTest
@testable import Lightstack

final class WorkoutImportParserTests: XCTestCase {

    private func json(date: String = "\"2026-09-14\"", name: String = "\"Pull\"", exercises: String) -> String {
        "{\"workouts\":[{\"date\":\(date),\"name\":\(name),\"notes\":\"N/A\",\"exercises\":[\(exercises)]}]}"
    }
    private func ex(name: String = "\"Barbell Row\"", mg: String = "\"Back\"", notes: String = "\"N/A\"", sets: String) -> String {
        "{\"name\":\(name),\"muscle_group\":\(mg),\"notes\":\(notes),\"sets\":[\(sets)]}"
    }
    private func set(w: String = "135", r: String = "8", rir: String = "\"1-2\"") -> String {
        "{\"weight_lbs\":\(w),\"reps\":\(r),\"rir\":\(rir)}"
    }
    private func parse(_ s: String) throws -> WorkoutImportParseResult { try WorkoutImportParser.parse(s) }
    private func firstSet(_ s: String) throws -> ImportedSet? {
        try parse(s).workouts.first?.exercises.first?.sets.first
    }

    func testFullSpecExample() throws {
        let r = try parse(json(exercises: ex(sets: set())))
        XCTAssertEqual(r.workouts.count, 1)
        let w = r.workouts[0]
        XCTAssertEqual(w.name, "Pull")
        XCTAssertNil(w.notes)
        XCTAssertEqual(w.exercises[0].name, "Barbell Row")
        XCTAssertEqual(w.exercises[0].muscleGroup, "Back")
        XCTAssertEqual(w.exercises[0].sets, [ImportedSet(weightLbs: 135, reps: 8, rir: 1)])
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour], from: w.date)
        XCTAssertEqual(c.year, 2026); XCTAssertEqual(c.month, 9); XCTAssertEqual(c.day, 14); XCTAssertEqual(c.hour, 12)
    }

    func testFencedJSON() throws {
        let text = "```json\n" + json(exercises: ex(sets: set())) + "\n```"
        XCTAssertEqual(try parse(text).workouts.count, 1)
    }

    func testSurroundingProse() throws {
        let text = "Here you go!\n" + json(exercises: ex(sets: set())) + "\nHope that helps."
        XCTAssertEqual(try parse(text).workouts.count, 1)
    }

    func testTopLevelArray() throws {
        let text = "[{\"date\":\"2026-09-14\",\"name\":\"Pull\",\"exercises\":[\(ex(sets: set()))]}]"
        XCTAssertEqual(try parse(text).workouts.count, 1)
    }

    func testISO8601Date() throws {
        let r = try parse(json(date: "\"2026-09-14T08:30:00Z\"", exercises: ex(sets: set())))
        XCTAssertEqual(r.workouts.count, 1)
    }

    func testUnknownDateSkipped() throws {
        for d in ["\"N/A\"", "null", "\"\"", "\"garbage\""] {
            let r = try parse(json(date: d, exercises: ex(sets: set())))
            XCTAssertTrue(r.workouts.isEmpty)
            XCTAssertEqual(r.skipped, [.noDate(workoutName: "Pull")], "date \(d)")
        }
    }

    func testMissingDateKeySkipped() throws {
        let r = try parse("{\"workouts\":[{\"name\":\"Pull\",\"exercises\":[\(ex(sets: set()))]}]}")
        XCTAssertEqual(r.skipped, [.noDate(workoutName: "Pull")])
    }

    func testNoExercisesSkipped() throws {
        let r = try parse(json(exercises: ""))
        XCTAssertTrue(r.workouts.isEmpty)
        guard case .noExercises(let name, let date)? = r.skipped.first else { return XCTFail("expected noExercises") }
        XCTAssertEqual(name, "Pull")
        XCTAssertNotNil(date)
    }

    func testAllExercisesSkippedReportsNoExercises() throws {
        let r = try parse(json(exercises: ex(sets: set(r: "\"N/A\""))))
        XCTAssertTrue(r.workouts.isEmpty)
        XCTAssertEqual(r.skipped.count, 1)
        guard case .noExercises? = r.skipped.first else { return XCTFail("expected noExercises") }
    }

    func testUnknownWorkoutNameDefaults() throws {
        for n in ["\"N/A\"", "null", "\"\""] {
            let r = try parse(json(name: n, exercises: ex(sets: set())))
            XCTAssertEqual(r.workouts.first?.name, "Imported Workout")
        }
    }

    func testUnknownExerciseNameSkipped() throws {
        let exs = ex(name: "\"N/A\"", sets: set()) + "," + ex(sets: set())
        let r = try parse(json(exercises: exs))
        XCTAssertEqual(r.workouts[0].exercises.count, 1)
        XCTAssertEqual(r.workouts[0].exercises[0].name, "Barbell Row")
    }

    func testUnknownMuscleGroupInferred() throws {
        let r = try parse(json(exercises: ex(name: "\"Barbell Row\"", mg: "\"N/A\"", sets: set())))
        XCTAssertEqual(r.workouts[0].exercises[0].muscleGroup, WorkoutSessionService.inferMuscleGroup("Barbell Row"))
    }

    func testUnknownWeightIsZero() throws {
        for w in ["\"N/A\"", "null", "\"\""] {
            XCTAssertEqual(try firstSet(json(exercises: ex(sets: set(w: w))))?.weightLbs, 0)
        }
        let noKey = json(exercises: ex(sets: "{\"reps\":8}"))
        XCTAssertEqual(try firstSet(noKey)?.weightLbs, 0)
    }

    func testWeightStringWithUnit() throws {
        XCTAssertEqual(try firstSet(json(exercises: ex(sets: set(w: "\"135 lbs\""))))?.weightLbs, 135)
        XCTAssertEqual(try firstSet(json(exercises: ex(sets: set(w: "\"132.5\""))))?.weightLbs, 132.5)
    }

    func testUnknownRepsSkipsSet() throws {
        let sets = set(r: "\"N/A\"") + "," + set(r: "\"abc\"") + "," + set(r: "10")
        let r = try parse(json(exercises: ex(sets: sets)))
        XCTAssertEqual(r.workouts[0].exercises[0].sets.count, 1)
        XCTAssertEqual(r.workouts[0].exercises[0].sets[0].reps, 10)
    }

    func testRepsFromString() throws {
        XCTAssertEqual(try firstSet(json(exercises: ex(sets: set(r: "\"8 reps\""))))?.reps, 8)
    }

    func testRIRRules() throws {
        XCTAssertEqual(try firstSet(json(exercises: ex(sets: set(rir: "\"2-3\""))))?.rir, 2)
        XCTAssertEqual(try firstSet(json(exercises: ex(sets: set(rir: "2"))))?.rir, 2)
        XCTAssertEqual(try firstSet(json(exercises: ex(sets: set(rir: "0"))))?.rir, 0)
        XCTAssertEqual(try firstSet(json(exercises: ex(sets: set(rir: "10"))))?.rir, 10)
        XCTAssertNil(try firstSet(json(exercises: ex(sets: set(rir: "\"N/A\""))))?.rir)
        XCTAssertNil(try firstSet(json(exercises: ex(sets: set(rir: "null"))))?.rir)
        XCTAssertNil(try firstSet(json(exercises: ex(sets: set(rir: "\"12\""))))?.rir)
        XCTAssertNil(try firstSet(json(exercises: ex(sets: set(rir: "-1"))))?.rir)
        XCTAssertNil(try firstSet(json(exercises: ex(sets: "{\"weight_lbs\":1,\"reps\":5}")))?.rir)
        // set must still exist when RIR unknown
        XCTAssertNotNil(try firstSet(json(exercises: ex(sets: set(rir: "\"N/A\"")))))
    }

    func testNotesRules() throws {
        let text = "{\"workouts\":[{\"date\":\"2026-09-14\",\"name\":\"Pull\",\"notes\":\"Felt great\",\"exercises\":[\(ex(notes: "\"Wrist sore\"", sets: set())),\(ex(name: "\"Lat Pulldown\"", notes: "\"n/a\"", sets: set()))]}]}"
        let w = try parse(text).workouts[0]
        XCTAssertEqual(w.notes, "Felt great")
        XCTAssertEqual(w.exercises[0].notes, "Wrist sore")
        XCTAssertNil(w.exercises[1].notes)
    }

    func testGarbageThrowsNoJSONFound() {
        XCTAssertThrowsError(try parse("hello there")) { XCTAssertEqual($0 as? WorkoutImportError, .noJSONFound) }
    }

    func testBrokenJSONThrowsInvalid() {
        XCTAssertThrowsError(try parse("{\"workouts\": [ {oops} ]}")) { XCTAssertEqual($0 as? WorkoutImportError, .invalidJSON) }
    }

    func testEmptyWorkoutsThrowsNoWorkouts() {
        XCTAssertThrowsError(try parse("{\"workouts\": []}")) { XCTAssertEqual($0 as? WorkoutImportError, .noWorkouts) }
    }

    func testPromptContents() {
        XCTAssertTrue(WorkoutImportPrompt.text.contains("N/A"))
        XCTAssertTrue(WorkoutImportPrompt.text.contains("YYYY-MM-DD"))
        XCTAssertTrue(WorkoutImportPrompt.text.hasSuffix("My workout records:\n\n"))
    }

    func testZeroRepsKeptAsUnableSet() throws {
        XCTAssertEqual(try firstSet(json(exercises: ex(sets: set(r: "0"))))?.reps, 0)
    }
}
