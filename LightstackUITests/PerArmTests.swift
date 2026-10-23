import XCTest

final class PerArmUITests: LightstackUITestCase {

    /// Marks the first exercise "Per arm" from its menu, logs a set and sees "/ arm" on the row.
    func testPerArmToggleLabelsLoggedRow() throws {
        launchApp()
        generateAndStartPushWorkout()

        for _ in 0..<3 where !app.buttons["perArmToggle.0"].exists {
            tap(app.buttons["moreActionsButton"])
            _ = app.buttons["perArmToggle.0"].waitForExistence(timeout: 8)
        }
        tap(waitFor(app.buttons["perArmToggle.0"], "Per arm menu item missing"))
        shot("01-per-arm-on")

        replaceText(in: weightField(), with: "25")
        replaceText(in: repsField(), with: "10")
        replaceText(in: rirField(), with: "2")
        dismissKeyboardIfNeeded()
        tap(app.buttons["setRow.0.0.log"])
        let unit = waitFor(app.staticTexts["loggedSet.0.0.unit"], "Logged row has no unit label")
        XCTAssertTrue(unit.label.contains("/ arm"), "Unit label was \(unit.label)")
        shot("02-logged-per-arm")
    }
}
