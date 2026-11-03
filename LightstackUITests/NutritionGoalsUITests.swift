import XCTest

/// Setup wizard, weekday plans and the Goals tab.
final class NutritionGoalsUITests: LightstackUITestCase {

    private let wizardArgs = ["-uiTestingNutritionWizard"]

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func label(_ id: String) -> String { waitFor(any(id)).label }

    private func openNutrition() {
        tap(app.buttons["side.switch"].firstMatch)
        waitFor(any("journal.ring.calories"), "Journal did not appear after switching sides")
    }

    private func next() { tap(app.buttons["setup.continue"]) }

    /// Taps `id` `times` times.
    private func press(_ id: String, _ times: Int) {
        for _ in 0..<times { tap(app.buttons[id]) }
    }

    /// Number at the start of "2,150 calories" or "0 of 2,150".
    private func kcalFromResult() -> String {
        label("setup.result.kcal").components(separatedBy: " ").first ?? ""
    }

    private func walkToActivity(goal: String, weightSteps: Int = 0) {
        waitFor(app.buttons["setup.goal.\(goal)"], "Wizard did not open")
        shot("wizard-01-goal-\(goal)")
        tap(app.buttons["setup.goal.\(goal)"])
        next()
        waitFor(any("setup.age.value"))
        shot("wizard-02-about-\(goal)")
        next()
        waitFor(any("setup.weight.value"))
        press("setup.weight.plus", weightSteps)
        shot("wizard-03-current-weight-\(goal)")
        next()
    }

    private func finishQuestions() {
        waitFor(app.buttons["setup.activity.active"])
        shot("wizard-06-activity")
        tap(app.buttons["setup.activity.active"])
        next()
        waitFor(app.buttons["setup.lift.yes"])
        shot("wizard-07-lifting")
        tap(app.buttons["setup.lift.yes"])
        next()
        waitFor(any("setup.loading"))
        shot("wizard-08-loading")
        waitFor(any("setup.result.kcal"))
    }

    private func journalCalories() -> String { label("journal.ring.calories") }

    // MARK: - Wizard

    func testWizardLosePathEndToEnd() throws {
        launchApp(colorScheme: "light", extraArguments: wizardArgs)
        openNutrition()
        walkToActivity(goal: "lose")
        waitFor(any("setup.target.value"))
        press("setup.target.minus", 5)
        shot("wizard-04-target-weight")
        next()
        waitFor(any("setup.rate.slider"))
        shot("wizard-05-rate")
        tap(app.buttons["setup.rate.recommended"])
        XCTAssertNotEqual(label("setup.rate.date"), "–", "Lose path should project a goal date")
        next()
        finishQuestions()
        shot("wizard-09-result")
        let kcal = kcalFromResult()
        XCTAssertFalse(kcal.isEmpty)
        tap(app.buttons["setup.finish"])
        waitFor(any("journal.ring.calories"))
        XCTAssertTrue(journalCalories().contains("0 of \(kcal)"), "\(journalCalories()) vs \(kcal)")
        shot("wizard-10-journal")
        openTab("Goals")
        waitFor(any("goals.plan.Daily"))
        XCTAssertFalse(any("goals.personalize").exists, "Personalize card should be gone after setup")
        shot("goals-01-after-setup")
    }

    func testWizardMaintainSkipsTargetWeightAndRate() throws {
        launchApp(extraArguments: wizardArgs)
        openNutrition()
        walkToActivity(goal: "maintain")
        // Straight to activity: no target-weight or rate screens.
        XCTAssertFalse(any("setup.target.value").exists)
        XCTAssertFalse(any("setup.rate.slider").exists)
        waitFor(app.buttons["setup.activity.active"])
        finishQuestions()
        tap(app.buttons["setup.finish"])
        waitFor(any("journal.ring.calories"))
        XCTAssertFalse(journalCalories().contains("of 0"), journalCalories())
    }

    func testWizardEditTargetPath() throws {
        launchApp(extraArguments: wizardArgs)
        openNutrition()
        walkToActivity(goal: "maintain")
        finishQuestions()
        tap(app.buttons["setup.editTarget"])
        replaceText(in: app.textFields["nutrition.target.protein"], with: "111")
        replaceText(in: app.textFields["nutrition.target.carbs"], with: "222")
        replaceText(in: app.textFields["nutrition.target.fat"], with: "33")
        dismissKeyboardIfNeeded()
        shot("wizard-11-edit-target")
        tap(app.buttons["nutrition.target.save"])
        waitFor(any("journal.ring.protein"))
        XCTAssertTrue(label("journal.ring.protein").contains("of 111"), label("journal.ring.protein"))
        XCTAssertTrue(journalCalories().contains("of 1,629"), journalCalories())
    }

    func testSkipForNowDoesNotNag() throws {
        launchApp(extraArguments: wizardArgs)
        openNutrition()
        waitFor(app.buttons["setup.skip"])
        tap(app.buttons["setup.skip"])
        waitFor(any("journal.ring.calories"))
        openTab("Goals")
        waitFor(any("goals.personalize"))
        shot("goals-02-personalize")
    }

    // MARK: - Existing user

