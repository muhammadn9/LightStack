import XCTest

final class RelaunchTests: LightstackUITestCase {

    /// Start a workout, type into a row, kill the app, relaunch: numbers survive, no duplicates.
    func testTypedRowSurvivesRelaunch() throws {
        launchApp()
        generateAndStartPushWorkout()
        waitFor(app.staticTexts["1 of 3"])

        replaceText(in: weightField(), with: "95")
        replaceText(in: repsField(), with: "6")
        dismissKeyboardIfNeeded()
        shot("01-before-kill")

        // Backgrounding saves the session, as it would before iOS reclaims the app.
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.terminate()

        app.launchArguments = ["-uiTesting"]
        app.launch()

        let weight = waitFor(weightField(), "Workout was not restored after relaunch")
        XCTAssertEqual(weight.value as? String, "95")
        XCTAssertEqual(repsField().value as? String, "6")
        XCTAssertTrue(app.staticTexts["1 of 3"].exists, "Exercises were duplicated or lost after relaunch")
        XCTAssertEqual(app.staticTexts.matching(identifier: "Barbell Bench Press").count, 1)
        shot("02-after-relaunch")
    }
}
