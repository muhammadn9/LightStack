import XCTest

/// The workout clock and rest countdown must keep running while the user visits the nutrition side.
final class WorkoutTimerSideSwitchTests: LightstackUITestCase {

    private func elapsedSeconds() -> Int {
        let label = app.staticTexts["workout.elapsed"].label
        let parts = label.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return -1 }
        return parts[0] * 60 + parts[1]
    }

    /// Today -> Log Manually -> custom exercise -> Start.
    private func startManualWorkout() {
        let manual = waitFor(app.buttons["logManuallyButton"])
        let add = app.buttons["Add Exercise"]
        for _ in 0..<3 where !add.exists {
            manual.tap()
            if add.waitForExistence(timeout: 10) { break }
        }
        let custom = app.buttons["addCustomExerciseButton"]
        for _ in 0..<3 where !custom.exists {
            add.tap()
            if custom.waitForExistence(timeout: 10) { break }
        }
        tap(custom)
        type("Timer Curl", into: app.textFields["customExerciseNameField"])
        tap(app.buttons["customExerciseAddButton"])
        type("Arms", into: app.textFields["manualWorkoutTypeField"])
        let start = app.buttons["Start"]
        waitFor(start)
        tap(start)
        waitFor(app.staticTexts["workout.elapsed"], "Manual workout did not start")
    }

    private func switchSide() {
        tap(app.buttons["side.switch"].firstMatch)
    }

    /// Starts a manual workout, leaves Today for the Profile tab, hops to the nutrition side and back,
    /// then returns to Today. The clock must include the time spent away.
    func testManualWorkoutClockSurvivesSideSwitch() throws {
        launchApp()
        startManualWorkout()
        sleep(5)
        let before = elapsedSeconds()
        XCTAssertGreaterThanOrEqual(before, 4, "Clock should be running before the switch")

        openTab("Profile")
        switchSide()
        waitFor(app.descendants(matching: .any)["journal.ring.calories"].firstMatch, "Nutrition side did not appear")
        sleep(3)
        switchSide()
        waitFor(app.staticTexts["profile.stat.totalWorkouts"], "Did not return to the gym side")
        openTab("Today")
        waitFor(app.staticTexts["workout.elapsed"], "Active workout missing after returning to Today")
        let after = elapsedSeconds()
        shot("after-switch")
        XCTAssertGreaterThanOrEqual(after, before + 3,
                                    "Clock reset or stalled while away: before=\(before)s after=\(after)s")
    }

    /// Manual workout, user sits on the nutrition side, iOS reclaims the app a while later.
    /// After relaunch the clock must include the time the app was gone.
    func testManualWorkoutClockSurvivesRelaunchFromNutritionSide() throws {
        launchApp()
        startManualWorkout()
        sleep(5)
        let before = elapsedSeconds()
        openTab("Profile")
        switchSide()
        waitFor(app.descendants(matching: .any)["journal.ring.calories"].firstMatch, "Nutrition side did not appear")

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.terminate()
        sleep(5)

        app.launchArguments = ["-uiTesting"]
        app.launch()
        waitFor(app.descendants(matching: .any)["journal.ring.calories"].firstMatch, "App did not reopen on the nutrition side")
        switchSide()
        openTab("Today")
        waitFor(app.staticTexts["workout.elapsed"], "Manual workout was not restored after relaunch")
        let after = elapsedSeconds()
        shot("after-relaunch")
        XCTAssertGreaterThanOrEqual(after, before + 5, "Clock lost time across relaunch: before=\(before)s after=\(after)s")
    }

    /// The session is saved the moment a workout starts, so even an app that dies without a
    /// chance to save (crash, jetsam while foregrounded) resumes with the clock still counting.
    func testManualWorkoutClockSurvivesAbruptKill() throws {
        launchApp()
        startManualWorkout()
        sleep(6)
        app.terminate()
        sleep(3)

        app.launchArguments = ["-uiTesting"]
        app.launch()
        waitFor(app.staticTexts["workout.elapsed"], "Manual workout was not restored after an abrupt kill")
        let after = elapsedSeconds()
        shot("after-kill")
        XCTAssertGreaterThanOrEqual(after, 8, "Clock restarted after an abrupt kill: after=\(after)s")
    }

    /// The rest countdown keeps its target date across a side switch.
    func testRestTimerSurvivesSideSwitch() throws {
        launchApp(extraArguments: ["-defaultRestSeconds", "180"])
        startManualWorkout()
        waitFor(app.buttons["startRestButton"]).tap()
        waitFor(app.staticTexts["Rest Period"], "Rest countdown did not appear")
        openTab("Profile")
        switchSide()
        waitFor(app.descendants(matching: .any)["journal.ring.calories"].firstMatch, "Nutrition side did not appear")
        sleep(8)
        switchSide()
        waitFor(app.staticTexts["profile.stat.totalWorkouts"], "Did not return to the gym side")
        openTab("Today")
        waitFor(app.staticTexts["Rest Period"], "Rest countdown vanished after the side switch")
        let low = NSPredicate(format: "label BEGINSWITH '2:5' OR label BEGINSWITH '2:4' OR label BEGINSWITH '2:3'")
        XCTAssertTrue(app.staticTexts.matching(low).firstMatch.waitForExistence(timeout: 5),
                      "Rest countdown restarted instead of continuing")
    }
}
