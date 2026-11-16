import XCTest

/// Progress > Overview / Lifts / Lift detail, on the seeded test data (plus the weekly Bench Press history).
final class ProgressLiftsTests: LightstackUITestCase {

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func openProgress(colorScheme: String? = nil) {
        launchApp(colorScheme: colorScheme, extraArguments: ["-uiTestingLiftHistory"])
        openTab("Progress")
        waitFor(app.buttons["progress.segment.overview"])
    }

    private func scrollTo(_ id: String) -> XCUIElement {
        let target = element(id)
        waitFor(target)
        return scrollUntilHittable(target, maxSwipes: 10)
    }

    private func openBenchDetail() {
        tap(app.buttons["progress.segment.lifts"])
        waitFor(element("progress.liftsList"))
        tap(element("progress.lift.Bench Press"))
        waitFor(app.staticTexts["liftDetail.title"])
    }

    func testLiftsListIsAToZSearchableAndOpensDetail() throws {
        openProgress()
        tap(app.buttons["progress.segment.lifts"])
        waitFor(element("progress.liftsList"))
        XCTAssertEqual(element("progress.lifts.count").label, "6 lifts, A to Z")
        shot("lifts-list")

        let names = ["Barbell Curl", "Bench Press", "Lat Pulldown", "Leg Press", "Overhead Press", "Skull Crusher"]
        var lastY = -CGFloat.greatestFiniteMagnitude
        for name in names {
            let row = element("progress.lift.\(name)")
            waitFor(row, "Row \(name) missing")
            XCTAssertGreaterThan(row.frame.minY, lastY, "\(name) is out of A to Z order")
            lastY = row.frame.minY
        }
        // Row text: muscle group, session count, current est. 1RM.
        let bench = element("progress.lift.Bench Press")
        XCTAssertTrue(bench.label.contains("Chest"), bench.label)
        XCTAssertTrue(bench.label.contains("sessions"), bench.label)
        XCTAssertTrue(bench.label.contains("lb"), bench.label)

        let search = app.textFields["progress.lifts.search"]
        tap(search)
        search.typeText("pull")
        waitFor(element("progress.lift.Lat Pulldown"))
        XCTAssertEqual(element("progress.lifts.count").label, "1 lift, A to Z")
        XCTAssertFalse(element("progress.lift.Bench Press").exists)
        shot("lifts-search")
        search.clearAndType("zzz")
        waitFor(element("progress.lifts.noMatch"))
        search.clearAndType("")
        dismissKeyboardIfNeeded()

        waitFor(element("progress.lift.Bench Press"))
        tap(element("progress.lift.Bench Press"))
        let title = waitFor(app.staticTexts["liftDetail.title"])
        XCTAssertEqual(title.label, "Bench Press")
        XCTAssertTrue(element("liftDetail.subtitle").label.contains("Chest"))
        waitFor(element("liftDetail.tile.e1rm"))
        waitFor(element("liftDetail.tile.best"))
        waitFor(element("liftDetail.tile.heaviest"))
        shot("lift-detail-est")
        tap(app.buttons["liftDetail.metric.top"])
        shot("lift-detail-top")
        tap(app.buttons["liftDetail.metric.volume"])
        shot("lift-detail-volume")
        tap(app.buttons["liftDetail.metric.est"])

        let chart = element("liftDetail.chart")
        waitFor(chart)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        // The callout is drawn inside the chart and is not exposed to accessibility; the screenshot shows it.
        shot("lift-detail-selected")

        let first = scrollTo("liftDetail.session.0")
        XCTAssertTrue(first.label.contains("Push"), first.label)
        XCTAssertTrue(first.label.contains("135"), first.label)
        shot("lift-detail-sessions")
        // Rows open the workout's history detail; back returns to the lift.
        first.tap()
        waitFor(app.navigationBars["Push"], "Workout detail did not open")
        shot("lift-detail-workout")
        app.navigationBars.buttons.firstMatch.tap()
        waitFor(app.staticTexts["liftDetail.title"])
        // System back button returns to the list.
        app.navigationBars.buttons.firstMatch.tap()
        waitFor(element("progress.liftsList"))
    }

    func testOverviewShowsEquipmentAndLinksToLifts() throws {
        openProgress()
        shot("overview-top")
        _ = scrollTo("progress.trends")
        let open = scrollTo("progress.trendOpen.Bench Press")
        shot("overview-trends")
        open.tap()
        XCTAssertEqual(waitFor(app.staticTexts["liftDetail.title"]).label, "Bench Press")
        app.navigationBars.buttons.firstMatch.tap()

        _ = scrollTo("progress.equipmentCard")
        shot("overview-equipment")
        let seeAll = scrollTo("progress.seeAllLifts")
        seeAll.tap()
        waitFor(element("progress.liftsList"), "See all lifts did not switch to Lifts")
    }

    func testLastSegmentIsRemembered() throws {
        openProgress()
        tap(app.buttons["progress.segment.lifts"])
        waitFor(element("progress.liftsList"))
        app.terminate()
        launchApp(reset: false, extraArguments: ["-uiTestingLiftHistory"])
        openTab("Progress")
        waitFor(element("progress.liftsList"), "Lifts segment was not remembered")
        tap(app.buttons["progress.segment.overview"])
        waitFor(element("progress.streak"))
    }

    func testScreenshotsInLightAndDark() throws {
        for scheme in ["light", "dark"] {
            if app != nil { app.terminate() }
            openProgress(colorScheme: scheme)
            waitFor(element("progress.streak"))
            shot("\(scheme)-overview")
            _ = scrollTo("progress.seeAllLifts")
            shot("\(scheme)-overview-trends")
            _ = scrollTo("progress.equipmentCard")
            app.swipeUp()
            shot("\(scheme)-overview-equipment")
            app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown()
            openBenchDetail()
            shot("\(scheme)-lift-detail")
            app.navigationBars.buttons.firstMatch.tap()
            waitFor(element("progress.liftsList"))
            shot("\(scheme)-lifts")
        }
    }
}

private extension XCUIElement {
    /// Replaces the field's text (the helpers in the base class only append).
    func clearAndType(_ text: String) {
        tap()
        if let current = value as? String, !current.isEmpty, current != "Search your lifts" {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        if !text.isEmpty { typeText(text) }
    }
}
