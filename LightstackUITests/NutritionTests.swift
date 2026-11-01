import XCTest

final class NutritionTests: LightstackUITestCase {

    // MARK: - Helpers

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func label(_ id: String) -> String {
        waitFor(any(id)).label
    }

    private func switchSide() {
        tap(app.buttons["side.switch"].firstMatch)
    }

    /// Gym side -> nutrition side (Journal).
    private func openNutrition() {
        switchSide()
        waitFor(any("journal.ring.calories"), "Journal did not appear after switching sides")
    }

    /// Goals tab -> set targets -> back to Journal.
    private func setTargets(protein: String = "100", carbs: String = "200", fat: String = "50") {
        openTab("Goals")
        tap(app.buttons["goals.edit"])
        type(protein, into: app.textFields["nutrition.target.protein"])
        type(carbs, into: app.textFields["nutrition.target.carbs"])
        type(fat, into: app.textFields["nutrition.target.fat"])
        dismissKeyboardIfNeeded()
        tap(app.buttons["nutrition.target.save"])
        XCTAssertTrue(app.buttons["nutrition.target.save"].waitForNonExistence(timeout: timeout))
        waitFor(any("goals.calories"))
        openTab("Journal")
        waitFor(any("journal.ring.calories"))
    }

    private func menuItem(_ id: String, _ title: String) -> XCUIElement {
        let byId = app.buttons[id]
        if byId.waitForExistence(timeout: 4) { return byId }
        return app.buttons[title]
    }

