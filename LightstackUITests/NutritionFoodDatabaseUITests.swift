import XCTest

/// Branded (Open Food Facts) search and barcode lookup, against the fake food database.
final class NutritionFoodDatabaseUITests: LightstackUITestCase {

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func label(_ id: String) -> String { waitFor(any(id)).label }

    private func openNutrition() {
        tap(app.buttons["side.switch"].firstMatch)
        waitFor(any("journal.ring.calories"), "Journal did not appear after switching sides")
    }

    private func setTargets() {
        openTab("Goals")
        tap(app.buttons["goals.add"])
        type("100", into: app.textFields["nutrition.target.protein"])
        type("200", into: app.textFields["nutrition.target.carbs"])
        type("50", into: app.textFields["nutrition.target.fat"])
        dismissKeyboardIfNeeded()
        tap(app.buttons["nutrition.target.save"])
        XCTAssertTrue(app.buttons["nutrition.target.save"].waitForNonExistence(timeout: timeout))
        waitFor(any("goals.plan.Daily"))
        openTab("Journal")
        waitFor(any("journal.ring.calories"))
    }

    private func start() {
        launchApp(colorScheme: "light")
        openNutrition()
        setTargets()
    }

    private func search(_ text: String, meal: String) {
        tap(app.buttons["journal.meal.\(meal).add"])
        type(text, into: app.textFields["addfood.search"])
    }

    private func lookUp(_ code: String) {
        tap(app.buttons["journal.barcode"])
        type(code, into: app.textFields["nutrition.barcode.field"])
        dismissKeyboardIfNeeded()
        tap(app.buttons["nutrition.barcode.lookup"])
    }

    func testBrandedSearchLogsTwoServingsToBreakfast() throws {
        start()
        search("greek yogurt", meal: "Breakfast")
        waitFor(app.buttons["addfood.branded.Greek Yogurt Strawberry"])
        waitFor(any("addfood.branded.attribution"))
        shot("branded-01-search-results")
        tap(app.buttons["addfood.branded.Greek Yogurt Strawberry"])
        waitFor(any("branded.name"))
        tap(app.buttons["branded.servings.inc"])
        tap(app.buttons["branded.servings.inc"])
        shot("branded-02-serving-sheet")
        tap(app.buttons["branded.add"])
        waitFor(any("journal.ring.calories"))
        XCTAssertTrue(label("journal.ring.calories").contains("240 of"), label("journal.ring.calories"))
        tap(app.buttons["journal.meal.Breakfast"])
        waitFor(app.buttons["journal.entry.Greek Yogurt Strawberry"])
    }

    func testOreoLogsToSnackAndAppearsInRecent() throws {
        start()
        search("oreo", meal: "Snack")
        waitFor(app.buttons["addfood.branded.Oreo Original Cookies"])
        tap(app.buttons["addfood.branded.Oreo Original Cookies"])
        tap(app.buttons["branded.add"])
        waitFor(any("journal.ring.calories"))
        XCTAssertTrue(label("journal.ring.calories").contains("160 of"), label("journal.ring.calories"))
        tap(app.buttons["journal.meal.Snack.add"])
        waitFor(app.buttons["addfood.food.Oreo Original Cookies"], "Branded food should be in Most Recent")
    }

    func testBarcodeFoundThenLogged() throws {
        start()
        lookUp("0123456789012")
        waitFor(any("branded.name"))
        XCTAssertEqual(label("branded.name"), "Total 0% Greek Yogurt")
        shot("barcode-02-found")
        tap(app.buttons["branded.add"])
        waitFor(any("journal.ring.calories"))
        XCTAssertTrue(label("journal.ring.calories").contains("90 of"), label("journal.ring.calories"))
    }

    func testBarcodeNotFoundCreateFoodThenScanResolvesLocally() throws {
        start()
        tap(app.buttons["journal.barcode"])
        waitFor(any("barcode.stub"))
        shot("barcode-01-scanner-stub")
        type("0000000000000", into: app.textFields["nutrition.barcode.field"])
        dismissKeyboardIfNeeded()
        tap(app.buttons["nutrition.barcode.lookup"])
        waitFor(any("barcode.notfound"))
        waitFor(app.buttons["barcode.scanLabel"])
        shot("barcode-03-not-found")
        tap(app.buttons["barcode.create"])
        type("Barcode Bar", into: app.textFields["nutrition.review.name"])
        type("200", into: app.textFields["nutrition.review.field.calories"])
        dismissKeyboardIfNeeded()
        tap(app.buttons["nutrition.review.save"])
        waitFor(any("journal.ring.calories"))

        lookUp("0000000000000")
        waitFor(any("branded.name"))
        XCTAssertEqual(label("branded.name"), "Barcode Bar")
        XCTAssertFalse(any("barcode.notfound").exists)
    }
}
