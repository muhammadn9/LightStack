import XCTest

/// Owner bug: Settings > Default Rest Timer changed mid-workout was ignored for exercises added in the workout.
final class RestTimerDefaultTests: LightstackUITestCase {

    // MARK: Helpers

    /// Active Push workout -> "+" -> custom exercise. Lands on the new exercise's page (index 1).
    private func addCustomExercise(_ name: String) {
        tap(app.buttons["addExerciseButton"])
        let custom = app.buttons["addCustomExerciseButton"]
        waitFor(custom)
        for _ in 0..<3 where !app.textFields["customExerciseNameField"].exists {
            tap(custom)
            if app.textFields["customExerciseNameField"].waitForExistence(timeout: 8) { break }
        }
        type(name, into: app.textFields["customExerciseNameField"])
        tap(app.buttons["customExerciseAddButton"])
        waitFor(app.textFields["setRow.1.0.weight"], "New exercise page did not appear")
    }

    /// Settings > Default Rest Timer -> `option`, then back to the Today tab.
    private func setDefaultRest(_ option: String) {
        openSettings()
        let picker = scrollUntilHittable(app.descendants(matching: .any)["settings.defaultRestPicker"].firstMatch)
        tap(picker)
        tap(app.buttons[option])
        openTab("Today")
        waitFor(app.buttons["startRestButton"], "Active workout missing after returning from Settings")
    }

    /// True when the countdown on screen starts at `minutes`:00 (a second or two of slack).
    private func countdownStarts(at minutes: Int) -> Bool {
        let predicate = NSPredicate(format: "label BEGINSWITH '\(minutes):00' OR label BEGINSWITH '\(minutes - 1):5'")
        return app.staticTexts.matching(predicate).firstMatch.waitForExistence(timeout: 8)
    }

    private func endRest() {
        tap(app.buttons["endRestButton"])
        XCTAssertTrue(app.staticTexts["Rest Period"].waitForNonExistence(timeout: 5))
    }

    // MARK: Tests

    /// Owner's steps: add an exercise mid-workout, change the default in Settings, come back, start the timer.
    func testChangingDefaultAfterAddingAnExerciseAppliesToTheTimerButton() throws {
        launchApp()
        generateAndStartPushWorkout()
        addCustomExercise("Rest Probe")
        setDefaultRest("5 min")
        shot("rest-default-after-change")
        tap(app.buttons["startRestButton"])
        waitFor(app.staticTexts["Rest Period"], "Rest countdown did not appear")
        XCTAssertTrue(countdownStarts(at: 5), "Countdown should start at the new 5:00 default")
    }

    func testChangingDefaultAfterAddingAnExerciseAppliesWhenLoggingASet() throws {
        launchApp()
        generateAndStartPushWorkout()
        addCustomExercise("Rest Probe")
        setDefaultRest("5 min")
        replaceText(in: weightField(exercise: 1), with: "50")
        replaceText(in: repsField(exercise: 1), with: "10")
        dismissKeyboardIfNeeded()
        tap(app.buttons["setRow.1.0.log"])
        waitFor(app.staticTexts["Rest Period"], "Logging a set did not start the rest timer")
        XCTAssertTrue(countdownStarts(at: 5), "Countdown after logging should start at the new 5:00 default")
    }

    func testDefaultChangedBeforeAddingAnExerciseApplies() throws {
        launchApp()
        generateAndStartPushWorkout()
        setDefaultRest("5 min")
        addCustomExercise("Rest Probe")
        tap(app.buttons["startRestButton"])
        waitFor(app.staticTexts["Rest Period"], "Rest countdown did not appear")
        XCTAssertTrue(countdownStarts(at: 5), "Countdown should start at the 5:00 default set before adding")
    }
}
