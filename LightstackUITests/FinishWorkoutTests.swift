import XCTest

final class FinishWorkoutTests: LightstackUITestCase {

    /// Log one set, leave another typed but unlogged -> Finish -> only the logged set is saved.
    func testFinishSavesOnlyLoggedSets() throws {
        launchApp()
        shot("01-setup")
        generateAndStartPushWorkout()
        shot("02-active-workout")

        replaceText(in: weightField(), with: "100")
        replaceText(in: repsField(), with: "5")
        replaceText(in: rirField(), with: "2")
        dismissKeyboardIfNeeded()
        tap(app.buttons["setRow.0.0.log"])
        waitFor(app.staticTexts["loggedSet.0.0.weight"], "Set was not logged")

        // Typed but never logged: second exercise (next page).
        app.swipeLeft()
        replaceText(in: weightField(exercise: 1), with: "50")
        replaceText(in: repsField(exercise: 1), with: "10")
        dismissKeyboardIfNeeded()
        shot("03-typed-unlogged-row")

        tap(app.buttons["finishWorkoutButton"])
        let alert = app.alerts["Finish workout?"]
        waitFor(alert, "Confirmation alert did not appear")
        let messages = alert.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(messages.contains { $0.hasPrefix("1 set logged across 1 exercise.") && $0.contains("Unlogged sets won't be saved.") },
                      "Unexpected alert message: \(messages)")
        shot("04-finish-confirm-alert")
        tap(alert.buttons["confirmFinishWorkoutButton"].firstMatch)

        let save = waitFor(app.buttons["saveWorkoutButton"], "Post-workout screen did not appear")
        shot("05-post-workout")
        XCTAssertTrue(save.waitForHittable(timeout: timeout), "Save never became enabled")
        let chip = app.buttons["chip.Push"]
        for _ in 0..<3 where !chip.exists {
            if save.exists && save.isHittable { save.tap() }
            if chip.waitForExistence(timeout: 10) { break }
        }
        waitFor(chip, "Did not return to setup after saving")
        openTab("History")
        let rows = app.buttons.matching(identifier: "historyRow.Push")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: timeout))
        rows.element(boundBy: 0).tap()
        waitFor(app.staticTexts["Barbell Bench Press"], "Detail did not list the logged exercise")
        waitFor(app.staticTexts["100.0"], "Detail did not show the logged weight")
        XCTAssertFalse(app.staticTexts["Incline Dumbbell Press"].exists, "Unworked exercise must not appear")
        XCTAssertFalse(app.staticTexts["Cable Triceps Pushdown"].exists, "Unworked exercise must not appear")
        shot("06-history-detail")
    }

    /// Nothing logged -> alert offers Discard, and the workout never reaches History.
    func testFinishWithNothingLoggedOffersDiscard() throws {
        launchApp()
        generateAndStartPushWorkout()
        replaceText(in: weightField(), with: "100")
        replaceText(in: repsField(), with: "5")
        dismissKeyboardIfNeeded()

        tap(app.buttons["finishWorkoutButton"])
        let alert = app.alerts["Finish workout?"]
        waitFor(alert, "Confirmation alert did not appear")
        let messages = alert.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(messages.contains("You haven't logged any sets. This workout won't be saved."),
                      "Unexpected alert message: \(messages)")
        XCTAssertFalse(alert.buttons["confirmFinishWorkoutButton"].exists)
        shot("01-nothing-logged-alert")
        tap(alert.buttons["discardFromFinishButton"].firstMatch)

        waitFor(app.buttons["chip.Push"], "Did not return to setup after discarding")
        openTab("History")
        let rows = app.buttons.matching(identifier: "historyRow.Push")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: timeout))
        XCTAssertEqual(rows.count, 1, "Only the seeded Push workout should exist")
        shot("02-history")
    }

    /// Finish asks first; Keep Training changes nothing; Finish then proceeds.
    func testFinishConfirmationKeepTrainingThenFinish() throws {
        launchApp()
        generateAndStartPushWorkout()
        replaceText(in: weightField(), with: "100")
        replaceText(in: repsField(), with: "5")
        replaceText(in: rirField(), with: "2")
        dismissKeyboardIfNeeded()
        tap(app.buttons["setRow.0.0.log"])
        waitFor(app.staticTexts["loggedSet.0.0.weight"], "Set was not logged")
        replaceText(in: weightField(), with: "90")
        dismissKeyboardIfNeeded()

        tap(app.buttons["finishWorkoutButton"])
        let alert = app.alerts["Finish workout?"]
        waitFor(alert, "Confirmation alert did not appear")
        shot("01-finish-confirm-alert")
        let messages = alert.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(messages.contains { $0.hasPrefix("1 set logged across 1 exercise.") },
                      "Unexpected alert message: \(messages)")

        tap(alert.buttons["keepTrainingButton"].firstMatch)
        XCTAssertTrue(alert.waitForNonExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["loggedSet.0.0.weight"].exists)
        XCTAssertTrue(app.buttons["finishWorkoutButton"].exists, "Should still be on the active workout")
        XCTAssertFalse(app.buttons["saveWorkoutButton"].exists)
        XCTAssertEqual(weightField().value as? String, "90")
        XCTAssertTrue(app.buttons["Pause workout"].exists, "Timer should still be running")
        shot("02-after-keep-training")

        finishWorkoutConfirmed()
        waitFor(app.buttons["saveWorkoutButton"], "Post-workout screen did not appear")
        shot("03-post-workout")
    }
}

extension XCUIElement {
    /// Waits until the element exists, is hittable and enabled.
    func waitForHittable(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND hittable == true AND enabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
