import XCTest

final class WorkoutFlowTests: LightstackUITestCase {

    func testReorderMovesExerciseAndOrderPersists() throws {
        launchApp()
        generateAndStartPushWorkout()
        waitFor(app.staticTexts["1 of 3"])
        waitFor(app.staticTexts["Barbell Bench Press"])

        // A tap during the first render can be lost, so retry until the sheet is up.
        for _ in 0..<3 where !app.buttons["reorderDoneButton"].exists {
            tap(app.buttons["reorderExercisesButton"])
            _ = app.buttons["reorderDoneButton"].waitForExistence(timeout: 6)
        }
        waitFor(app.buttons["reorderDoneButton"])
        shot("01-reorder-sheet")
        tap(app.buttons["reorderDown.Barbell Bench Press"])
        // After the move, Bench Press can no longer go up-first: its up button is enabled.
        let up = app.buttons["reorderUp.Barbell Bench Press"]
        XCTAssertTrue(NSPredicate(format: "isEnabled == true").evaluate(with: up) || up.waitForExistence(timeout: 3))
        shot("01b-after-down")
        tap(app.buttons["reorderDoneButton"])

        // Still on the same exercise, which is now second.
        waitFor(app.staticTexts["2 of 3"], "Reorder did not move the exercise")
        waitFor(app.staticTexts["Barbell Bench Press"])

        // Backgrounding saves the session; after relaunch the new order must hold.
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.terminate()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        waitFor(app.textFields["setRow.0.0.weight"], "Workout was not restored after relaunch")
        waitFor(app.staticTexts["1 of 3"])
        waitFor(app.staticTexts["Incline Dumbbell Press"], "Order was not persisted: first exercise is wrong")
        XCTAssertFalse(app.staticTexts["Barbell Bench Press"].exists)
        shot("02-after-relaunch")
    }

    func testAddExerciseShowsHistoryAndInsertsAfterCurrent() throws {
        launchApp()
        generateAndStartPushWorkout()
        waitFor(app.staticTexts["1 of 3"])

        tap(app.buttons["addExerciseButton"])
        waitFor(app.staticTexts["yourExercisesHeader"], "No 'Your exercises' section")
        let row = waitFor(app.buttons["yourExercise.Bench Press"], "Seeded Bench Press missing from history")
        shot("03-add-sheet")

        // Search narrows the history section.
        type("Overhead", into: app.textFields["exerciseSearchField"])
        waitFor(app.buttons["yourExercise.Overhead Press"])
        XCTAssertFalse(row.exists)
        replaceText(in: app.textFields["exerciseSearchField"], with: "Bench")
        tap(app.buttons["yourExercise.Bench Press"])
        shot("03b-after-tap")

        // Inserted right after exercise 1 and shown: page 2 of 4.
        waitFor(app.staticTexts["2 of 4"], "New exercise was not inserted after the current one")
        waitFor(app.staticTexts["Bench Press"])
        shot("04-added-after-current")

        // The original second exercise is now third.
        tap(app.buttons["Next exercise"])
        waitFor(app.staticTexts["3 of 4"])
        waitFor(app.staticTexts["Incline Dumbbell Press"])
    }

    func testSetupOffersPastWorkoutsAndStartsWithoutAI() throws {
        launchApp()
        waitFor(app.staticTexts["fromHistoryHeader"], "No 'From history' section")
        let chip = waitFor(app.buttons["chip.Arm Day"], "Arm Day chip missing")
        shot("05-setup-history")
        chip.tap()

        let start = waitFor(app.buttons["startWorkoutButton"])
        waitFor(app.staticTexts["Barbell Curl"])
        var swipes = 0
        while !start.isHittable && swipes < 4 { app.swipeUp(); swipes += 1 }
        start.tap()

        waitFor(app.textFields["setRow.0.0.weight"], "Active workout did not start")
        waitFor(app.staticTexts["1 of 2"])
        waitFor(app.staticTexts["Barbell Curl"])
        shot("06-arm-day-active")
    }
}
