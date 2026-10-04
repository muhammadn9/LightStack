import XCTest

final class SupersetTests: LightstackUITestCase {

    func testLinkAndUnlinkSuperset() throws {
        launchApp()
        generateAndStartPushWorkout()
        waitFor(app.staticTexts["1 of 3"])
        XCTAssertFalse(app.staticTexts["Round 1"].exists)

        tap(app.buttons["supersetWithNextButton"])
        waitFor(app.staticTexts["1 of 2"], "Linking did not merge the two exercises onto one page")
        waitFor(app.staticTexts["Round 1"], "Superset page has no round rows")
        XCTAssertTrue(app.staticTexts["Barbell Bench Press"].exists)
        XCTAssertTrue(app.staticTexts["Incline Dumbbell Press"].exists)
        XCTAssertTrue(app.textFields["setRow.0.0.weight"].exists)
        XCTAssertTrue(app.textFields["setRow.1.0.weight"].exists)
        shot("01-superset")

        tap(app.buttons["unlinkButton"])
        waitFor(app.staticTexts["1 of 3"], "Unlinking did not separate the exercises")
        XCTAssertFalse(app.staticTexts["Round 1"].exists)
        XCTAssertFalse(app.staticTexts["Incline Dumbbell Press"].exists)
        shot("02-unlinked")
    }
}
