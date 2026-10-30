import XCTest

final class NutritionTests: LightstackUITestCase {

    // MARK: - Helpers

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func label(_ id: String) -> String {
        waitFor(any(id)).label
    }

    private func openNutrition() {
        openTab("Nutrition")
        waitFor(any("nutrition.remaining.calories"))
    }

    private func setTargets(protein: String = "100", carbs: String = "200", fat: String = "50") {
        tap(app.buttons["nutrition.target.edit"])
        type(protein, into: app.textFields["nutrition.target.protein"])
        type(carbs, into: app.textFields["nutrition.target.carbs"])
        type(fat, into: app.textFields["nutrition.target.fat"])
        dismissKeyboardIfNeeded()
        tap(app.buttons["nutrition.target.save"])
        XCTAssertTrue(app.buttons["nutrition.target.save"].waitForNonExistence(timeout: timeout))
    }

    private func quickAdd(name: String = "", kcal: String, protein: String, carbs: String, fat: String) {
        tap(app.buttons["nutrition.quickAdd.button"])
        if !name.isEmpty { type(name, into: app.textFields["nutrition.quickAdd.name"]) }
        type(kcal, into: app.textFields["nutrition.quickAdd.kcal"])
        type(protein, into: app.textFields["nutrition.quickAdd.protein"])
        type(carbs, into: app.textFields["nutrition.quickAdd.carbs"])
        type(fat, into: app.textFields["nutrition.quickAdd.fat"])
        dismissKeyboardIfNeeded()
        tap(app.buttons["nutrition.quickAdd.save"])
        XCTAssertTrue(app.buttons["nutrition.quickAdd.save"].waitForNonExistence(timeout: timeout))
    }

