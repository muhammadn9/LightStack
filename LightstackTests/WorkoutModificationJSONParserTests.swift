import XCTest
@testable import Lightstack

final class WorkoutModificationJSONParserTests: XCTestCase {

    private let parser = WorkoutModificationJSONParser()

    // MARK: - Helpers

    private func json(_ modifications: String) -> String {
        """
        ```json
        {
          "modifications": [
            \(modifications)
          ]
        }
        ```
        """
    }

    // MARK: - No block present

    func testNoJSONBlockReturnsEmptyArray() throws {
        let text = "Here is some advice about your workout. No modifications today."
        let result = try parser.parse(text)
        XCTAssertTrue(result.isEmpty)
    }

    func testEmptyStringReturnsEmptyArray() throws {
        let result = try parser.parse("")
        XCTAssertTrue(result.isEmpty)
    }

    func testPlainProseWithNoFenceReturnsEmptyArray() throws {
        let text = "You should add more volume. Try adding an extra set."
        let result = try parser.parse(text)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Malformed JSON throws

    func testMalformedJSONThrows() {
        let text = """
        Here's my advice.
        ```json
        { this is not valid json
        ```
        """
        XCTAssertThrowsError(try parser.parse(text)) { error in
            guard case WorkoutModificationJSONParserError.malformedJSON = error else {
                return XCTFail("Expected .malformedJSON, got \(error)")
            }
        }
    }

    func testValidJSONButMissingModificationsKeyThrows() {
        let text = """
        Advice here.
        ```json
        { "changes": [] }
        ```
        """
        XCTAssertThrowsError(try parser.parse(text))
    }

    func testAddActionMissingNameThrows() {
        let text = json("""
        { "action": "add", "muscle_group": "Chest", "target_sets": 3 }
        """)
        XCTAssertThrowsError(try parser.parse(text)) { error in
            guard case WorkoutModificationJSONParserError.invalidSchema = error else {
                return XCTFail("Expected .invalidSchema, got \(error)")
            }
        }
    }

    func testUnknownActionThrows() {
        let text = json("""
        { "action": "teleport", "name": "Bench Press" }
        """)
        XCTAssertThrowsError(try parser.parse(text))
    }

    // MARK: - add action

    func testAddExerciseAllFields() throws {
        let text = json("""
        {
          "action": "add",
          "name": "Bench Press",
          "muscle_group": "Chest",
          "target_sets": 4,
          "target_reps": "8-10",
          "target_rir": "2",
          "rest_seconds": 90,
          "note": "Keep tight arch"
        }
        """)
        let result = try parser.parse(text)
        XCTAssertEqual(result.count, 1)
        guard case .addExercise(let name, let muscleGroup, let sets, let reps, let rir, let rest, let note) = result[0] else {
            return XCTFail("Expected .addExercise")
        }
        XCTAssertEqual(name, "Bench Press")
        XCTAssertEqual(muscleGroup, "Chest")
        XCTAssertEqual(sets, 4)
        XCTAssertEqual(reps, "8-10")
        XCTAssertEqual(rir, "2")
        XCTAssertEqual(rest, 90)
        XCTAssertEqual(note, "Keep tight arch")
    }

    func testAddExerciseRequiredFieldsOnly() throws {
        let text = json("""
        {
          "action": "add",
          "name": "Squat",
          "muscle_group": "Legs",
          "target_sets": 3
        }
        """)
        let result = try parser.parse(text)
        XCTAssertEqual(result.count, 1)
        guard case .addExercise(let name, let muscleGroup, let sets, let reps, let rir, let rest, let note) = result[0] else {
            return XCTFail("Expected .addExercise")
        }
        XCTAssertEqual(name, "Squat")
        XCTAssertEqual(muscleGroup, "Legs")
        XCTAssertEqual(sets, 3)
        XCTAssertNil(reps)
        XCTAssertNil(rir)
        XCTAssertNil(rest)
        XCTAssertNil(note)
    }

    // MARK: - remove action

    func testRemoveExercise() throws {
        let text = json("""
        { "action": "remove", "name": "Lat Pulldown" }
        """)
        let result = try parser.parse(text)
        XCTAssertEqual(result.count, 1)
        guard case .removeExercise(let name) = result[0] else {
            return XCTFail("Expected .removeExercise")
        }
        XCTAssertEqual(name, "Lat Pulldown")
    }

    func testRemoveMissingNameThrows() {
        let text = json("""
        { "action": "remove" }
        """)
        XCTAssertThrowsError(try parser.parse(text))
    }

    // MARK: - modify action

    func testModifyExerciseAllFields() throws {
        let text = json("""
        {
          "action": "modify",
          "name": "Bench Press",
          "new_target_sets": 5,
          "new_target_reps": "5",
          "new_target_rir": "1",
          "new_rest": 120,
          "note": "Go heavier"
        }
        """)
        let result = try parser.parse(text)
        XCTAssertEqual(result.count, 1)
        guard case .modifyExercise(let name, let sets, let reps, let rir, let rest, let note) = result[0] else {
            return XCTFail("Expected .modifyExercise")
        }
        XCTAssertEqual(name, "Bench Press")
        XCTAssertEqual(sets, 5)
        XCTAssertEqual(reps, "5")
        XCTAssertEqual(rir, "1")
        XCTAssertEqual(rest, 120)
        XCTAssertEqual(note, "Go heavier")
    }

    func testModifyExerciseNameOnly() throws {
        let text = json("""
        { "action": "modify", "name": "Deadlift" }
        """)
        let result = try parser.parse(text)
        XCTAssertEqual(result.count, 1)
        guard case .modifyExercise(let name, let sets, let reps, let rir, let rest, let note) = result[0] else {
            return XCTFail("Expected .modifyExercise")
        }
        XCTAssertEqual(name, "Deadlift")
        XCTAssertNil(sets)
        XCTAssertNil(reps)
        XCTAssertNil(rir)
        XCTAssertNil(rest)
        XCTAssertNil(note)
    }

    // MARK: - replace action

    func testReplaceExerciseAllFields() throws {
        let text = json("""
        {
          "action": "replace",
          "old_name": "Bench Press",
          "new_name": "Incline DB Press",
          "muscle_group": "Chest",
          "target_sets": 4,
          "target_reps": "8-10",
          "target_rir": "2",
          "rest_seconds": 90,
          "note": "Variation"
        }
        """)
        let result = try parser.parse(text)
        XCTAssertEqual(result.count, 1)
        guard case .replaceExercise(let oldName, let newName, let muscleGroup, let sets, let reps, let rir, let rest, let note) = result[0] else {
            return XCTFail("Expected .replaceExercise")
        }
        XCTAssertEqual(oldName, "Bench Press")
        XCTAssertEqual(newName, "Incline DB Press")
        XCTAssertEqual(muscleGroup, "Chest")
        XCTAssertEqual(sets, 4)
        XCTAssertEqual(reps, "8-10")
        XCTAssertEqual(rir, "2")
        XCTAssertEqual(rest, 90)
        XCTAssertEqual(note, "Variation")
    }

    func testReplaceMissingOldNameThrows() {
        let text = json("""
        { "action": "replace", "new_name": "Incline DB Press", "muscle_group": "Chest", "target_sets": 3 }
        """)
        XCTAssertThrowsError(try parser.parse(text))
    }

    // MARK: - Multiple modifications

    func testMultipleModificationsInOrder() throws {
        let text = """
        I suggest the following changes.
        ```json
        {
          "modifications": [
            { "action": "add", "name": "Push-up", "muscle_group": "Chest", "target_sets": 3 },
            { "action": "remove", "name": "Lat Pulldown" }
          ]
        }
        ```
        """
        let result = try parser.parse(text)
        XCTAssertEqual(result.count, 2)
        guard case .addExercise(let addName, _, _, _, _, _, _) = result[0] else {
            return XCTFail("Expected first result to be .addExercise")
        }
        guard case .removeExercise(let removeName) = result[1] else {
            return XCTFail("Expected second result to be .removeExercise")
        }
        XCTAssertEqual(addName, "Push-up")
        XCTAssertEqual(removeName, "Lat Pulldown")
    }

    // MARK: - JSON block stripping

    func testStrippingRemovesJSONBlock() {
        let text = """
        Here is my advice about your workout.

        ```json
        {
          "modifications": [
            { "action": "remove", "name": "Lat Pulldown" }
          ]
        }
        ```
        """
        let stripped = parser.strippingJSONBlock(from: text)
        XCTAssertFalse(stripped.contains("```"))
        XCTAssertFalse(stripped.contains("modifications"))
        XCTAssertTrue(stripped.contains("Here is my advice about your workout."))
    }

    /// Regression for issue #13: AI responses delimited with \r\n must still
    /// parse. Trimming with .whitespaces alone leaves the trailing \r on the
    /// fence line, so the ```json fence never matches and every modification
    /// is silently dropped.
    func testParsesResponseWithCRLFLineEndings() throws {
        let text = "Swap that out.\r\n\r\n```json\r\n{\r\n  \"modifications\": [\r\n    { \"action\": \"remove\", \"name\": \"Lat Pulldown\" }\r\n  ]\r\n}\r\n```"
        let mods = try parser.parse(text)
        XCTAssertEqual(mods.count, 1)
        guard case .removeExercise(let name) = mods[0] else {
            return XCTFail("Expected removeExercise, got \(mods[0])")
        }
        XCTAssertEqual(name, "Lat Pulldown")
    }

    /// Companion to the above: the block must also be stripped from display
    /// text on \r\n responses, or the user sees raw JSON in the chat bubble.
    func testStrippingRemovesJSONBlockWithCRLFLineEndings() {
        let text = "Swap that out.\r\n\r\n```json\r\n{ \"modifications\": [] }\r\n```"
        let stripped = parser.strippingJSONBlock(from: text)
        XCTAssertFalse(stripped.contains("```"))
        XCTAssertFalse(stripped.contains("modifications"))
        XCTAssertTrue(stripped.contains("Swap that out."))
    }

    func testStrippingWithNoBlockLeavesTextUnchanged() {
        let text = "Just some advice with no modifications."
        let stripped = parser.strippingJSONBlock(from: text)
        XCTAssertEqual(stripped, text)
    }

    func testStrippingTrimsTrailingWhitespace() {
        let text = "Advice here.\n\n```json\n{\"modifications\":[]}\n```\n\n"
        let stripped = parser.strippingJSONBlock(from: text)
        XCTAssertEqual(stripped, "Advice here.")
    }

    // MARK: - Bare (unfenced) JSON

    /// The failure seen in TestFlight: asking to change weights mid-session got
    /// answered with an unfenced workout plan object, which reached the bubble.
    func testStrippingRemovesBareWorkoutPlanJSON() {
        let text = """
        Here's the updated session.
        {"exercises":[{"name":"Face Pulls","muscle_group":"Rear Delts","sets":3,\
        "target_weight":null,"reps":null,"rir":null,"rest_seconds":null,\
        "coach_note":null}],"coaching_notes":"Need your previous numbers."}
        """
        let stripped = parser.strippingJSONBlock(from: text)
        XCTAssertEqual(stripped, "Here's the updated session.")
    }

    func testStrippingRemovesBareJSONWithNoSurroundingProse() {
        let text = "{\"exercises\":[],\"coaching_notes\":\"x\"}"
        XCTAssertEqual(parser.strippingJSONBlock(from: text), "")
    }

    func testStrippingRemovesTruncatedBareJSON() {
        let text = "Updated plan:\n{\"exercises\": [{\"name\": \"Face Pulls\", \"sets\": 3"
        XCTAssertEqual(parser.strippingJSONBlock(from: text), "Updated plan:")
    }

    func testStrippingKeepsBracesThatAreNotJSON() {
        let text = "Use a {1,2} rep bracket and keep RIR at 2."
        XCTAssertEqual(parser.strippingJSONBlock(from: text), text)
    }

    func testStrippingKeepsProseAfterBareJSON() {
        let text = "Before. {\"a\":1} After."
        XCTAssertEqual(parser.strippingJSONBlock(from: text), "Before.  After.")
    }

    // MARK: - Fence tolerance

    func testAcceptsBackticksWithoutLanguageTag() throws {
        let text = """
        Advice.
        ```
        {
          "modifications": [
            { "action": "remove", "name": "Cable Row" }
          ]
        }
        ```
        """
        let result = try parser.parse(text)
        XCTAssertEqual(result.count, 1)
    }

    func testActionIsCaseInsensitive() throws {
        let text = json("""
        { "action": "ADD", "name": "Pull-up", "muscle_group": "Back", "target_sets": 3 }
        """)
        let result = try parser.parse(text)
        XCTAssertEqual(result.count, 1)
        guard case .addExercise = result[0] else {
            return XCTFail("Expected .addExercise")
        }
    }

    // MARK: - Fallback to pipe parser still works

    func testPipeParserFallbackAddExercise() {
        let pipeParser = WorkoutModificationParser()
        let line = "[ADD] Bench Press | Chest | 4 | 8-10 | 2 | 90 | Note here"
        let result = pipeParser.parse(line)
        XCTAssertEqual(result.count, 1)
        guard case .addExercise(let name, let muscleGroup, let sets, let reps, let rir, let rest, let note) = result[0] else {
            return XCTFail("Expected .addExercise from pipe parser")
        }
        XCTAssertEqual(name, "Bench Press")
        XCTAssertEqual(muscleGroup, "Chest")
        XCTAssertEqual(sets, 4)
        XCTAssertEqual(reps, "8-10")
        XCTAssertEqual(rir, "2")
        XCTAssertEqual(rest, 90)
        XCTAssertEqual(note, "Note here")
    }

    func testPipeParserFallbackRemoveExercise() {
        let pipeParser = WorkoutModificationParser()
        let result = pipeParser.parse("[REMOVE] Lat Pulldown")
        XCTAssertEqual(result.count, 1)
        guard case .removeExercise(let name) = result[0] else {
            return XCTFail("Expected .removeExercise from pipe parser")
        }
        XCTAssertEqual(name, "Lat Pulldown")
    }

    func testPipeParserFallbackModifyExercise() {
        let pipeParser = WorkoutModificationParser()
        let result = pipeParser.parse("[MODIFY] Squat | 5 | 5 | 1 | 120 | Heavier")
        XCTAssertEqual(result.count, 1)
        guard case .modifyExercise(let name, let sets, _, _, _, _) = result[0] else {
            return XCTFail("Expected .modifyExercise from pipe parser")
        }
        XCTAssertEqual(name, "Squat")
        XCTAssertEqual(sets, 5)
    }

    func testPipeParserFallbackReplaceExercise() {
        let pipeParser = WorkoutModificationParser()
        let result = pipeParser.parse("[REPLACE] Bench Press → Incline DB Press | Chest | 4")
        XCTAssertEqual(result.count, 1)
        guard case .replaceExercise(let oldName, let newName, _, _, _, _, _, _) = result[0] else {
            return XCTFail("Expected .replaceExercise from pipe parser")
        }
        XCTAssertEqual(oldName, "Bench Press")
        XCTAssertEqual(newName, "Incline DB Press")
    }
}
