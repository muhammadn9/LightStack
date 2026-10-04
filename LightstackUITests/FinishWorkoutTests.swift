import XCTest

final class FinishWorkoutTests: LightstackUITestCase {

    /// Generate -> start -> type one row without logging it -> Finish -> save -> History has the set.
    func testFinishWithTypedUnloggedSet() throws {
        launchApp()
        shot("01-setup")
        generateAndStartPushWorkout()
        shot("02-active-workout")

        // Fields come prefilled from the plan's targets, so replace rather than append.
        replaceText(in: weightField(), with: "100")
        replaceText(in: repsField(), with: "5")
        replaceText(in: rirField(), with: "2")
        dismissKeyboardIfNeeded()
        shot("03-typed-unlogged-row")

        tap(app.buttons["finishWorkoutButton"])
        let save = waitFor(app.buttons["saveWorkoutButton"], "Post-workout screen did not appear")
        shot("04-post-workout")
        XCTAssertTrue(app.staticTexts["Session Complete"].exists)

        // Save becomes tappable once the (fake) progression note has loaded.
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
        XCTAssertEqual(rows.count, 2, "Expected the seeded Push workout plus the new one")
        shot("05-history")

        // Newest first: the workout just finished.
        rows.element(boundBy: 0).tap()
        waitFor(app.staticTexts["Barbell Bench Press"], "Detail did not list the exercise")
        waitFor(app.staticTexts["100.0"], "Detail did not show the typed weight")
        shot("06-history-detail")
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
