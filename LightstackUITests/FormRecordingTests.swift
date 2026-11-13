import XCTest

/// Record Form end to end on the simulator, with the synthetic pose source standing in for the camera.
final class FormRecordingTests: LightstackUITestCase {

    func testRecordFormCountsRepsAndShowsFindings() throws {
        launchApp()
        generateAndStartPushWorkout()
        waitFor(app.staticTexts["1 of 3"])

        // The menu can fail to open on a lost tap, so retry until the capture screen is up.
        let start = app.buttons["formCapture.start"]
        for _ in 0..<3 where !start.exists {
            tap(app.buttons["moreActionsButton"])
            let item = app.buttons["recordFormButton"]
            if item.waitForExistence(timeout: 8) { item.tap() }
            _ = start.waitForExistence(timeout: 12)
        }
        waitFor(start, "Capture screen did not open")
        waitFor(app.descendants(matching: .any)["formCapture.setupStatus"], "Setup status card missing")
        shot("01-setup")

        tap(start)
        waitFor(app.descendants(matching: .any)["formCapture.countdown"], "Countdown did not start")

        let repCount = waitFor(app.staticTexts["formCapture.repCount"], "Recording screen did not appear", timeout: 30)
        shot("02-recording-start")
        let reachedThree = NSPredicate { _, _ in (Int(repCount.label) ?? 0) >= 3 }
        let wait = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: reachedThree, object: nil)], timeout: 40)
        XCTAssertEqual(wait, .completed, "Live rep count never reached 3 (showing \(repCount.label))")
        shot("03-recording")

        tap(app.buttons["formCapture.done"])

        let results = waitFor(app.staticTexts["formResults.repCount"], "Results did not appear", timeout: 30)
        XCTAssertGreaterThanOrEqual(Int(results.label) ?? 0, 3, "Results rep count: \(results.label)")
        let findings = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'formResults.finding.'"))
        XCTAssertGreaterThanOrEqual(findings.count, 1, "No findings shown")
        shot("04-results")

        // Coach feedback (canned by the UI-test fake AI).
        let verdict = app.staticTexts["formResults.verdict"]
        waitFor(verdict, "Coach verdict did not appear", timeout: 20)
        XCTAssertTrue(verdict.label.contains("Steady set"), "Verdict: \(verdict.label)")
        let fixes = ["formResults.fix.0", "formResults.fix.1"].map { app.descendants(matching: .any)[$0] }
        for fix in fixes { waitFor(fix, "A fix card is missing") }
        XCTAssertFalse(app.descendants(matching: .any)["formResults.coachUnavailable"].exists)

        // Replay controls exist and respond.
        let playPause = app.buttons["formResults.playPause"]
        XCTAssertTrue(playPause.exists)
        XCTAssertTrue(app.buttons["formResults.speed"].exists)
        tap(app.buttons["formResults.speed"])
        tap(playPause)

        // Rep strip: at least 3 bars; tapping one and a fix card must not break the screen.
        let bars = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'formResults.rep.'"))
        XCTAssertGreaterThanOrEqual(bars.count, 3, "Rep strip should show a bar per rep")
        tap(app.buttons["formResults.rep.2"])
        tap(fixes[0])
        XCTAssertTrue(playPause.exists, "Results screen still up after seeking")
        shot("05-after-seek")

        // Measured section.
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<4 where !findings.firstMatch.isHittable { scroll.swipeUp() }
        shot("06-measured")

        // Record again returns to the capture setup screen.
        tap(app.buttons["formResults.recordAgain"])
        waitFor(app.buttons["formCapture.start"], "Record again did not reopen the capture screen", timeout: 20)
        waitFor(app.descendants(matching: .any)["formCapture.setupStatus"], "Setup status card missing after Record again")
        shot("07-record-again")
        tap(app.buttons["formCapture.close"])
        XCTAssertTrue(app.buttons["formCapture.start"].waitForNonExistence(timeout: 10))
    }
}
