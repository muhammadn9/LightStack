import XCTest

final class ProgressTests: LightstackUITestCase {

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// The seeded "Core Day" is dated today: 3 Lat Pulldown sets (back), 2 Leg Press sets (legs).
    /// Today shows the slim "This week" card with sets per muscle group; the equipment grid lives on Progress.
    func testTodayShowsThisWeekInsteadOfEquipment() throws {
        launchApp()
        waitFor(app.buttons["chip.Push"])
        waitFor(element("thisWeek.card"), "This week card missing on Today")
        waitFor(element("weekStrip"), "Week strip missing on Today")
        XCTAssertFalse(element("equipment.usedCount").exists, "The equipment grid is not on Today any more")
        XCTAssertFalse(app.staticTexts["Equipment Worked This Week"].exists)
        let back = waitFor(element("thisWeek.group.Back"))
        XCTAssertTrue(back.label.hasPrefix("Back, "), back.label)
        XCTAssertTrue(back.label.contains("sets"), "Core Day logged back sets today: \(back.label)")
        XCTAssertEqual(element("thisWeek.group.Core").label, "Core, not yet")
        shot("today-this-week")
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
        tap(app.buttons["progress.segment.lifts"])
        waitFor(element("progress.liftsList"))
        shot("progress-lifts")
        tap(app.buttons["progress.segment.overview"])
        let weeks = element("progress.equipmentWeeks")
        waitFor(weeks)
        scrollUntilHittable(weeks)
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
        tap(app.buttons["progress.segment.lifts"])
        waitFor(element("progress.liftsList"))
        shot("lifts-list-with-history")
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