    private func quickAddFields(name: String = "", kcal: String, protein: String, carbs: String, fat: String) {
        if !name.isEmpty { type(name, into: app.textFields["nutrition.quickAdd.name"]) }
        type(kcal, into: app.textFields["nutrition.quickAdd.kcal"])
        type(protein, into: app.textFields["nutrition.quickAdd.protein"])
        type(carbs, into: app.textFields["nutrition.quickAdd.carbs"])
        type(fat, into: app.textFields["nutrition.quickAdd.fat"])
        dismissKeyboardIfNeeded()
        tap(app.buttons["nutrition.quickAdd.save"])
        XCTAssertTrue(app.buttons["nutrition.quickAdd.save"].waitForNonExistence(timeout: timeout))
    }

    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) {
        for _ in 0..<maxSwipes where !(element.exists && element.isHittable) { app.swipeUp() }
    }

    private func dayId(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: - Sides

    func testSwitchSidesAndBackKeepsActiveWorkout() throws {
        launchApp(colorScheme: "light")
        generateAndStartPushWorkout()
        shot("01-active-workout")

        // The active workout has no header button, so switch from Profile.
        openTab("Profile")
        openNutrition()
        shot("02-nutrition-light")
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].exists)
        XCTAssertTrue(app.tabBars.buttons["Goals"].exists)
        XCTAssertTrue(app.tabBars.buttons["Kitchen"].exists)

        switchSide()
        waitFor(app.tabBars.buttons["Today"], "Gym tab bar did not return")
        openTab("Today")
        waitFor(weightField(), "Active workout was lost by switching sides")
    }

    func testEverySideSwitchButtonLocation() throws {
        launchApp()
        for tab in ["Today", "History", "Progress", "Profile"] {
            openTab(tab)
            waitFor(app.buttons["side.switch"].firstMatch, "No switch button on \(tab)")
        }
        openNutrition()
        for tab in ["Dashboard", "Goals", "Kitchen", "Journal"] {
            openTab(tab)
            waitFor(app.buttons["side.switch"].firstMatch, "No switch button on \(tab)")
        }
    }

    func testSideSurvivesRelaunch() throws {
        launchApp()
        openNutrition()
        app.terminate()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        waitFor(any("journal.ring.calories"), "App did not reopen on the nutrition side")
    }

    // MARK: - Journal

    func testPlateLogsTwoFoodsToBreakfastAndUpdatesRings() throws {
        launchApp(colorScheme: "light")
        openNutrition()
        setTargets()
        shot("10-journal-empty-light")
        XCTAssertTrue(label("journal.ring.calories").contains("0 of 1,650"), label("journal.ring.calories"))

        tap(app.buttons["journal.meal.Breakfast.add"])
        waitFor(app.buttons["addfood.food.Egg"])
        tap(app.buttons["addfood.add.Egg"])
        tap(app.buttons["addfood.add.Greek Yogurt"])
        XCTAssertTrue(label("plate.open").contains("2 items"), label("plate.open"))
        shot("11-add-food-plate-light")
        tap(app.buttons["plate.confirm"])

        waitFor(any("journal.ring.calories"))
        XCTAssertTrue(label("journal.ring.calories").contains("300 of 1,650"), label("journal.ring.calories"))
        XCTAssertTrue(label("journal.ring.protein").contains("32 of 100"), label("journal.ring.protein"))

        tap(app.buttons["journal.meal.Breakfast"])
        waitFor(app.buttons["journal.entry.Egg"])
        waitFor(app.buttons["journal.entry.Greek Yogurt"])
        shot("12-journal-expanded-light")
        app.swipeUp()
        app.swipeUp()
        shot("13-journal-scrolled-light")
    }

    func testAdjustServingsOnThePlate() throws {
        launchApp()
        openNutrition()
        tap(app.buttons["journal.meal.Breakfast.add"])
        tap(app.buttons["addfood.food.Egg"])
        replaceText(in: app.textFields["plate.servings.field"], with: "2")
        dismissKeyboardIfNeeded()
        tap(app.buttons["plate.servings.save"])
        XCTAssertTrue(label("plate.open").contains("1 items"), label("plate.open"))
        tap(app.buttons["plate.confirm"])
        waitFor(any("journal.ring.calories"))
        XCTAssertTrue(label("journal.ring.calories").hasPrefix("kCal, 280"), label("journal.ring.calories"))
    }

    func testQuickAddIntoLunch() throws {
        launchApp()
        openNutrition()
        setTargets()
        tap(app.buttons["journal.meal.Lunch.add"])
        tap(app.buttons["addfood.plus"])
        tap(menuItem("addfood.quickadd", "Quick add"))
        quickAddFields(name: "Wrap", kcal: "500", protein: "30", carbs: "50", fat: "10")
        waitFor(any("journal.ring.calories"))
        XCTAssertTrue(label("journal.ring.calories").contains("500 of 1,650"), label("journal.ring.calories"))
        tap(app.buttons["journal.meal.Lunch"])
        waitFor(app.buttons["journal.entry.Wrap"])
    }

    func testWaterAddAndDelete() throws {
        launchApp()
        openNutrition()
        XCTAssertTrue(label("journal.water.total").contains("0 fl oz"), label("journal.water.total"))
        tap(app.buttons["journal.water.add"])
        tap(app.buttons["journal.water.quick.8"])
        XCTAssertTrue(label("journal.water.total").contains("8 fl oz"), label("journal.water.total"))
        shot("20-water")
        tap(app.buttons["journal.water.delete.0"])
        XCTAssertTrue(label("journal.water.total").contains("0 fl oz"), label("journal.water.total"))
    }

    func testRenameMealAndCreateNewMeal() throws {
        launchApp()
        openNutrition()
        tap(app.buttons["journal.meal.Breakfast.menu"])
        tap(menuItem("Rename meal", "Rename meal"))
        let field = waitFor(app.alerts.textFields.firstMatch)
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))
        field.typeText("Brunch")
        tap(app.alerts.buttons["Save"])
        waitFor(app.buttons["journal.meal.Brunch"])
        XCTAssertFalse(app.buttons["journal.meal.Breakfast"].exists)

        scrollTo(app.buttons["journal.meal.create"])
        tap(app.buttons["journal.meal.create"])
        let newField = waitFor(app.alerts.textFields.firstMatch)
        newField.tap()
        newField.typeText("Pre-workout")
        tap(app.alerts.buttons["Add"])
        waitFor(app.buttons["journal.meal.Pre-workout"])
        shot("30-meals-renamed")
    }

    func testDayNotePersistsAcrossRelaunch() throws {
        launchApp()
        openNutrition()
        let note = app.textFields["journal.note.field"]
        scrollTo(note)
        type("Felt strong today", into: note)
        dismissKeyboardIfNeeded()

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.terminate()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        waitFor(any("journal.ring.calories"))
        let restored = app.textFields["journal.note.field"]
        scrollTo(restored)
        XCTAssertEqual(restored.value as? String, "Felt strong today")
        shot("31-note-after-relaunch")
    }

    func testWeekStripChangesDay() throws {
        launchApp()
        openNutrition()
        XCTAssertEqual(label("journal.date.label"), "Today")
        let cal = Calendar.current
        let today = Date()
        // Pick a neighbour inside the visible week.
        let isFirstDay = cal.component(.weekday, from: today) == cal.firstWeekday
        let other = cal.date(byAdding: .day, value: isFirstDay ? 1 : -1, to: today) ?? today
        tap(app.buttons["journal.day.\(dayId(other))"])
        XCTAssertEqual(label("journal.date.label"), isFirstDay ? "Tomorrow" : "Yesterday")
        tap(app.buttons["journal.date.label"])
        XCTAssertEqual(label("journal.date.label"), "Today")
    }

    func testScanStubLogsIntoMeal() throws {
        launchApp(colorScheme: "dark", extraArguments: ["-nutritionScanFixture", "us_standard"])
        openNutrition()
        setTargets()
        tap(app.buttons["journal.meal.Dinner.add"])
        tap(app.buttons["addfood.plus"])
        tap(menuItem("addfood.scan", "Scan label"))
        tap(app.buttons["nutrition.scan.use"])
        type("Test Bar", into: app.textFields["nutrition.review.name"])
        dismissKeyboardIfNeeded()
        shot("40-review-dark")
        tap(app.buttons["nutrition.review.save"])
        waitFor(any("journal.ring.calories"))
        XCTAssertTrue(label("journal.ring.calories").contains("250 of 1,650"), label("journal.ring.calories"))
        tap(app.buttons["journal.meal.Dinner"])
        waitFor(app.buttons["journal.entry.Test Bar"])
    }

    // MARK: - Other tabs

    func testKitchenGoalsAndDashboard() throws {
        launchApp(colorScheme: "dark")
        openNutrition()
        shot("50-journal-dark")
        openTab("Kitchen")
        waitFor(app.buttons["kitchen.food.Oats"])
        tap(app.buttons["kitchen.favorite.Oats"])
        shot("51-kitchen-dark")
        tap(app.buttons["kitchen.food.Oats"])
        waitFor(app.textFields["kitchen.edit.name"])
        tap(app.buttons["Cancel"])
        openTab("Goals")
        waitFor(any("goals.card"))
        shot("52-goals-dark")
        openTab("Dashboard")
        waitFor(any("dashboard.soon"))
        shot("53-dashboard-dark")
    }

    func testSettingsFromJournalMenu() throws {
        launchApp()
        openNutrition()
        tap(app.buttons["journal.menu"])
        tap(menuItem("journal.menu.settings", "Journal settings"))
        tap(app.buttons["nutritionSettings.meals"])
        waitFor(app.buttons["settings.meal.Breakfast"])
        shot("60-meal-settings")
    }
}
