import XCTest

/// Phase 5: Kitchen (meals, recipes, foods), the editors, logging them, and serving units.
final class NutritionKitchenUITests: LightstackUITestCase {

    // MARK: - Helpers

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func openNutrition() {
        tap(app.buttons["side.switch"].firstMatch)
        waitFor(any("journal.ring.calories"), "Journal did not appear after switching sides")
    }

    private func menuItem(_ id: String, _ title: String) -> XCUIElement {
        let byId = app.buttons[id].firstMatch
        if byId.waitForExistence(timeout: 4) { return byId }
        return app.buttons[title].firstMatch
    }

    /// Coordinate taps retried until `target` appears; for elements XCUITest wrongly reports as not hittable.
    @discardableResult
    private func tapAt(_ element: XCUIElement, until target: XCUIElement, attempts: Int = 3) -> Bool {
        for _ in 0..<attempts {
            if target.exists { return true }
            if element.waitForExistence(timeout: 10) {
                waitUntilHittable(element)
                element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            if target.waitForExistence(timeout: 8) { return true }
        }
        return target.exists
    }

    private func start() {
        launchApp(colorScheme: "light")
        openNutrition()
    }

    private func openKitchen(_ chip: String? = nil) {
        openTab("Kitchen")
        waitFor(app.buttons["kitchen.chip.All"])
        if let chip { tap(app.buttons["kitchen.chip.\(chip)"]) }
    }

    /// Opens the food picker inside an editor and picks a food.
    private func pick(_ addButton: String, _ food: String) {
        dismissKeyboardIfNeeded()
        tap(app.buttons[addButton])
        tap(app.buttons["picker.food.\(food)"])
    }

    private func createMeal(named name: String, foods: [String]) {
        tap(app.buttons["journal.plus"])
        tap(app.buttons["addmenu.createMeal"])
        type(name, into: app.textFields["meal.name"])
        for food in foods { pick("meal.addFood", food) }
        dismissKeyboardIfNeeded()
    }

    private func createRecipe(named name: String, foods: [String]) {
        tap(app.buttons["journal.plus"])
        tap(app.buttons["addmenu.createRecipe"])
        type(name, into: app.textFields["recipe.name"])
        for food in foods { pick("recipe.addIngredient", food) }
        dismissKeyboardIfNeeded()
    }

    // MARK: - Kitchen list

    func testKitchenChipsFilterMealsRecipesAndFoods() throws {
        start()
        openKitchen()
        waitFor(app.buttons["kitchen.row.Usual breakfast"])
        waitFor(app.buttons["kitchen.row.Egg Oat Bowl"])
        waitFor(app.buttons["kitchen.food.Egg"])
        XCTAssertFalse(app.buttons["kitchen.food.Egg Oat Bowl"].exists, "A recipe's own food must not be listed as a food")
        XCTAssertFalse(any("kitchen.soon").exists)
        shot("kitchen-01-all")

        tap(app.buttons["kitchen.chip.Meals"])
        waitFor(app.buttons["kitchen.row.Usual breakfast"])
        XCTAssertFalse(app.buttons["kitchen.row.Egg Oat Bowl"].exists)
        XCTAssertFalse(app.buttons["kitchen.food.Egg"].exists)

        tap(app.buttons["kitchen.chip.Recipes"])
        waitFor(app.buttons["kitchen.row.Egg Oat Bowl"])
        XCTAssertFalse(app.buttons["kitchen.row.Usual breakfast"].exists)
        XCTAssertFalse(app.buttons["kitchen.food.Egg Oat Bowl"].exists)
        shot("kitchen-02-recipes")

        tap(app.buttons["kitchen.chip.Foods"])
        waitFor(app.buttons["kitchen.food.Egg"])
        XCTAssertFalse(app.buttons["kitchen.row.Usual breakfast"].exists)
        XCTAssertFalse(app.buttons["kitchen.row.Egg Oat Bowl"].exists)
        XCTAssertFalse(app.buttons["kitchen.food.Egg Oat Bowl"].exists)

        tap(app.buttons["kitchen.chip.All"])
        type("oat", into: app.textFields["kitchen.search"])
        waitFor(app.buttons["kitchen.row.Egg Oat Bowl"])
        waitFor(app.buttons["kitchen.food.Oats"])
        XCTAssertFalse(app.buttons["kitchen.food.Greek Yogurt"].exists)
    }

    func testEditSeededMeal() throws {
        start()
        openKitchen("Meals")
        tap(app.buttons["kitchen.row.Usual breakfast"])
        let name = waitFor(app.textFields["meal.name"])
        XCTAssertEqual(name.value as? String, "Usual breakfast")
        waitFor(app.textFields["meal.item.0.servings"])
        waitFor(app.textFields["meal.item.1.servings"])
        XCTAssertTrue(any("meal.total").label.contains("730 calories"), any("meal.total").label)
    }

    /// Deleting from the editor (the swipe-to-delete gesture is not driveable by XCUITest: its synthesized swipe also opens the row).
    func testDeleteSeededMealFromEditorAsksForConfirmation() throws {
        start()
        openKitchen("Meals")
        tap(app.buttons["kitchen.row.Usual breakfast"])
        tap(app.buttons["meal.delete"])
        shot("kitchen-07-delete-confirm")
        tap(app.alerts.buttons["Delete"].firstMatch)
        XCTAssertTrue(app.buttons["meal.delete"].waitForNonExistence(timeout: timeout))
        XCTAssertTrue(app.buttons["kitchen.row.Usual breakfast"].waitForNonExistence(timeout: timeout), "Meal was not deleted")
    }

    // MARK: - Create menu

    func testAddMenuHasNoAlcoholicBev() throws {
        start()
        tap(app.buttons["journal.plus"])
        waitFor(app.buttons["addmenu.createFood"])
        XCTAssertTrue(app.buttons["addmenu.createMeal"].isEnabled)
        XCTAssertTrue(app.buttons["addmenu.createRecipe"].isEnabled)
        XCTAssertFalse(app.buttons["addmenu.createBev"].exists)
        XCTAssertFalse(app.staticTexts["Create Alcoholic Bev"].exists)
        shot("kitchen-00-add-menu")
    }

    func testCreateMealFromPlusMenuAppearsInKitchen() throws {
        start()
        createMeal(named: "Post workout", foods: ["Egg", "Oats"])
        waitFor(app.textFields["meal.item.1.servings"])
        XCTAssertTrue(any("meal.total").label.contains("450 calories"), any("meal.total").label)
        shot("kitchen-03-meal-editor")
        tap(app.buttons["meal.save"])
        XCTAssertTrue(app.buttons["meal.save"].waitForNonExistence(timeout: timeout))
        openKitchen("Meals")
        waitFor(app.buttons["kitchen.row.Post workout"])
        waitFor(app.buttons["kitchen.row.Usual breakfast"])
    }

    func testMealSaveIsDisabledWithoutNameOrItems() throws {
        start()
        tap(app.buttons["journal.plus"])
        tap(app.buttons["addmenu.createMeal"])
        waitFor(app.buttons["meal.save"])
        XCTAssertFalse(app.buttons["meal.save"].isEnabled)
        type("Only a name", into: app.textFields["meal.name"])
        dismissKeyboardIfNeeded()
        XCTAssertFalse(app.buttons["meal.save"].isEnabled)
        pick("meal.addFood", "Egg")
        waitFor(app.textFields["meal.item.0.servings"])
        XCTAssertTrue(app.buttons["meal.save"].isEnabled)
    }

    // MARK: - Log meals and recipes

    func testLogSeededMealIntoLunch() throws {
        start()
        tap(app.buttons["journal.meal.Lunch.add"])
        tap(app.buttons["addfood.savedMeal.Usual breakfast"])
        waitFor(any("meal.log.item.0"))
        waitFor(any("food.mealBadge"))
        tap(app.buttons["meal.log"])
        XCTAssertTrue(app.buttons["addfood.back"].waitForNonExistence(timeout: timeout), "Add-food flow did not close")
        waitFor(any("journal.ring.calories"))
        // 3 x 140 + 310
        XCTAssertTrue(any("journal.ring.calories").label.contains("730"), any("journal.ring.calories").label)
        let lunch = app.buttons["journal.meal.Lunch"]
        waitFor(lunch)
        // The card sits behind the floating search bar until scrolled.
        for _ in 0..<4 where lunch.frame.maxY > app.windows.firstMatch.frame.height - 200 { app.swipeUp() }
        let expanded = tapAt(lunch, until: app.buttons["journal.entry.Egg"])
        XCTAssertTrue(expanded)
        waitFor(app.buttons["journal.entry.Oats"])
    }

    func testCreateRecipeThenFindAndLogIt() throws {
        start()
        createRecipe(named: "Test Bowl", foods: ["Egg", "Oats"])
        waitFor(app.textFields["recipe.item.1.servings"])
        XCTAssertTrue(any("recipe.perServing").label.contains("450 calories"), any("recipe.perServing").label)
        tap(app.buttons["recipe.yield.inc"])
        tap(app.buttons["recipe.yield.inc"])
        XCTAssertEqual(app.textFields["recipe.yield"].value as? String, "2")
        XCTAssertTrue(any("recipe.perServing").label.contains("225 calories"), any("recipe.perServing").label)
        replaceText(in: app.textFields["recipe.cookedWeight"], with: "500")
        dismissKeyboardIfNeeded()
        waitFor(any("recipe.servingWeight"))
        shot("kitchen-04-recipe-editor")
        tap(app.buttons["recipe.save"])
        XCTAssertTrue(app.buttons["recipe.save"].waitForNonExistence(timeout: timeout))

        openKitchen("Recipes")
        waitFor(app.buttons["kitchen.row.Test Bowl"])
        XCTAssertFalse(app.buttons["kitchen.food.Test Bowl"].exists)
        openTab("Journal")

        tap(app.buttons["journal.meal.Dinner.add"])
        type("Test Bowl", into: app.textFields["addfood.search"])
        waitFor(app.buttons["addfood.food.Test Bowl"])
        waitFor(any("food.recipeBadge"))
        tap(app.buttons["addfood.add.Test Bowl"])
        tap(app.buttons["plate.confirm"])
        waitFor(any("journal.ring.calories"))
        XCTAssertTrue(any("journal.ring.calories").label.contains("225"), any("journal.ring.calories").label)
        tap(app.buttons["journal.meal.Dinner"])
        waitFor(app.buttons["journal.entry.Test Bowl"])
    }

    func testSeededRecipeShowsUnderRecipesFilterOfAddFlow() throws {
        start()
        tap(app.buttons["journal.meal.Lunch.add"])
        tap(app.buttons["addfood.chip.Recipes"])
        waitFor(app.buttons["addfood.food.Egg Oat Bowl"])
        XCTAssertFalse(app.buttons["addfood.food.Egg"].exists)
        tap(app.buttons["addfood.chip.Meals"])
        waitFor(app.buttons["addfood.savedMeal.Usual breakfast"])
        XCTAssertFalse(any("addfood.soon").exists)
        XCTAssertFalse(app.buttons["addfood.food.Egg Oat Bowl"].exists)
    }

    // MARK: - Save as meal

    func testJournalMealSaveAsMeal() throws {
        start()
        tap(app.buttons["journal.meal.Breakfast.add"])
        waitFor(app.buttons["addfood.food.Egg"])
        tap(app.buttons["addfood.add.Egg"])
        tap(app.buttons["addfood.add.Greek Yogurt"])
        tap(app.buttons["plate.confirm"])
        waitFor(any("journal.ring.calories"))

        tap(app.buttons["journal.meal.Breakfast.menu"])
        tap(menuItem("journal.saveAsMeal", "Save as meal"))
        let field = waitFor(app.alerts.textFields.firstMatch)
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))
        field.typeText("Yogurt and egg")
        tap(app.alerts.buttons["journal.saveAsMeal.confirm"].firstMatch)
        openKitchen("Meals")
        waitFor(app.buttons["kitchen.row.Yogurt and egg"])
    }

    func testPlateSaveAsMeal() throws {
        start()
        tap(app.buttons["journal.meal.Breakfast.add"])
        tap(app.buttons["addfood.add.Egg"])
        tap(app.buttons["plate.open"])
        tap(app.buttons["plate.saveAsMeal"])
        waitFor(app.textFields["meal.name"])
        waitFor(app.textFields["meal.item.0.servings"])
        type("From plate", into: app.textFields["meal.name"])
        dismissKeyboardIfNeeded()
        tap(app.buttons["meal.save"])
        XCTAssertTrue(app.buttons["meal.save"].waitForNonExistence(timeout: timeout))
        tap(app.buttons["plate.done"])
        tap(app.buttons["addfood.chip.Meals"])
        waitFor(app.buttons["addfood.savedMeal.From plate"])
    }

    // MARK: - Serving units

    func testLogOatsInGramsShowsGramsOnTheEntry() throws {
        start()
        tap(app.buttons["journal.meal.Breakfast.add"])
        tap(app.buttons["addfood.food.Oats"])
        waitFor(any("log.unit"))
        waitFor(app.buttons["log.unit.g"])
        shot("kitchen-05-unit-picker")
        tap(app.buttons["log.unit.g"])
        replaceText(in: app.textFields["plate.servings.field"], with: "80")
        dismissKeyboardIfNeeded()
        tap(app.buttons["plate.servings.save"])
        tap(app.buttons["plate.confirm"])
        waitFor(any("journal.ring.calories"))
        // 80 g of a 40 g serving = 2 servings of 310 kcal
        XCTAssertTrue(any("journal.ring.calories").label.contains("620"), any("journal.ring.calories").label)
        tap(app.buttons["journal.meal.Breakfast"])
        let entry = waitFor(app.buttons["journal.entry.Oats"])
        XCTAssertTrue(entry.label.contains("80 g"), entry.label)
    }

    func testFavoriteUnitsComeFirstInThePicker() throws {
        start()
        tap(app.buttons["journal.menu"])
        tap(menuItem("journal.menu.settings", "Journal settings"))
        tap(app.buttons["settings.favoriteUnits"])
        // Start clean: other runs may have left favourites behind.
        for unit in ["serving", "g", "oz", "ml", "flOz", "cup", "tbsp", "tsp"] {
            let row = waitFor(app.buttons["settings.unit.\(unit)"])
            if (row.value as? String) == "Favorite" { tap(row) }
        }
        tap(app.buttons["settings.unit.oz"])
        XCTAssertEqual(app.buttons["settings.unit.oz"].value as? String, "Favorite")
        shot("kitchen-06-favorite-units")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap(app.buttons["nutritionSettings.done"])
        XCTAssertTrue(app.buttons["nutritionSettings.done"].waitForNonExistence(timeout: timeout))

        tap(app.buttons["journal.meal.Breakfast.add"])
        tap(app.buttons["addfood.food.Oats"])
        let oz = waitFor(app.buttons["log.unit.oz"])
        let serving = waitFor(app.buttons["log.unit.serving"])
        let grams = waitFor(app.buttons["log.unit.g"])
        XCTAssertLessThan(oz.frame.minX, serving.frame.minX, "Favourite unit should come first")
        XCTAssertLessThan(serving.frame.minX, grams.frame.minX)
        tap(app.buttons["Cancel"])

        // Put things back.
        tap(app.buttons["addfood.back"])
        tap(app.buttons["journal.menu"])
        tap(menuItem("journal.menu.settings", "Journal settings"))
        tap(app.buttons["settings.favoriteUnits"])
        tap(app.buttons["settings.unit.oz"])
    }
}
