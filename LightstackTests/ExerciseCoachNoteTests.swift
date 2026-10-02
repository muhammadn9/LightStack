import XCTest
@testable import Lightstack

final class ExerciseCoachNoteTests: XCTestCase {

    func testTargetPrefixWithMessage() {
        let parts = Exercise.splitCoachNote("Target: 155 lbs — You crushed 150 lbs for 8 last time.")
        XCTAssertEqual(parts.weight, "155 lbs")
        XCTAssertEqual(parts.message, "You crushed 150 lbs for 8 last time.")
    }

    func testBareWeightWithMessage() {
        let parts = Exercise.splitCoachNote("155 lbs — Focus on a controlled eccentric.")
        XCTAssertEqual(parts.weight, "155 lbs")
        XCTAssertEqual(parts.message, "Focus on a controlled eccentric.")
    }

    func testMiddleDotSeparator() {
        let parts = Exercise.splitCoachNote("Target: 40 lbs · Slow negatives")
        XCTAssertEqual(parts.weight, "40 lbs")
        XCTAssertEqual(parts.message, "Slow negatives")
    }

    func testMessageKeepsItsOwnDashes() {
        let parts = Exercise.splitCoachNote("Target: 100 lbs — Go heavy — but stay safe")
        XCTAssertEqual(parts.weight, "100 lbs")
        XCTAssertEqual(parts.message, "Go heavy — but stay safe")
    }

    func testWeightOnly() {
        let parts = Exercise.splitCoachNote("Target: BW")
        XCTAssertEqual(parts.weight, "BW")
        XCTAssertNil(parts.message)
    }

    func testMessageOnly() {
        let parts = Exercise.splitCoachNote("Keep your elbows tucked — protect the shoulder")
        XCTAssertNil(parts.weight)
        XCTAssertEqual(parts.message, "Keep your elbows tucked — protect the shoulder")
    }

    func testNil() {
        let parts = Exercise.splitCoachNote(nil)
        XCTAssertNil(parts.weight)
        XCTAssertNil(parts.message)
    }
}
