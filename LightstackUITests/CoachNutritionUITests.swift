import XCTest

/// Coach and nutrition together: the sharing switches in Settings, the training-day card in the Journal and the
/// FUEL / PRE-WORKOUT MEALS blocks in "What the coach saw".
final class CoachNutritionUITests: LightstackUITestCase {

    private let fuelSeed = ["-uiTestingFuelSeed"]

    private func anyElement(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func scrollTo(_ element: XCUIElement) {
        var swipes = 0
        while !element.isHittable && swipes < 8 { app.swipeUp(); swipes += 1 }
    }

    /// Taps a switch on its control (the right edge), not the row label.
    private func flip(_ toggle: XCUIElement) {
        waitFor(toggle)
        waitUntilHittable(toggle)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    private func isOn(_ toggle: XCUIElement) -> Bool { (toggle.value as? String) == "1" }

    private func waitForValue(_ toggle: XCUIElement, on: Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", on ? "1" : "0"), object: toggle)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed, "Toggle did not turn \(on ? "on" : "off")")
    }

    private func relaunch(arguments: [String]) {
        app.terminate()
        app.launchArguments = ["-uiTesting"] + arguments
        app.launch()
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 45)
    }

    private func openGymSettings() {
        openSettings()
        scrollTo(app.switches["settings.shareNutrition"])
    }

    private func openNutritionJournal() {
        tap(app.buttons["side.switch"].firstMatch)
        waitFor(anyElement("journal.ring.calories"), "Journal did not appear after switching sides")
    }

    private func openJournalSettings() {
        tap(app.buttons["journal.menu"])
        tap(app.buttons["journal.menu.settings"])
        waitFor(app.switches["settings.trainingDayTips"])
    }

    // MARK: - a. Settings

    func testSharingSwitchesExistDisableAndPersist() throws {
        launchApp(colorScheme: "light")
        openGymSettings()
        let summary = waitFor(app.switches["settings.shareNutrition"])
        let meals = waitFor(app.switches["settings.shareMeals"])
        XCTAssertTrue(isOn(summary) && isOn(meals), "Both default on")
        XCTAssertTrue(meals.isEnabled)
        XCTAssertTrue(app.staticTexts["Averages, today's intake so far and your weight trend. Never your food list."].exists)
        shot("60-settings-coach-nutrition")

        flip(summary)
        waitForValue(app.switches["settings.shareNutrition"], on: false)
        XCTAssertFalse(app.switches["settings.shareMeals"].isEnabled, "Meals switch is disabled while the summary is off")

        relaunch(arguments: [])
        openGymSettings()
        waitForValue(app.switches["settings.shareNutrition"], on: false)
        XCTAssertFalse(app.switches["settings.shareMeals"].isEnabled)
        shot("61-settings-sharing-off")

        flip(app.switches["settings.shareNutrition"])
        waitForValue(app.switches["settings.shareNutrition"], on: true)
        XCTAssertTrue(app.switches["settings.shareMeals"].isEnabled)
        flip(app.switches["settings.shareMeals"])
        waitForValue(app.switches["settings.shareMeals"], on: false)

        relaunch(arguments: [])
        openGymSettings()
        waitForValue(app.switches["settings.shareNutrition"], on: true)
        waitForValue(app.switches["settings.shareMeals"], on: false)
    }

    func testNutritionSideSettingsShareTheSameSwitches() throws {
        launchApp()
        openNutritionJournal()
        openJournalSettings()
        let summary = waitFor(app.switches["settings.shareNutrition"])
        XCTAssertTrue(isOn(summary))
        XCTAssertTrue(isOn(waitFor(app.switches["settings.trainingDayTips"])))
        flip(summary)
        waitForValue(app.switches["settings.shareNutrition"], on: false)
        tap(app.buttons["nutritionSettings.done"])

        tap(app.buttons["side.switch"].firstMatch)
        openGymSettings()
        waitForValue(app.switches["settings.shareNutrition"], on: false)
    }

    // MARK: - b. Training-day card

    func testTrainingDayCardShowsDismissesAndStaysHidden() throws {
        launchApp(colorScheme: "light", extraArguments: fuelSeed)
        openNutritionJournal()
        let card = waitFor(anyElement("journal.trainingDay"), "Training-day card missing on a training day")
        _ = card
        XCTAssertTrue(anyElement("journal.trainingDay.title").label.hasPrefix("Training day"), anyElement("journal.trainingDay.title").label)
        let protein = anyElement("journal.trainingDay.protein").label
        XCTAssertTrue(protein.hasPrefix("Protein ") && protein.contains("/45 g so far"), protein)
        XCTAssertFalse(anyElement("journal.trainingDay.tip").label.isEmpty, "A tip is shown")
        shot("62-training-day-card")

        tap(app.buttons["journal.trainingDay.dismiss"])
        XCTAssertTrue(anyElement("journal.trainingDay").waitForNonExistence(timeout: 10), "Dismiss hides the card")

        relaunch(arguments: fuelSeed)
        waitFor(anyElement("journal.ring.calories"), "Journal did not reopen")
        XCTAssertFalse(anyElement("journal.trainingDay").waitForExistence(timeout: 3), "Still hidden after a relaunch the same day")
    }

    func testTrainingDayTipsSwitchHidesTheCard() throws {
        launchApp(extraArguments: fuelSeed)
        openNutritionJournal()
        waitFor(anyElement("journal.trainingDay"))

        openJournalSettings()
        flip(app.switches["settings.trainingDayTips"])
        waitForValue(app.switches["settings.trainingDayTips"], on: false)
        tap(app.buttons["nutritionSettings.done"])
        XCTAssertTrue(anyElement("journal.trainingDay").waitForNonExistence(timeout: 10), "Card hidden while tips are off")

        openJournalSettings()
        flip(app.switches["settings.trainingDayTips"])
        waitForValue(app.switches["settings.trainingDayTips"], on: true)
        tap(app.buttons["nutritionSettings.done"])
        waitFor(anyElement("journal.trainingDay"), "Card returns when tips are turned back on")
    }

    func testNoTrainingDayCardWithoutTheSeededTargets() throws {
        launchApp()
        openNutritionJournal()
        XCTAssertFalse(anyElement("journal.trainingDay").waitForExistence(timeout: 3), "No targets means no card")
    }

    // MARK: - c. What the coach saw

    private func generatePlanAndCancel() {
        tap(app.buttons["chip.Push"])
        tap(app.buttons["generateButton"])
        waitFor(app.buttons["startWorkoutButton"], "Plan preview did not appear")
        let alert = app.alerts["Discard this workout plan?"]
        XCTAssertTrue(tap(app.buttons["previewCancelButton"], until: alert), "Discard confirmation missing")
        tap(alert.buttons["previewDiscardConfirmButton"].firstMatch)
        waitFor(app.buttons["chip.Push"], "Did not return to setup after discarding")
    }

    private func openProfileCoachSaw() {
        openTab("Profile")
        let row = app.buttons["profile.coachSaw"]
        var swipes = 0
        while !row.exists && swipes < 6 { app.swipeUp(); swipes += 1 }
        tap(row)
    }

    func testCoachSawShowsFuelAndMealsThenSharingOff() throws {
        launchApp(colorScheme: "light", extraArguments: fuelSeed)
        generatePlanAndCancel()

        openProfileCoachSaw()
        let fuel = waitFor(anyElement("coachSaw.fuel"), "FUEL block missing")
        XCTAssertTrue(fuel.label.contains("FUEL"), fuel.label)
        XCTAssertTrue(fuel.label.contains("Carbs last 24h"), "Carbs are in the FUEL block: \(fuel.label)")
        let meals = anyElement("coachSaw.meals")
        scrollTo(meals)
        waitFor(meals, "PRE-WORKOUT MEALS block missing")
        shot("63-coach-saw-fuel-and-meals")
        tap(app.buttons["coachSaw.done"])

        openGymSettings()
        flip(app.switches["settings.shareNutrition"])
        waitForValue(app.switches["settings.shareNutrition"], on: false)
        tap(app.navigationBars.buttons.element(boundBy: 0))   // back to the Profile root
        openTab("Today")
        generatePlanAndCancel()

        openProfileCoachSaw()
        let off = waitFor(anyElement("coachSaw.nutritionOff"), "Nutrition sharing is off notice missing")
        XCTAssertTrue(off.label.contains("Nutrition sharing is off"), off.label)
        XCTAssertFalse(anyElement("coachSaw.fuel").exists)
        XCTAssertFalse(anyElement("coachSaw.meals").exists)
        shot("64-coach-saw-sharing-off")
    }
}
