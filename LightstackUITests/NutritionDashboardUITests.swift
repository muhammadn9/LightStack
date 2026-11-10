import XCTest

/// Phase 6: the nutrition Dashboard, summary, weigh-ins and weight history.
final class NutritionDashboardUITests: LightstackUITestCase {

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func openDashboard() {
        tap(app.buttons["side.switch"].firstMatch)
        waitFor(any("journal.ring.calories"), "Journal did not appear after switching sides")
        openTab("Dashboard")
        waitFor(any("dashboard.macros"))
    }

    private func tileValue(_ id: String) -> String {
        (waitFor(any(id)).value as? String) ?? ""
    }

    /// First number in a tile value like "1,234 of 2,000".
    private func firstNumber(_ text: String) -> Double {
        let head = text.components(separatedBy: " ").first ?? ""
        return Double(head.replacingOccurrences(of: ",", with: "")) ?? -1
    }

    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 6) {
        for _ in 0..<maxSwipes where !(element.exists && element.isHittable) { app.swipeUp() }
    }

    private func logWeight(_ text: String, viaCard: Bool = false) {
        if viaCard {
            scrollTo(any("dashboard.weighIn.add"))
            tap(app.buttons["dashboard.weighIn.add"])
        } else {
            tap(app.buttons["journal.plus"])
            tap(app.buttons["addmenu.weight"])
        }
        let field = app.textFields["weight.value"]
        waitFor(field)
        replaceText(in: field, with: text)
        dismissKeyboardIfNeeded()
        tap(app.buttons["weight.save"])
        XCTAssertTrue(app.buttons["weight.save"].waitForNonExistence(timeout: timeout))
    }

    func testDashboardShowsCards() throws {
        launchApp(colorScheme: "light")
        openDashboard()
        shot("60-dashboard-top")
        for id in ["dashboard.tile.protein", "dashboard.tile.carbs", "dashboard.tile.fat", "dashboard.tile.kcal"] {
            waitFor(any(id))
        }
        scrollTo(any("dashboard.foodLog"))
        waitFor(any("dashboard.weighIn"))
        let streak = waitFor(any("dashboard.streak"))
        XCTAssertTrue(streak.label.contains("3"), "Streak text was: \(streak.label)")
        shot("61-dashboard-cards")
    }

    func testSelectingPastDayChangesCalories() throws {
        launchApp()
        openDashboard()
        XCTAssertEqual(firstNumber(tileValue("dashboard.tile.kcal")), 0)
        let weekday = Calendar.current.component(.weekday, from: Date())
        if weekday == 1 {
            tap(app.buttons["dashboard.prevWeek"])
            tap(app.buttons["dashboard.day.6"])
        } else {
            tap(app.buttons["dashboard.day.\(weekday - 2)"])
        }
        let kcal = any("dashboard.tile.kcal")
        let changed = NSPredicate { _, _ in self.firstNumber((kcal.value as? String) ?? "") > 0 }
        let exp = XCTNSPredicateExpectation(predicate: changed, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: timeout), .completed,
                       "Calories stayed at \(tileValue("dashboard.tile.kcal"))")
    }

    func testWeekNavigation() throws {
        launchApp()
        openDashboard()
        XCTAssertFalse(app.buttons["dashboard.nextWeek"].isEnabled)
        tap(app.buttons["dashboard.prevWeek"])
        XCTAssertTrue(app.buttons["dashboard.nextWeek"].isEnabled)
        XCTAssertNotEqual(any("dashboard.weekTitle").label, "This week")
        tap(app.buttons["dashboard.nextWeek"])
        XCTAssertEqual(any("dashboard.weekTitle").label, "This week")
        XCTAssertFalse(app.buttons["dashboard.nextWeek"].isEnabled)
    }

    func testSummaryAndRange() throws {
        launchApp()
        openDashboard()
        tap(app.buttons["dashboard.seeAll"])
        waitFor(any("dashboard.summary"))
        let onTarget = waitFor(any("dashboard.summary.onTarget"))
        XCTAssertTrue(onTarget.label.contains("logged days on target"), onTarget.label)
        let logged28 = waitFor(any("dashboard.summary.logged")).label
        XCTAssertTrue(logged28.hasSuffix("of 28 days logged"), logged28)
        shot("62-summary-4weeks")
        tap(app.buttons["3 months"])
        let predicate = NSPredicate(format: "label ENDSWITH 'of 90 days logged'")
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: any("dashboard.summary.logged"))
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: timeout), .completed)
        shot("63-summary-3months")
    }

    func testLogWeightFromMenuUpdatesCard() throws {
        launchApp()
        tap(app.buttons["side.switch"].firstMatch)
        waitFor(any("journal.ring.calories"))
        logWeight("178.4")
        openTab("Dashboard")
        waitFor(any("dashboard.macros"))
        scrollTo(any("dashboard.weighIn.open"))
        let value = (any("dashboard.weighIn.open").value as? String) ?? ""
        XCTAssertTrue(value.contains("178.4"), "Weigh-in card value: \(value)")
    }

    func testLogWeightFromCardPlus() throws {
        launchApp()
        openDashboard()
        logWeight("177.2", viaCard: true)
        let open = any("dashboard.weighIn.open")
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS '177.2'"), object: open)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: timeout), .completed,
                       "Weigh-in card value: \((open.value as? String) ?? "nil")")
    }

    func testSaveDisabledForInvalidInput() throws {
        launchApp()
        openDashboard()
        scrollTo(any("dashboard.weighIn.add"))
        tap(app.buttons["dashboard.weighIn.add"])
        let field = app.textFields["weight.value"]
        waitFor(field)
        shot("64-log-weight-sheet")
        replaceText(in: field, with: "0")
        dismissKeyboardIfNeeded()
        XCTAssertFalse(app.buttons["weight.save"].isEnabled)
        tap(field)
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        dismissKeyboardIfNeeded()
        XCTAssertFalse(app.buttons["weight.save"].isEnabled)
        tap(field)
        field.typeText("180")
        dismissKeyboardIfNeeded()
        XCTAssertTrue(app.buttons["weight.save"].isEnabled)
    }

    func testWeightHistoryEditAndDelete() throws {
        launchApp()
        openDashboard()
        logWeight("178.4", viaCard: true)
        scrollTo(any("dashboard.weighIn.open"))
        tap(any("dashboard.weighIn.open"))
        waitFor(any("dashboard.weightHistory"))
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'weight.row.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: timeout))
        XCTAssertEqual(rows.count, 6, "5 seeded + 1 logged")
        shot("65-weight-history")

        // Swipe-delete the oldest visible row, then confirm.
        let last = rows.element(boundBy: rows.count - 1)
        let id = last.identifier
        let dayId = String(id.dropFirst("weight.row.".count))
        scrollTo(last)
        last.swipeLeft()
        tap(app.buttons["weight.delete.\(dayId)"])
        tap(app.alerts.buttons["Delete"])
        XCTAssertTrue(any(id).waitForNonExistence(timeout: timeout), "Row was not deleted")
        XCTAssertEqual(rows.count, 5)

        // Tap the newest row, edit its weight.
        let first = rows.element(boundBy: 0)
        first.tap()
        let field = app.textFields["weight.value"]
        waitFor(field)
        replaceText(in: field, with: "175.5")
        dismissKeyboardIfNeeded()
        tap(app.buttons["weight.save"])
        XCTAssertTrue(app.buttons["weight.save"].waitForNonExistence(timeout: timeout))
        let updated = NSPredicate(format: "value CONTAINS '175.5'")
        let exp = XCTNSPredicateExpectation(predicate: updated, object: rows.element(boundBy: 0))
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: timeout), .completed)
    }

    func testLogWeightFromHistoryToolbar() throws {
        launchApp()
        openDashboard()
        scrollTo(any("dashboard.weighIn.open"))
        tap(any("dashboard.weighIn.open"))
        waitFor(any("dashboard.weightHistory"))
        tap(app.buttons["weight.history.log"])
        let field = app.textFields["weight.value"]
        waitFor(field)
        replaceText(in: field, with: "181.0")
        dismissKeyboardIfNeeded()
        tap(app.buttons["weight.save"])
        XCTAssertTrue(app.buttons["weight.save"].waitForNonExistence(timeout: timeout))
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'weight.row.'"))
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 6"), object: rows)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: timeout), .completed)
    }
}
