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

        tap(app.buttons["formResults.done"])
        XCTAssertTrue(app.staticTexts["formResults.repCount"].waitForNonExistence(timeout: 10))
    }
}
