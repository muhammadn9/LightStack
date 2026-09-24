import XCTest
@testable import Lightstack

final class WorkoutModificationParserTests: XCTestCase {

    private let parser = WorkoutModificationParser()

    // MARK: - Empty input

    func testParseEmptyInputReturnsEmptyArray() {
        XCTAssertTrue(parser.parse("").isEmpty)
    }

    // MARK: - [ADD]

    func testParseAddWithAllFieldsReturnsCorrectModification() {
        let line = "[ADD] Bench Press | Chest | 4 | 8-10 | 2 | 90 | Note here"
        let result = parser.parse(line)
        XCTAssertEqual(result.count, 1)
        guard case .addExercise(let name, let muscleGroup, let sets, let reps, let rir, let rest, _, let note) = result[0] else {
            return XCTFail("Expected .addExercise")
        }
        XCTAssertEqual(name, "Bench Press")
        XCTAssertEqual(muscleGroup, "Chest")
        XCTAssertEqual(sets, 4)
        XCTAssertEqual(reps, "8-10")
        XCTAssertEqual(rir, "2")
        XCTAssertEqual(rest, 90)
        XCTAssertEqual(note, "Note here")
    }

    func testParseAddWithOnlyRequiredFieldsReturnsNilOptionals() {
        let line = "[ADD] Squat | Legs | 3"
        let result = parser.parse(line)
        XCTAssertEqual(result.count, 1)
        guard case .addExercise(let name, let muscleGroup, let sets, let reps, let rir, let rest, _, let note) = result[0] else {
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

    func testParseAddWithTooFewPartsReturnsEmpty() {
        let line = "[ADD] BadLine"
        XCTAssertTrue(parser.parse(line).isEmpty)
    }

    // MARK: - [REMOVE]

    func testParseRemoveReturnsCorrectModification() {
        let line = "[REMOVE] Bench Press"
        let result = parser.parse(line)
        XCTAssertEqual(result.count, 1)
        guard case .removeExercise(let name) = result[0] else {
            return XCTFail("Expected .removeExercise")
        }
        XCTAssertEqual(name, "Bench Press")
    }

    func testParseRemoveWithEmptyNameReturnsEmpty() {
        let line = "[REMOVE]"
        XCTAssertTrue(parser.parse(line).isEmpty)
    }

    // MARK: - [MODIFY]

    func testParseModifyWithAllFieldsReturnsCorrectModification() {
        let line = "[MODIFY] Bench Press | 5 | 5 | 1 | 120 | Heavier"
        let result = parser.parse(line)
        XCTAssertEqual(result.count, 1)
        guard case .modifyExercise(let name, let sets, let reps, let rir, let rest, _, let note) = result[0] else {
            return XCTFail("Expected .modifyExercise")
        }
        XCTAssertEqual(name, "Bench Press")
        XCTAssertEqual(sets, 5)
        XCTAssertEqual(reps, "5")
        XCTAssertEqual(rir, "1")
        XCTAssertEqual(rest, 120)
        XCTAssertEqual(note, "Heavier")
    }

    func testParseModifyWithNameOnlyReturnsAllOptionalsNil() {
        let line = "[MODIFY] Bench Press"
        let result = parser.parse(line)
        XCTAssertEqual(result.count, 1)
        guard case .modifyExercise(let name, let sets, let reps, let rir, let rest, _, let note) = result[0] else {
            return XCTFail("Expected .modifyExercise")
        }
        XCTAssertEqual(name, "Bench Press")
        XCTAssertNil(sets)
        XCTAssertNil(reps)
        XCTAssertNil(rir)
        XCTAssertNil(rest)
        XCTAssertNil(note)
    }

    // MARK: - [REPLACE]

    func testParseReplaceWithUnicodeArrowReturnsCorrectModification() {
        let line = "[REPLACE] Bench Press → Incline DB Press | Chest | 4 | 8-10 | 2 | 90 | Variation"
        let result = parser.parse(line)
        XCTAssertEqual(result.count, 1)
        guard case .replaceExercise(let oldName, let newName, let muscleGroup, let sets, let reps, let rir, let rest, _, let note) = result[0] else {
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

    func testParseReplaceWithASCIIArrowRegressionReturnsCorrectModification() {
        // Regression: ASCII "->" was previously not normalised, causing silent failure
        let line = "[REPLACE] Bench Press -> Incline DB Press | Chest | 4"
        let result = parser.parse(line)
        XCTAssertEqual(result.count, 1, "ASCII -> must be treated identically to Unicode →")
        guard case .replaceExercise(let oldName, let newName, _, _, _, _, _, _, _) = result[0] else {
            return XCTFail("Expected .replaceExercise")
        }
        XCTAssertEqual(oldName, "Bench Press")
        XCTAssertEqual(newName, "Incline DB Press")
    }

    func testParseReplaceWithNoArrowReturnsEmpty() {
        let line = "[REPLACE] OnlyOneName | Chest | 4"
        XCTAssertTrue(parser.parse(line).isEmpty)
    }

    // MARK: - Multi-line

    func testParseMultiLineReturnsBothModificationsInOrder() {
        let text = "[ADD] Push-up | Chest | 3\n[REMOVE] Lat Pulldown"
        let result = parser.parse(text)
        XCTAssertEqual(result.count, 2)
        guard case .addExercise(let addName, _, _, _, _, _, _, _) = result[0] else {
            return XCTFail("Expected first result to be .addExercise")
        }
        guard case .removeExercise(let removeName) = result[1] else {
            return XCTFail("Expected second result to be .removeExercise")
        }
        XCTAssertEqual(addName, "Push-up")
        XCTAssertEqual(removeName, "Lat Pulldown")
    }
}
