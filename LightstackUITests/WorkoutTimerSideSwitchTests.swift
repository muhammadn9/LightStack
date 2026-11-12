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
        let nameField = app.textFields["customExerciseNameField"]
        for _ in 0..<3 where !nameField.exists {
            tap(custom)
            if nameField.waitForExistence(timeout: 8) { break }
        }
        type("Timer Curl", into: nameField)
        tap(app.buttons["customExerciseAddButton"])
        let typeField = waitFor(app.textFields["manualWorkoutTypeField"])
        waitUntilHittable(typeField)
        type("Arms", into: typeField)
        let start = app.buttons["Start"]
        waitFor(start)
        for _ in 0..<3 where !app.staticTexts["workout.elapsed"].exists {
            if start.exists, start.isHittable { start.tap() }
            if app.staticTexts["workout.elapsed"].waitForExistence(timeout: 8) { break }
        }
        waitFor(app.staticTexts["workout.elapsed"], "Manual workout did not start")
    }

    /// One cycle per workout: the first match is the visible side's button (the hidden side's tree is not yet
    /// created on the first switch, and on the way back the nutrition button is the one that exists first).
    private func switchSide(toNutrition: Bool) {
        let label = toNutrition ? "Switch to nutrition" : "Switch to training"
        let predicate = NSPredicate(format: "identifier == 'side.switch' AND label == %@", label)
        // The hidden side's identical button stays in the tree; take the one that is hittable.
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let all = app.buttons.matching(predicate).allElementsBoundByIndex
            if let hit = all.first(where: { $0.exists && $0.isHittable }) {
                hit.tap()
                return
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTFail("No hittable '\(label)' button")
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
        switchSide(toNutrition: true)
        waitFor(app.descendants(matching: .any)["journal.ring.calories"].firstMatch, "Nutrition side did not appear")
        sleep(3)
        switchSide(toNutrition: false)
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
        switchSide(toNutrition: true)
        waitFor(app.descendants(matching: .any)["journal.ring.calories"].firstMatch, "Nutrition side did not appear")

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.terminate()
        sleep(5)

        app.launchArguments = ["-uiTesting"]
        app.launch()
        waitFor(app.descendants(matching: .any)["journal.ring.calories"].firstMatch, "App did not reopen on the nutrition side")
        switchSide(toNutrition: false)
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
        switchSide(toNutrition: true)
        waitFor(app.descendants(matching: .any)["journal.ring.calories"].firstMatch, "Nutrition side did not appear")
        sleep(8)
        switchSide(toNutrition: false)
        waitFor(app.staticTexts["profile.stat.totalWorkouts"], "Did not return to the gym side")
        openTab("Today")
        waitFor(app.staticTexts["Rest Period"], "Rest countdown vanished after the side switch")
        let low = NSPredicate(format: "label BEGINSWITH '2:5' OR label BEGINSWITH '2:4' OR label BEGINSWITH '2:3'")
        XCTAssertTrue(app.staticTexts.matching(low).firstMatch.waitForExistence(timeout: 5),
                      "Rest countdown restarted instead of continuing")
    }

    // MARK: - Every path that can touch the clock

    /// Tab tap tolerant of the duplicate tab-bar button the system briefly exposes after a side switch.
    private func goTab(_ title: String) {
        let tab = waitFor(app.tabBars.buttons[title].firstMatch)
        waitUntilHittable(tab)
        for _ in 0..<3 where !tab.isSelected {
            tab.tap()
            let selected = NSPredicate(format: "selected == true")
            _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: selected, object: tab)], timeout: 3)
        }
        sleep(1)
    }

    private func journal() -> XCUIElement { app.descendants(matching: .any)["journal.ring.calories"].firstMatch }

    /// Leaves Today for `tab`, hops to the nutrition side and back, then returns to Today.
    private func awayViaSideSwitch(from tab: String, seconds: UInt32) {
        goTab(tab)
        switchSide(toNutrition: true)
        waitFor(journal(), "Nutrition side did not appear")
        sleep(seconds)
        switchSide(toNutrition: false)
        waitFor(app.tabBars.buttons[tab].firstMatch, "Did not return to the gym side")
        sleep(2)   // let the reveal finish so only the gym tab bar is hittable
        let elapsed = app.staticTexts["workout.elapsed"]
        for _ in 0..<3 where !elapsed.exists {
            goTab("Today")
            if elapsed.waitForExistence(timeout: 5) { break }
        }
        shot("missing-after-\(tab)")
        waitFor(elapsed, "Active workout missing after returning to Today (from \(tab))")
    }

    private func assertAdvanced(from before: Int, by gain: Int, _ what: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        let after = elapsedSeconds()
        XCTAssertGreaterThanOrEqual(after, before + gain,
                                    "\(what): clock froze or reset (before=\(before)s after=\(after)s)", file: file, line: line)
    }

    /// 1. Side switch from each tab that carries the button (History, Progress, Profile), one cycle per workout.
    private func sideSwitchCycle(from tab: String) {
        launchApp()
        startManualWorkout()
        sleep(3)
        let before = elapsedSeconds()
        awayViaSideSwitch(from: tab, seconds: 4)
        assertAdvanced(from: before, by: 4, "side switch from \(tab)")
    }
    func testSideSwitchFromHistory() throws { sideSwitchCycle(from: "History") }
    func testSideSwitchFromProgress() throws { sideSwitchCycle(from: "Progress") }
    func testSideSwitchFromProfile() throws { sideSwitchCycle(from: "Profile") }

    /// 1b. The Today header's switch button is covered by the workout screen: not reachable mid-workout.
    func testTodayHeaderSwitchHiddenDuringWorkout() throws {
        launchApp()
        startManualWorkout()
        XCTAssertFalse(app.buttons["side.switch"].firstMatch.exists, "Active workout screen has no side switch")
    }

    /// 2. Plain tab changes.
    func testPlainTabChanges() throws {
        launchApp()
        startManualWorkout()
        sleep(2)
        let before = elapsedSeconds()
        for tab in ["History", "Progress", "Profile"] {
            openTab(tab)
            sleep(2)
        }
        openTab("Today")
        waitFor(app.staticTexts["workout.elapsed"])
        assertAdvanced(from: before, by: 6, "tab changes")
    }

    /// 3. Background and foreground, gym side.
    func testBackgroundForegroundOnGymSide() throws {
        launchApp()
        startManualWorkout()
        sleep(2)
        let before = elapsedSeconds()
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        sleep(6)
        app.activate()
        waitFor(app.staticTexts["workout.elapsed"])
        assertAdvanced(from: before, by: 6, "background/foreground")
    }

    /// 3. Background and foreground while on the nutrition side.
    func testBackgroundForegroundOnNutritionSide() throws {
        launchApp()
        startManualWorkout()
        sleep(2)
        let before = elapsedSeconds()
        openTab("Profile")
        switchSide(toNutrition: true)
        waitFor(journal())
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        sleep(5)
        app.activate()
        waitFor(journal())
        switchSide(toNutrition: false)
        openTab("Today")
        waitFor(app.staticTexts["workout.elapsed"])
        assertAdvanced(from: before, by: 5, "background on nutrition side")
    }

    /// 3. Kill and relaunch while on the gym side.
    func testKillRelaunchOnGymSide() throws {
        launchApp()
        startManualWorkout()
        sleep(4)
        let before = elapsedSeconds()
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.terminate()
        sleep(4)
        app.launchArguments = ["-uiTesting"]
        app.launch()
        waitFor(app.staticTexts["workout.elapsed"], "Workout was not restored")
        assertAdvanced(from: before, by: 4, "kill/relaunch on gym side")
    }

    /// 4. Sheets over the workout: coach chat, add exercise, finish confirmation (cancelled).
    func testSheetsOverWorkoutKeepClock() throws {
        launchApp()
        generateAndStartPushWorkout()
        waitFor(app.staticTexts["workout.elapsed"])
        sleep(2)
        let before = elapsedSeconds()

        tap(app.buttons["Chat with coach"])
        sleep(3)
        app.swipeDown(velocity: .fast)
        waitFor(app.staticTexts["workout.elapsed"], "Chat sheet did not dismiss")

        tap(app.buttons["addExerciseButton"])
        sleep(3)
        app.swipeDown(velocity: .fast)
        waitFor(app.staticTexts["workout.elapsed"], "Add exercise sheet did not dismiss")

        tap(app.buttons["finishWorkoutButton"])
        sleep(2)
        tap(app.alerts.buttons["keepTrainingButton"].firstMatch)
        waitFor(app.staticTexts["workout.elapsed"])
        assertAdvanced(from: before, by: 8, "sheets over the workout")
    }

    /// 5. Pause, side switch while paused: stays paused and does not jump; resume continues from there.
    func testPausedClockStaysPausedAcrossSideSwitch() throws {
        launchApp()
        startManualWorkout()
        sleep(4)
        tap(app.buttons["Pause workout"])
        waitFor(app.buttons["Resume workout"])
        let paused = elapsedSeconds()
        awayViaSideSwitch(from: "Profile", seconds: 5)
        waitFor(app.buttons["Resume workout"], "Pause was lost across the side switch")
        let after = elapsedSeconds()
        XCTAssertLessThanOrEqual(abs(after - paused), 1, "Paused clock jumped: \(paused)s -> \(after)s")
        tap(app.buttons["Resume workout"])
        sleep(3)
        assertAdvanced(from: after, by: 2, "resume after pause")
        XCTAssertLessThan(elapsedSeconds(), paused + 12, "Resume counted the paused span")
    }

    /// 6. Rest timer through tab changes and background.
    func testRestTimerSurvivesTabChangesAndBackground() throws {
        launchApp(extraArguments: ["-defaultRestSeconds", "180"])
        startManualWorkout()
        waitFor(app.buttons["startRestButton"]).tap()
        waitFor(app.staticTexts["Rest Period"])
        openTab("History")
        sleep(3)
        openTab("Today")
        waitFor(app.staticTexts["Rest Period"], "Rest vanished after a tab change")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        sleep(5)
        app.activate()
        waitFor(app.staticTexts["Rest Period"], "Rest vanished after background")
        let low = NSPredicate(format: "label BEGINSWITH '2:4' OR label BEGINSWITH '2:3' OR label BEGINSWITH '2:5'")
        XCTAssertTrue(app.staticTexts.matching(low).firstMatch.waitForExistence(timeout: 5),
                      "Rest countdown restarted instead of continuing")
    }

    /// 8. Start types. Manual is covered above; AI plan, repeat last and from history here.
    private func awayAndBack(_ what: String) {
        waitFor(app.staticTexts["workout.elapsed"], "\(what): workout did not start")
        sleep(3)
        let before = elapsedSeconds()
        awayViaSideSwitch(from: "Profile", seconds: 4)
        assertAdvanced(from: before, by: 4, what)
    }

    func testAIPlanClockSurvivesSideSwitch() throws {
        launchApp()
        generateAndStartPushWorkout()
        awayAndBack("AI plan")
    }

    func testRepeatLastClockSurvivesSideSwitch() throws {
        launchApp()
        tap(app.buttons["chip.Push"])
        tap(app.buttons["repeatLastButton"])
        let start = waitFor(app.buttons["startWorkoutButton"], timeout: 30)
        var swipes = 0
        while !start.isHittable && swipes < 6 { app.swipeUp(); swipes += 1 }
        tap(start)
        awayAndBack("repeat last")
    }

    func testHistoryRepeatClockTicks() throws {
        launchApp()
        openTab("History")
        tap(app.buttons.matching(identifier: "historyRow.Push").firstMatch)
        tap(app.buttons["Use This Workout Today"])
        let start = waitFor(app.buttons["startWorkoutButton"], timeout: 30)
        var swipes = 0
        while !start.isHittable && swipes < 6 { app.swipeUp(); swipes += 1 }
        tap(start)
        waitFor(app.staticTexts["workout.elapsed"], "History repeat did not start")
        sleep(5)
        XCTAssertGreaterThanOrEqual(elapsedSeconds(), 4, "History-started clock is not counting")
    }
}
