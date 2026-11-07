import XCTest

final class NutritionAIUITests: LightstackUITestCase {

    private let chipotleText = "half a chicken burrito bowl from Chipotle"

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func openNutrition() {
        tap(app.buttons["side.switch"].firstMatch)
        waitFor(any("journal.ring.calories"), "Journal did not appear after switching sides")
    }

    private func openAIFromPlus() {
        tap(app.buttons["journal.plus"])
        let ai = app.buttons["addmenu.ai"]
        tap(ai)
        waitFor(any("ai.input"))
    }

    private func estimate(_ text: String) {
        type(text, into: any("ai.input"))
        dismissKeyboardIfNeeded()
        tap(app.buttons["ai.estimate"])
    }

    // MARK: - Tests

    func testChipotleHalfBowlLogsToJournal() throws {
        launchApp(colorScheme: "light")
        openNutrition()
        openAIFromPlus()
        estimate(chipotleText)
        waitFor(any("ai.item.0"), "No result item")
        waitFor(any("ai.searchNote"))
        shot("ai-review-screen")
        tap(app.buttons["ai.log"])
        XCTAssertTrue(any("ai.log").waitForNonExistence(timeout: timeout), "Sheet did not close")
        waitFor(any("journal.ring.calories"))
        // 0.5 x 1000 kcal
        XCTAssertTrue(any("journal.ring.calories").label.contains("500"), any("journal.ring.calories").label)
        // The default meal depends on the time of day: open whichever meal holds the 500 kcal.
        let logged = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'journal.meal.' AND label CONTAINS '500 calories'")).firstMatch
        tap(logged)
        waitFor(app.buttons["journal.entry.Chicken Burrito Bowl"], "Logged food missing from journal")
        shot("ai-journal")
    }

    func testServingsStepperChangesTotalThenLogs() throws {
        launchApp()
        openNutrition()
        openAIFromPlus()
        estimate(chipotleText)
        waitFor(any("ai.item.0"))
        let total = any("ai.total")
        waitFor(total)
        let before = total.label
        let stepper = app.steppers["ai.item.0.servings"]
        waitFor(stepper)
        stepper.buttons.element(boundBy: 1).tap()
        let changed = NSPredicate(format: "label != %@", before)
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: changed, object: total)], timeout: 10), .completed,
                       "Total did not change: \(total.label)")
        tap(app.buttons["ai.log"])
        XCTAssertTrue(any("ai.log").waitForNonExistence(timeout: timeout))
        waitFor(any("journal.ring.calories"))
    }

    func testRemoveItemFromMultiItemResult() throws {
        launchApp()
        openNutrition()
        openAIFromPlus()
        estimate("greek yogurt with strawberries")
        waitFor(any("ai.item.1"), "Expected two items")
        tap(app.buttons["ai.item.1.remove"])
        XCTAssertTrue(any("ai.item.1").waitForNonExistence(timeout: 10), "Item was not removed")
        waitFor(any("ai.item.0"))
    }

    func testErrorShowsRetry() throws {
        launchApp()
        openNutrition()
        openAIFromPlus()
        estimate("this will fail")
        waitFor(any("ai.error"))
        waitFor(app.buttons["ai.retry"])
        shot("ai-error")
    }

    func testCancelReturnsToInput() throws {
        launchApp(extraArguments: ["-uiTestAIDelay", "20"])
        openNutrition()
        openAIFromPlus()
        estimate("a sandwich")
        waitFor(any("ai.working"))
        tap(app.buttons["ai.cancel"])
        waitFor(any("ai.input"), "Did not return to input after cancel")
        XCTAssertFalse(any("ai.working").exists)
    }

    func testAIFromMealAddFlowLogsToThatMeal() throws {
        launchApp()
        openNutrition()
        tap(app.buttons["journal.meal.Lunch.add"])
        tap(app.buttons["addfood.plus"])
        let aiItem = any("addfood.ai")
        if !aiItem.waitForExistence(timeout: 5) { XCTFail("Missing addfood.ai"); return }
        aiItem.tap()
        waitFor(any("ai.input"))
        XCTAssertTrue(app.staticTexts["Lunch"].exists || app.buttons["Lunch"].exists || any("ai.mealPicker").label.contains("Lunch"),
                      "Lunch not preselected: \(any("ai.mealPicker").debugDescription)")
        estimate(chipotleText)
        waitFor(any("ai.item.0"))
        XCTAssertTrue(app.buttons["ai.log"].label.contains("Lunch"), app.buttons["ai.log"].label)
        tap(app.buttons["ai.log"])
        XCTAssertTrue(any("ai.log").waitForNonExistence(timeout: timeout))
        // Logging closes the add flow too, back to the journal.
        waitFor(any("journal.ring.calories"))
        XCTAssertTrue(app.buttons["journal.meal.Lunch"].label.contains("500 calories"), app.buttons["journal.meal.Lunch"].label)
        let entry = app.buttons["journal.entry.Chicken Burrito Bowl"]
        if !entry.waitForExistence(timeout: 3) {
            for _ in 0..<3 where !entry.exists { app.swipeUp() }
        }
        if !entry.exists { tap(app.buttons["journal.meal.Lunch"]) }
        waitFor(entry, "Entry not in Lunch")
    }

    func testLoggedFoodShowsAIBadgeInKitchen() throws {
        launchApp()
        openNutrition()
        openAIFromPlus()
        estimate(chipotleText)
        waitFor(any("ai.item.0"))
        tap(app.buttons["ai.log"])
        XCTAssertTrue(any("ai.log").waitForNonExistence(timeout: timeout))
        openTab("Kitchen")
        waitFor(app.buttons["kitchen.food.Chicken Burrito Bowl"], "Food missing in Kitchen")
        waitFor(any("food.aiBadge"), "AI badge missing")
        shot("ai-kitchen")
    }
}
