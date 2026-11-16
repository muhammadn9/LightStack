import XCTest

/// Today redesign: slim "This week" card, one split chip list through the coach, Freestyle with a
/// multi-select picker, and A to Z order for browsing lists.
final class GymTodayRedesignTests: LightstackUITestCase {

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func labels(withPrefix prefix: String) -> [String] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .allElementsBoundByIndex
            .filter { $0.exists && !$0.frame.isEmpty }
            .sorted { $0.frame.minY < $1.frame.minY }
            .map(\.label)
    }

    private func assertAZ(_ names: [String], _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(names.count, 2, "\(what): too few rows to judge: \(names)", file: file, line: line)
        for (a, b) in zip(names, names.dropFirst()) {
            XCTAssertNotEqual(a.localizedCaseInsensitiveCompare(b), .orderedDescending,
                              "\(what) is not A to Z: \(a) before \(b)", file: file, line: line)
        }
    }

    // MARK: - Today layout

    func testTodayLayoutLight() throws {
        launchApp(colorScheme: "light")
        assertTodayLayout()
        shot("today-light")
        app.swipeUp()
        shot("today-light-scrolled")
    }

    func testTodayLayoutDark() throws {
        launchApp(colorScheme: "dark")
        assertTodayLayout()
        shot("today-dark")
        app.swipeUp()
        shot("today-dark-scrolled")
    }

    private func assertTodayLayout() {
        waitFor(element("thisWeek.card"), "This week card missing")
        waitFor(element("thisWeek.headline"))
        waitFor(app.staticTexts["splitHeader"], "Workout split card missing")
        waitFor(app.buttons["generateButton"])
        XCTAssertEqual(app.buttons["generateButton"].label, "Build my Push workout")
        waitFor(app.buttons["freestyleButton"])
        waitFor(app.buttons["talkToCoachButton"])
        // Everything the old screen cluttered itself with is gone.
        XCTAssertFalse(element("equipment.usedCount").exists, "Equipment grid must not be on Today")
        XCTAssertFalse(app.staticTexts["Equipment Worked This Week"].exists)
        XCTAssertFalse(app.buttons["logManuallyButton"].exists, "Log Manually left the Today screen")
        XCTAssertFalse(app.buttons["repeatLastButton"].exists, "Repeat last left the Today screen")
        XCTAssertFalse(app.staticTexts["fromHistoryHeader"].exists, "No separate From history card")
        // Split chips: profile split days, then past names that are not split days.
        XCTAssertTrue(app.buttons["chip.Push"].exists)
        XCTAssertTrue(app.buttons["chip.Arm Day"].exists, "Past workout names join the same chip list")
        waitFor(app.staticTexts["setup.lastSession"], "Last session line missing")
        XCTAssertTrue(app.staticTexts["setup.lastSession"].label.contains("The coach builds on it."))
        // Settings rows summarise their values.
        XCTAssertEqual(app.buttons["setup.row.energy"].value as? String, "4 of 5")
        XCTAssertEqual(app.buttons["setup.row.time"].value as? String, "45 min")
        XCTAssertEqual(app.buttons["setup.moreOptions"].value as? String, "None")
    }

    func testSettingsRowsExpandInlineAndAreRemembered() throws {
        launchApp()
        for _ in 0..<4 where !app.buttons["setup.row.time"].isHittable { app.swipeUp() }
        tap(app.buttons["setup.row.time"])
        tap(app.buttons["Increase time"])
        XCTAssertEqual(app.staticTexts["timeValue"].label, "60")
        tap(app.buttons["setup.row.energy"])
        tap(app.buttons["energyDot.2"])
        XCTAssertEqual(app.staticTexts["energyLabel"].label, "2 / 5")
        shot("settings-expanded")

        // Relaunch without wiping: the last used energy and time come back.
        app.terminate()
        launchApp(reset: false)
        for _ in 0..<4 where !app.buttons["setup.row.time"].isHittable { app.swipeUp() }
        waitFor(app.buttons["setup.row.time"])
        XCTAssertEqual(app.buttons["setup.row.time"].value as? String, "60 min")
        XCTAssertEqual(app.buttons["setup.row.energy"].value as? String, "2 of 5")
    }

    // MARK: - Split always uses the coach

    func testHistoryOnlySplitNameGoesThroughCoachPlanPreview() throws {
        launchApp()
        tap(app.buttons["chip.Arm Day"])
        let generate = app.buttons["generateButton"]
        XCTAssertEqual(generate.label, "Build my Arm Day workout")
        tap(generate, until: app.buttons["previewCancelButton"], attempts: 3, perAttempt: 30)
        waitFor(app.buttons["previewCancelButton"], "Plan preview did not appear")
        waitFor(app.staticTexts["Barbell Curl"], "Plan should build on the last Arm Day")
        shot("history-split-plan-preview")
        tap(app.buttons["previewCancelButton"])
        tap(app.alerts.buttons["previewDiscardConfirmButton"].firstMatch)
        waitFor(app.buttons["chip.Arm Day"], "Did not return to setup after discarding")
    }

    // MARK: - Freestyle

    func testFreestyleMultiSelectLogAndFinishWithCoachReview() throws {
        launchApp(colorScheme: "light")
        tap(app.buttons["freestyleButton"])

        // The picker opens straight away on a live, empty workout.
        waitFor(app.buttons["pickerAddButton"], "Exercise picker did not open")
        waitFor(app.staticTexts["recentExercisesHeader"], "Recent group missing")
        waitFor(app.staticTexts["allExercisesHeader"], "A to Z group missing")
        waitFor(app.buttons["pickerRecent.Lat Pulldown"], "Most recent lift missing from Recent")
        XCTAssertFalse(app.buttons["pickerAddButton"].isEnabled, "Nothing ticked yet")
        shot("freestyle-picker")

        // Recent first, then A to Z.
        let recent = labels(withPrefix: "pickerRecent.")
        XCTAssertLessThanOrEqual(recent.count, 5)
        XCTAssertEqual(recent.first, "Lat Pulldown")
        assertAZ(labels(withPrefix: "pickerRow."), "Picker list")

        // Tick two, in this order.
        tap(app.buttons["pickerRow.Lat Pulldown"])
        tap(app.buttons["pickerRow.Bench Press"])
        XCTAssertEqual(app.buttons["pickerAddButton"].label, "Add 2 exercises")
        shot("freestyle-picker-ticked")
        tap(app.buttons["pickerAddButton"])

        // Both added, first ticked first, each prefilled from its last logged session.
        waitFor(app.staticTexts["1 of 2"], "Both exercises should be added")
        waitFor(app.staticTexts["Lat Pulldown"])
        XCTAssertEqual(weightField().value as? String, "100", "Lat Pulldown starts from its last session")
        XCTAssertEqual(repsField().value as? String, "10")
        shot("freestyle-active")
        replaceText(in: weightField(), with: "105")
        replaceText(in: repsField(), with: "10")
        replaceText(in: rirField(), with: "2")
        dismissKeyboardIfNeeded()
        tap(app.buttons["setRow.0.0.log"])
        waitFor(app.staticTexts["loggedSet.0.0.weight"], "Set was not logged")

        // Finish: same post-workout screen with the coach's review.
        finishWorkoutConfirmed()
        waitFor(app.buttons["saveWorkoutButton"], "Post-workout screen did not appear")
        let review = waitFor(element("review.card"), "Coach review missing after a Freestyle workout")
        XCTAssertTrue(review.exists)
        waitFor(element("review.exercise.0"))
        shot("freestyle-post-workout")
        let save = app.buttons["saveWorkoutButton"]
        XCTAssertTrue(save.waitForHittable(timeout: timeout), "Save never became enabled")
        let chip = app.buttons["chip.Push"]
        for _ in 0..<3 where !chip.exists {
            if save.exists && save.isHittable { save.tap() }
            if chip.waitForExistence(timeout: 10) { break }
        }
        waitFor(chip, "Did not return to setup after saving")
        XCTAssertFalse(app.buttons["chip.Freestyle"].exists, "Freestyle is a way to start, not a split chip")
        openTab("History")
        waitFor(app.buttons.matching(identifier: "historyRow.Freestyle").firstMatch, "Freestyle workout missing from History")
    }

    func testEmptyFreestyleShowsAddExercisesAndDiscards() throws {
        launchApp(colorScheme: "light")
        tap(app.buttons["freestyleButton"])
        waitFor(app.buttons["pickerAddButton"])
        tap(app.buttons["pickerCancelButton"])
        let add = waitFor(app.buttons["emptyWorkoutAddButton"], "Empty Freestyle needs an Add exercises call to action")
        waitFor(app.staticTexts["workout.elapsed"], "Clock should be running")
        shot("freestyle-empty")
        tap(add)
        waitFor(app.buttons["pickerAddButton"], "Add exercises did not reopen the picker")
        tap(app.buttons["pickerCancelButton"])

        // Nothing logged: finishing offers to discard, as before.
        tap(app.buttons["finishWorkoutButton"])
        waitFor(app.alerts["Finish workout?"])
        tap(app.alerts.buttons["discardFromFinishButton"].firstMatch)
        waitFor(app.buttons["chip.Push"], "Did not return to setup after discarding")
        openTab("History")
        XCTAssertFalse(app.buttons["historyRow.Freestyle"].waitForExistence(timeout: 3), "Discarded Freestyle must not reach History")
    }

    func testFreestyleSessionSurvivesRelaunch() throws {
        launchApp()
        tap(app.buttons["freestyleButton"])
        tap(app.buttons["pickerRow.Bench Press"])
        tap(app.buttons["pickerAddButton"])
        waitFor(app.staticTexts["1 of 1"])
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.terminate()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        waitFor(app.textFields["setRow.0.0.weight"], "Freestyle workout was not restored after relaunch")
        waitFor(app.staticTexts["workout.elapsed"])
    }

    /// History rows draw one chevron (inside the card), not a second one from the list.
    func testHistoryRowIsTappableWithOneChevron() throws {
        launchApp(colorScheme: "light")
        openTab("History")
        let row = waitFor(app.buttons.matching(identifier: "historyRow.Push").firstMatch)
        shot("history-rows")
        tap(row)
        waitFor(app.staticTexts["Bench Press"], "Row did not open the workout")
    }

    // MARK: - A to Z everywhere

    func testManageExercisesIsAZ() throws {
        launchApp()
        openTab("Profile")
        let manage = app.buttons["profile.manageExercises"]
        for _ in 0..<4 where !manage.isHittable { app.swipeUp() }
        tap(manage)
        waitFor(app.buttons["merge.pick.Barbell Curl"], "Manual merge list missing")
        let names = labelsOfStaticTexts(withIdentifierPrefix: "merge.pick.")
        assertAZ(names, "Manage exercises")
        shot("manage-exercises-az")
    }

    func testTopLiftsListDefaultsToAZ() throws {
        launchApp()
        openTab("Profile")
        let seeAll = app.buttons["profile.seeAllPRs"]
        for _ in 0..<4 where !seeAll.isHittable { app.swipeUp() }
        tap(seeAll)
        waitFor(app.staticTexts["prList.row.Bench Press"])
        let names = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'prList.row.'"))
            .allElementsBoundByIndex.filter { $0.exists && !$0.frame.isEmpty }
            .sorted { $0.frame.minY < $1.frame.minY }.map(\.label)
        assertAZ(names, "Top lifts")
    }

    /// Rows of the merge list are buttons whose child text carries the name.
    private func labelsOfStaticTexts(withIdentifierPrefix prefix: String) -> [String] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .allElementsBoundByIndex
            .filter { $0.exists && !$0.frame.isEmpty }
            .sorted { $0.frame.minY < $1.frame.minY }
            .map { $0.identifier.replacingOccurrences(of: prefix, with: "") }
    }
}