    func testExistingUserWithTargetsSeesPersonalizeCardNotWizard() throws {
        launchApp()
        openNutrition()
        openTab("Goals")
        tap(app.buttons["goals.add"])
        type("100", into: app.textFields["nutrition.target.protein"])
        type("200", into: app.textFields["nutrition.target.carbs"])
        type("50", into: app.textFields["nutrition.target.fat"])
        dismissKeyboardIfNeeded()
        tap(app.buttons["nutrition.target.save"])
        waitFor(any("goals.plan.Daily"))
        app.terminate()

        app.launchArguments = ["-uiTesting"] + wizardArgs
        app.launch()
        waitFor(app.tabBars.firstMatch, timeout: 45)
        // Wait for whichever side restored, and go to nutrition if it came back on the gym side.
        let deadline = Date().addingTimeInterval(20)
        var switched = false
        while Date() < deadline, !app.tabBars.buttons["Goals"].exists {
            if !switched, app.tabBars.buttons["Today"].exists {
                app.buttons["side.switch"].firstMatch.tap()
                switched = true
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        openTab("Goals")
        XCTAssertFalse(app.buttons["setup.skip"].waitForExistence(timeout: 3), "Wizard must not open for a user who already has targets")
        waitFor(any("goals.personalize"))
        shot("goals-03-existing-user-personalize")
    }

    // MARK: - Plans

    private func addPlan(name: String, days: [Int], deselect: [Int] = [], protein: String, carbs: String, fat: String) {
        tap(app.buttons["goals.add"])
        let nameField = app.textFields["plan.name"]
        replaceText(in: nameField, with: name)
        for day in deselect { tap(app.buttons["plan.day.\(day)"]) }
        for day in days { tap(app.buttons["plan.day.\(day)"]) }
        dismissKeyboardIfNeeded()
        for (id, value) in [("protein", protein), ("carbs", carbs), ("fat", fat)] {
            let field = app.textFields["nutrition.target.\(id)"]
            scrollToField(field)
            replaceText(in: field, with: value)
            dismissKeyboardIfNeeded()
        }
    }

    private func scrollToField(_ field: XCUIElement) {
        for _ in 0..<5 where !(field.exists && field.isHittable) { app.swipeUp() }
    }

    private func dayId(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// A date within the current week that falls on `weekday` (1 = Sunday ... 7 = Saturday).
    private func dateInCurrentWeek(weekday: Int) -> Date {
        let cal = Calendar.current
        let today = Date()
        let offset = weekday - cal.component(.weekday, from: today)
        return cal.date(byAdding: .day, value: offset, to: today) ?? today
    }

    func testWeekendPlanAppliesToWeekendAndDailyToWeekdays() throws {
        launchApp(colorScheme: "light")
        openNutrition()
        openTab("Goals")
        addPlan(name: "Daily", days: [], protein: "100", carbs: "200", fat: "50")
        tap(app.buttons["nutrition.target.save"])
        waitFor(any("goals.plan.Daily"))

        addPlan(name: "Weekend", days: [1, 7], deselect: [], protein: "150", carbs: "300", fat: "70")
        shot("goals-04-editor-weekend")
        // Sunday and Saturday come from Daily, so the editor warns about the move.
        waitFor(any("plan.moveNote"))
        tap(app.buttons["nutrition.target.save"])
        waitFor(any("goals.plan.Weekend"))
        shot("goals-05-two-plans")

        openTab("Journal")
        let saturday = dateInCurrentWeek(weekday: 7)
        let wednesday = dateInCurrentWeek(weekday: 4)
        tap(app.buttons["journal.day.\(dayId(saturday))"])
        // Weekend: 150 P, 300 C, 70 F = 2,430 kcal.
        XCTAssertTrue(waitForLabel("journal.ring.calories", contains: "of 2,430"), journalCalories())
        tap(app.buttons["journal.day.\(dayId(wednesday))"])
        // Daily: 100 P, 200 C, 50 F = 1,650 kcal.
        XCTAssertTrue(waitForLabel("journal.ring.calories", contains: "of 1,650"), journalCalories())
        shot("journal-weekday-vs-weekend")
    }

    func testDeletePlan() throws {
        launchApp()
        openNutrition()
        openTab("Goals")
        addPlan(name: "Daily", days: [], protein: "100", carbs: "200", fat: "50")
        tap(app.buttons["nutrition.target.save"])
        waitFor(any("goals.plan.Daily"))
        tap(app.buttons["goals.plan.Daily"])
        let delete = app.buttons["plan.delete"]
        for _ in 0..<5 where !(delete.exists && delete.isHittable) { app.swipeUp() }
        tap(delete)
        shot("goals-06-delete-confirm")
        tap(app.alerts.buttons["Delete"].firstMatch)
        XCTAssertTrue(any("goals.plan.Daily").waitForNonExistence(timeout: timeout))
        waitFor(any("goals.empty"))
    }

    func testUncoveredDaysWarning() throws {
        launchApp()
        openNutrition()
        openTab("Goals")
        addPlan(name: "Weekdays", days: [], deselect: [1, 7], protein: "100", carbs: "200", fat: "50")
        tap(app.buttons["nutrition.target.save"])
        waitFor(any("goals.plan.Weekdays"))
        let warning = waitFor(any("goals.uncovered"))
        XCTAssertTrue(warning.label.contains("Sun") && warning.label.contains("Sat"), warning.label)
        shot("goals-07-uncovered")
    }

    private func waitForLabel(_ id: String, contains text: String) -> Bool {
        let element = any(id)
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 10) == .completed
    }
}
