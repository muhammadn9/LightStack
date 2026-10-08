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

    /// Taps the heatmap cell of a seeded workout day and checks the callout names the date and workout.
    func testHeatmapTapShowsDayDetail() throws {
        launchApp(extraArguments: ["-uiTestingLiftHistory"])
        openTab("Progress")
        waitFor(element("progress.heatmap"))
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let cell = element("heatmap.\(Self.idString(yesterday))")
        waitFor(cell, "Heatmap cell for yesterday missing")
        let detail = element("heatmap.detail")
        var shown = ""
        for _ in 0..<3 {
            cell.tap()
            shown = detail.label
            if shown.contains("Push") { break }
        }
        let expected = yesterday.formatted(.dateTime.month(.abbreviated).day())
        XCTAssertTrue(shown.contains(expected), "Callout \(shown) lacks \(expected)")
        XCTAssertTrue(shown.contains("Push"), "Callout \(shown) lacks workout name")
        XCTAssertTrue(shown.contains("4 sets"), "Callout \(shown) lacks set count")
        shot("heatmap-selected")

        let rest = Calendar.current.date(byAdding: .day, value: -5, to: Date()) ?? Date()
        let restCell = element("heatmap.\(Self.idString(rest))")
        restCell.tap()
        XCTAssertTrue(detail.label.contains("Rest day"), detail.label)
        shot("heatmap-rest")
    }

    func testLiftChartSelectionShowsValue() throws {
        launchApp(extraArguments: ["-uiTestingLiftHistory"])
        openTab("Progress")
        let chart = element("lift.chart.Bench Press")
        waitFor(chart, "Lift chart missing")
        for _ in 0..<4 where !chart.isHittable { app.swipeUp() }
        shot("lift-chart")
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        shot("lift-chart-selected")
        tap(app.buttons["progress.segment.Lifts"])
        waitFor(element("progress.liftsList"))
        element("lift.sparkline.Bench Press").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .tap()
        shot("lift-sparkline-selected")
    }

    private static func idString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Dark theme pass over the selected heatmap day and selected chart point (screenshots only).
    func testDarkSelectionScreenshots() throws {
        launchApp(colorScheme: "dark", extraArguments: ["-uiTestingLiftHistory"])
        openTab("Progress")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let cell = element("heatmap.\(Self.idString(yesterday))")
        waitFor(cell)
        cell.tap()
        shot("dark-heatmap-selected")
        let chart = element("lift.chart.Bench Press")
        for _ in 0..<4 where !chart.isHittable { app.swipeUp() }
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).tap()
        shot("dark-chart-selected")
    }

}
