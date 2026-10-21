import XCTest

/// Evidence on the plan, "What the coach saw", and per-exercise feedback.
final class CoachTrustTests: LightstackUITestCase {

    private let engineHistory = ["-uiTestingEngineHistory"]

    private func anyElement(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func scrollTo(_ element: XCUIElement) {
        var swipes = 0
        while !element.isHittable && swipes < 6 { app.swipeUp(); swipes += 1 }
    }

    private func openPlanPreview() {
        tap(app.buttons["chip.Push"])
        tap(app.buttons["generateButton"])
        waitFor(app.buttons["previewCancelButton"], "Plan preview did not appear")
    }

    func testPlanShowsEvidenceBadgeAndWarmupOnlyOnFirstCompound() throws {
        launchApp(extraArguments: engineHistory)
        openPlanPreview()

        let evidence = waitFor(anyElement("plan.evidence.0"), "Evidence line missing for the seeded Bench Press")
        XCTAssertTrue(evidence.label.contains("Last ("), "Evidence should start with the last session: \(evidence.label)")
        XCTAssertTrue(evidence.label.contains("185×6 @1"), "Last session sets missing: \(evidence.label)")
        XCTAssertTrue(evidence.label.contains("Best:"), "Best set missing: \(evidence.label)")
        XCTAssertEqual(anyElement("plan.source.0").label, "Calculated from your log")

        // No history for the pushdown: the badge says so and there is no "Last" line.
        XCTAssertEqual(anyElement("plan.source.2").label, "AI estimate · adjusted")
        XCTAssertFalse(anyElement("plan.evidence.2").exists)

        waitFor(anyElement("plan.warmup.0.0"), "Warm-up badge missing on the first compound")
        XCTAssertFalse(anyElement("plan.warmup.1.0").exists)
        XCTAssertFalse(anyElement("plan.warmup.2.0").exists)
        XCTAssertTrue(anyElement("plan.setRow.0.0").label.contains("warm-up"))

        scrollTo(anyElement("plan.source.0"))
        shot("20-plan-evidence")
    }

    func testPlanEvidenceInDarkMode() throws {
        launchApp(colorScheme: "dark", extraArguments: engineHistory)
        openPlanPreview()
        waitFor(anyElement("plan.evidence.0"))
        shot("21-plan-evidence-dark")
    }

    func testWhatTheCoachSawShowsTheMessage() throws {
        launchApp()
        openPlanPreview()
        tap(app.buttons["plan.coachSaw"])
        let message = waitFor(anyElement("coachSaw.userMessage"), "User message missing")
        XCTAssertFalse(message.label.isEmpty)
        waitFor(app.buttons["coachSaw.copyAll"])
        waitFor(anyElement("coachSaw.adjustments"))
        shot("22-coach-saw")
        tap(app.buttons["coachSaw.done"])
        waitFor(app.buttons["previewCancelButton"])
    }

    func testProfileOpensWhatTheCoachSawEmptyState() throws {
        launchApp()
        openTab("Profile")
        var swipes = 0
        let row = app.buttons["profile.coachSaw"]
        while !row.exists && swipes < 5 { app.swipeUp(); swipes += 1 }
        tap(row)
        waitFor(anyElement("coachSaw.empty"), "Empty state missing before any plan")
        XCTAssertTrue(app.staticTexts["Generate a plan to see what the coach used."].exists)
        shot("23-coach-saw-empty")
    }

    func testFeedbackIsOptionalSelectableAndPersists() throws {
        launchApp(extraArguments: engineHistory)
        generateAndStartPushWorkout()
        // Not offered until something is logged.
        XCTAssertFalse(app.buttons["feedback.0.hard"].exists)
        tap(app.buttons["setRow.0.0.log"])
        let hard = waitFor(app.buttons["feedback.0.hard"], "Feedback control missing after logging a set")
        waitFor(anyElement("workout.last.0"), "Last: line missing in the workout header")
        tap(hard)
        XCTAssertEqual(app.buttons["feedback.0.hard"].value as? String, "Selected")
        XCTAssertNotEqual(app.buttons["feedback.0.easy"].value as? String, "Selected")
        shot("24-feedback-selected")

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.terminate()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        let again = waitFor(app.buttons["feedback.0.hard"], "Feedback control missing after relaunch")
        XCTAssertEqual(again.value as? String, "Selected", "Choice should persist")
    }
}
