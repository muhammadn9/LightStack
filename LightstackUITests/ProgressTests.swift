import XCTest

final class ProgressTests: LightstackUITestCase {

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// The seeded "Core Day" is dated today: 3 Lat Pulldown sets (cable), 2 Leg Press sets (machine).
    func testTodayShowsEquipmentUsage() throws {
        launchApp()
        waitFor(app.buttons["chip.Push"])
        let card = waitFor(element("equipment.usedCount"), "Equipment card missing on Today")
        XCTAssertTrue(card.exists)
        waitFor(element("weekStrip"), "Week strip missing on Today")
        XCTAssertEqual(waitFor(element("equipment.Cable")).label, "Cable, 3 sets")
        XCTAssertEqual(element("equipment.Machine").label, "Machine, 2 sets")
        XCTAssertEqual(element("equipment.Kettlebell").label, "Kettlebell, not yet")
        let used = element("equipment.usedCount").label
        XCTAssertTrue(["2 of 7", "3 of 7", "4 of 7", "5 of 7"].contains(used), "Unexpected used count \(used)")
        shot("today-equipment")
        app.swipeUp()
        shot("today-controls")
    }

    /// Opens Progress when the app has a tab bar for it; otherwise only the Today half runs.
    func testProgressTabShowsStats() throws {
        launchApp()
        let tab = app.tabBars.buttons["Progress"]
        guard tab.waitForExistence(timeout: 5) else {
            throw XCTSkip("No Progress tab in this build")
        }
        tab.tap()
        waitFor(app.staticTexts["progress.title"])
        waitFor(element("progress.streak"))
        shot("progress-overview")
        tap(app.buttons["progress.segment.Lifts"])
        waitFor(element("progress.liftsList"))
        shot("progress-lifts")
        tap(app.buttons["progress.segment.Equipment"])
        waitFor(element("progress.equipmentWeeks"))
        shot("progress-equipment")
    }
}
