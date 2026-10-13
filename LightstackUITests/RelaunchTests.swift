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

    /// Logged sets must still show as logged after a relaunch, with no extra target-filled rows.
    func testLoggedSetSurvivesRelaunch() throws {
        launchApp()
        generateAndStartPushWorkout()
        waitFor(app.staticTexts["1 of 3"])

        func rowCount() -> Int {
            let pending = app.textFields.matching(
                NSPredicate(format: "identifier BEGINSWITH 'setRow.0.' AND identifier ENDSWITH '.weight'")).count
            let logged = app.staticTexts.matching(
                NSPredicate(format: "identifier BEGINSWITH 'loggedSet.0.' AND identifier ENDSWITH '.weight'")).count
            return pending + logged
        }

        replaceText(in: weightField(), with: "95")
        replaceText(in: repsField(), with: "6")
        dismissKeyboardIfNeeded()
        let totalBefore = rowCount()
        tap(app.buttons["setRow.0.0.log"])
        waitFor(app.staticTexts["loggedSet.0.0.weight"], "Set was not logged")
        XCTAssertEqual(rowCount(), totalBefore)

        // The next pending row is now index 0; type into it without logging.
        replaceText(in: weightField(), with: "90")
        replaceText(in: repsField(), with: "7")
        dismissKeyboardIfNeeded()

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.terminate()

        app.launchArguments = ["-uiTesting"]
        app.launch()

        let logged = waitFor(app.staticTexts["loggedSet.0.0.weight"], "Logged set lost after relaunch")
        XCTAssertEqual(logged.label, "95.0")
        XCTAssertEqual(app.staticTexts["loggedSet.0.0.reps"].label, "×6")
        XCTAssertEqual(weightField().value as? String, "90")
        XCTAssertEqual(repsField().value as? String, "7")
        XCTAssertEqual(rowCount(), totalBefore, "Extra target-filled row appeared after relaunch")
        shot("03-logged-after-relaunch")
    }
}