    private var entryRows: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'nutrition.entry.' AND NOT identifier ENDSWITH '.delete'"))
    }

    private var foodRows: XCUIElementQuery {
        app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'nutrition.food.' AND NOT identifier BEGINSWITH 'nutrition.food.favorite.'"))
    }

    /// Day view -> Scan label -> stub "Use this" -> review form.
    private func scanToReview() {
        tap(app.buttons["nutrition.scan.button"])
        tap(app.buttons["nutrition.scan.use"])
        waitFor(app.textFields["nutrition.review.name"])
    }

    // MARK: - Tests

    func testSetTargetsAndQuickAddUpdatesRemaining() throws {
        launchApp(colorScheme: "light")
        openNutrition()
        shot("01-empty-day")

        tap(app.buttons["nutrition.target.edit"])
        type("100", into: app.textFields["nutrition.target.protein"])
        type("200", into: app.textFields["nutrition.target.carbs"])
        type("50", into: app.textFields["nutrition.target.fat"])
        dismissKeyboardIfNeeded()
        XCTAssertTrue(any("nutrition.target.derived").label.contains("1,650"), "Calories should derive 4/4/9")
        shot("02-targets")
        tap(app.buttons["nutrition.target.save"])
        XCTAssertTrue(app.buttons["nutrition.target.save"].waitForNonExistence(timeout: timeout))

        XCTAssertTrue(label("nutrition.remaining.calories").contains("1,650 remaining"), label("nutrition.remaining.calories"))

        quickAdd(name: "Snack", kcal: "500", protein: "30", carbs: "50", fat: "10")
        XCTAssertTrue(label("nutrition.remaining.calories").contains("1,150 remaining"), label("nutrition.remaining.calories"))
        XCTAssertTrue(label("nutrition.remaining.protein").contains("70 remaining"), label("nutrition.remaining.protein"))
        XCTAssertTrue(label("nutrition.remaining.carbs").contains("150 remaining"))
        XCTAssertTrue(label("nutrition.remaining.fat").contains("40 remaining"))
        XCTAssertEqual(entryRows.count, 1)
        shot("03-after-quick-add")

        // Micronutrients are collapsed and unknown values show a dash.
        tap(app.buttons["Micronutrients"])
        waitFor(any("nutrition.micro.sodium"))
        shot("03b-micros")
        XCTAssertTrue(label("nutrition.micro.sodium").contains("not recorded"), label("nutrition.micro.sodium"))
    }

    func testOverTargetUsesNeutralOverWording() throws {
        launchApp()
        openNutrition()
        setTargets(protein: "10", carbs: "10", fat: "10")
        quickAdd(kcal: "500", protein: "30", carbs: "5", fat: "5")
        let protein = label("nutrition.remaining.protein")
        XCTAssertTrue(protein.contains("20 over target"), protein)
    }

    func testScanStubReviewHighlightsEditSaveAndLog() throws {
        launchApp(colorScheme: "dark", extraArguments: ["-nutritionScanFixture", "macro_inconsistent"])
        openNutrition()
        setTargets()
        scanToReview()
        shot("04-review-dark")

        // The calories do not match the macros, so those fields are flagged.
        XCTAssertTrue(any("nutrition.review.flag.calories").exists, "Uncertain field should be highlighted")

        type("Test Bar", into: app.textFields["nutrition.review.name"])
        dismissKeyboardIfNeeded()
        replaceText(in: app.textFields["nutrition.review.field.calories"], with: "145")
        XCTAssertTrue(any("nutrition.review.flag.calories").waitForNonExistence(timeout: 5),
                      "Editing a flagged field clears its highlight")
        let servings = app.textFields["nutrition.review.servings"]
        for _ in 0..<6 where !servings.exists { app.swipeUp() }
        replaceText(in: servings, with: "2")
        dismissKeyboardIfNeeded()
        tap(app.buttons["nutrition.review.save"])

        waitFor(any("nutrition.remaining.calories"))
        XCTAssertTrue(label("nutrition.remaining.calories").contains("1,360 remaining"), label("nutrition.remaining.calories"))
        XCTAssertEqual(entryRows.count, 1)
        shot("05-after-scan-log")
    }

    func testPerHundredGramLabelDefaultsToHighlightedHundredGramServing() throws {
        launchApp(extraArguments: ["-nutritionScanFixture", "per100g_only"])
        openNutrition()
        scanToReview()
        XCTAssertEqual(app.textFields["nutrition.review.servingAmount"].value as? String, "100")
        XCTAssertTrue(any("nutrition.review.flag.serving").exists, "100 g default serving should be highlighted")
        shot("06-per100g-review")
    }

    func testReuseFromRecentFavouritesAndSearch() throws {
        launchApp(extraArguments: ["-nutritionScanFixture", "us_standard"])
        openNutrition()
        scanToReview()
        type("Oat Bowl", into: app.textFields["nutrition.review.name"])
        dismissKeyboardIfNeeded()
        tap(app.buttons["nutrition.review.save"])
        waitFor(any("nutrition.remaining.calories"))
        XCTAssertTrue(label("nutrition.remaining.calories").contains("250"))

        // Recent: log two more servings.
        tap(app.buttons["nutrition.addFood.button"])
        let recent = foodRows.firstMatch
        tap(recent)
        replaceText(in: app.textFields["nutrition.log.quantity"], with: "2")
        dismissKeyboardIfNeeded()
        shot("07-log-food")
        tap(app.buttons["nutrition.log.confirm"])
        waitFor(any("nutrition.remaining.calories"))
        XCTAssertTrue(label("nutrition.remaining.calories").contains("750"), label("nutrition.remaining.calories"))
        XCTAssertEqual(entryRows.count, 2)

        // Favourites.
        tap(app.buttons["nutrition.addFood.button"])
        waitFor(foodRows.firstMatch)
        let star = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'nutrition.food.favorite.'")).firstMatch
        tap(star)
        tap(app.buttons["Favourites"])
        waitFor(foodRows.firstMatch)
        XCTAssertEqual(foodRows.count, 1)

        // Search.
        type("oat", into: app.textFields["nutrition.history.search"])
        waitFor(foodRows.firstMatch)
        shot("08-search")
        replaceText(in: app.textFields["nutrition.history.search"], with: "zzz")
        waitFor(any("nutrition.addFood.empty"))
    }

    /// Delete from the entry editor. (The row also has a swipe-to-delete action; a synthesized swipe on iOS 26
    /// is taken by the tab bar's own swipe gesture in the simulator, so it is not driven here.)
    func testDeleteEntry() throws {
        launchApp()
        openNutrition()
        quickAdd(name: "Delete me", kcal: "300", protein: "10", carbs: "30", fat: "10")
        tap(waitFor(entryRows.firstMatch))
        tap(app.buttons["nutrition.entryEdit.delete"])
        waitFor(any("nutrition.entries.empty"))
        XCTAssertEqual(entryRows.count, 0)
        XCTAssertTrue(label("nutrition.remaining.calories").contains("0 kcal") || label("nutrition.remaining.calories").contains("no target"))
    }

    func testEditEntryServings() throws {
        launchApp()
        openNutrition()
        quickAdd(name: "Rice", kcal: "200", protein: "4", carbs: "44", fat: "0")
        tap(entryRows.firstMatch)
        replaceText(in: app.textFields["nutrition.entryEdit.servings"], with: "2")
        dismissKeyboardIfNeeded()
        tap(app.buttons["nutrition.entryEdit.save"])
        XCTAssertTrue(app.buttons["nutrition.entryEdit.save"].waitForNonExistence(timeout: timeout))
        XCTAssertTrue(label("nutrition.remaining.calories").contains("400"), label("nutrition.remaining.calories"))
    }

    func testNutritionSurvivesRelaunch() throws {
        launchApp()
        openNutrition()
        setTargets()
        quickAdd(name: "Persist", kcal: "500", protein: "30", carbs: "50", fat: "10")
        XCTAssertTrue(label("nutrition.remaining.calories").contains("1,150 remaining"))

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.terminate()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        openNutrition()
        XCTAssertTrue(label("nutrition.remaining.calories").contains("1,150 remaining"), label("nutrition.remaining.calories"))
        XCTAssertEqual(entryRows.count, 1)
        shot("09-after-relaunch")
    }
}
