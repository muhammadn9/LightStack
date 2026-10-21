import XCTest

/// Swap an exercise on the generated-plan preview, and back out of the preview.
final class PlanPreviewTests: LightstackUITestCase {

    func testSwapToHistoryBackedExerciseFillsRowsOnStart() throws {
        launchApp(extraArguments: ["-uiTestingLiftHistory"])
        tap(app.buttons["chip.Push"])
        tap(app.buttons["generateButton"])
        waitFor(app.buttons["previewCancelButton"], "Plan preview did not appear")
        shot("10-preview")

        let swap = waitFor(app.buttons["previewSwap.1"])
        var swipes = 0
        while !swap.isHittable && swipes < 4 { app.swipeUp(); swipes += 1 }
        swap.tap()
        waitFor(app.staticTexts["swapSheetTitle"], "Swap sheet missing")
        waitFor(app.buttons["swapRemoveButton"])
        waitFor(app.buttons["swapSearchButton"])
        let option = waitFor(app.buttons["swapOption.Bench Press"], "History-backed suggestion missing")
        shot("11-swap-sheet")
        option.tap()

        waitFor(app.buttons["previewCancelButton"])
        XCTAssertFalse(app.staticTexts["Incline Dumbbell Press"].exists, "Old exercise should be replaced")
        shot("12-preview-after-swap")

        let start = waitFor(app.buttons["startWorkoutButton"])
        let firstRow = weightField(exercise: 1, row: 0)
        for _ in 0..<3 where !app.staticTexts["1 of 3"].exists {
            var n = 0
            while !start.isHittable && n < 5 { app.swipeUp(); n += 1 }
            if start.exists { start.tap() }
            if app.staticTexts["1 of 3"].waitForExistence(timeout: 8) { break }
        }
        waitFor(app.staticTexts["1 of 3"])
        app.swipeLeft()
        waitFor(app.staticTexts["2 of 3"])
        waitFor(firstRow, "Swapped exercise rows missing")
        shot("13-started-prefilled")
        XCTAssertEqual(firstRow.value as? String, "135")
        XCTAssertEqual(repsField(exercise: 1, row: 0).value as? String, "8")
        XCTAssertEqual(repsField(exercise: 1, row: 1).value as? String, "7")
        XCTAssertFalse(weightField(exercise: 1, row: 2).exists, "Row count should match last session (2 sets)")
    }

    func testSetRowsShowFullWeightOnOneLine() throws {
        launchApp()
        tap(app.buttons["chip.Push"])
        tap(app.buttons["generateButton"])
        let row = app.descendants(matching: .any).matching(identifier: "plan.setRow.2.0").firstMatch
        var swipes = 0
        while !row.waitForExistence(timeout: 2) && swipes < 5 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(row.exists, "Set row missing")
        shot("16-plan-set-rows")
        XCTAssertEqual(row.label, "Set 1 185 lb × 8 @ RIR 4")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "plan.setRow.2.2").firstMatch.label, "Set 3 195 lb × 6 @ RIR 2")
    }

    func testCancelAndDiscardReturnsToSetupLeavingHistoryUnchanged() throws {
        launchApp()
        tap(app.buttons["chip.Push"])
        tap(app.buttons["generateButton"])
        tap(app.buttons["previewCancelButton"])
        let alert = app.alerts["Discard this workout plan?"]
        waitFor(alert, "Discard confirmation missing")
        shot("14-discard-alert")

        // Keep leaves the preview alone.
        tap(alert.buttons["previewKeepButton"].firstMatch)
        waitFor(app.buttons["startWorkoutButton"])
        tap(app.buttons["previewCancelButton"])
        tap(app.alerts["Discard this workout plan?"].buttons["previewDiscardConfirmButton"].firstMatch)

        waitFor(app.buttons["chip.Push"], "Did not return to setup after discarding")
        openTab("History")
        let rows = app.buttons.matching(identifier: "historyRow.Push")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: timeout))
        XCTAssertEqual(rows.count, 1, "Only the seeded Push workout should exist")
        shot("15-history-unchanged")
    }
}
