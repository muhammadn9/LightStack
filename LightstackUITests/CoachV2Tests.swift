import XCTest

/// Coach v2 UI: set roles and rest on the plan, the coach's review card, the in-session miss banner,
/// the post-workout review and the optional setup inputs.
final class CoachV2Tests: LightstackUITestCase {

    private let engineHistory = ["-uiTestingEngineHistory"]

    private func anyElement(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func scrollTo(_ element: XCUIElement) {
        var swipes = 0
        while !element.isHittable && swipes < 8 { app.swipeUp(); swipes += 1 }
    }

    private func openPlanPreview() {
        tap(app.buttons["chip.Push"])
        tap(app.buttons["generateButton"])
        waitFor(app.buttons["previewCancelButton"], "Plan preview did not appear")
    }

    // MARK: - Plan preview

    func testPlanShowsRolesRestAndCoachReview() throws {
        launchApp(extraArguments: engineHistory)
        openPlanPreview()

        let card = waitFor(anyElement("plan.coachReview"), "Coach's plan card missing")
        XCTAssertFalse(anyElement("plan.coachReview.verdict").exists, "The old Sound / Adjusted verdict is gone")
        XCTAssertFalse(anyElement("plan.coachReview.summary").label.isEmpty)
        let checks = waitFor(anyElement("plan.coachReview.checks"), "The checks line is missing")
        XCTAssertTrue(checks.label.hasPrefix("Checks: "), checks.label)
        XCTAssertTrue(checks.label.contains(" of 6 passed"), checks.label)
        shot("30-plan-top")
        _ = card

        var labels: [String] = []
        for row in 0..<8 {
            let el = anyElement("plan.setRow.0.\(row)")
            guard el.waitForExistence(timeout: row == 0 ? timeout : 1) else { break }
            labels.append(el.label)
        }
        XCTAssertTrue(labels.first?.hasPrefix("Warm-up") == true, "First row should be the warm-up: \(labels)")
        // The engine's structure for a lift with a log: warm-up, Set 1, one top set (and a back-off at higher energy).
        XCTAssertTrue(labels.contains { $0.hasPrefix("Set 1") }, "Set 1 missing: \(labels)")
        XCTAssertEqual(labels.filter { $0.hasPrefix("Top set") }.count, 1, "One top set expected: \(labels)")
        XCTAssertTrue(labels.allSatisfy { $0.contains("rest ") }, "Every row should show rest: \(labels)")

        // The pushdown has a known form issue: its cue shows under the rows.
        let cue = anyElement("plan.cue.2")
        scrollTo(cue)
        XCTAssertTrue(cue.waitForExistence(timeout: 5), "Form cue missing")
        shot("31-plan-roles-and-cue")
    }

    /// The plan shows the coach's decision per lift with its reason, the checks that ran, and no old labels.
    func testPlanShowsDecisionLabelsReasonsAndChecks() throws {
        launchApp(extraArguments: engineHistory)
        openPlanPreview()
        waitFor(anyElement("plan.coachReview"), "Coach's plan card missing")
        XCTAssertFalse(anyElement("plan.recencyWarning").exists, "The session was 3 days ago: no heads-up")
        XCTAssertEqual(anyElement("plan.source.0").label, "Swapped in for Bench Press")
        XCTAssertFalse(anyElement("plan.reason.0").label.isEmpty, "The lift's reason is shown")
        XCTAssertEqual(anyElement("plan.source.1").label, "Added")
        for text in ["Sound", "Adjusted", "Safety rail", "Set by the coach", "Review (sound)"] {
            let match = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text))
            XCTAssertEqual(match.count, 0, "Old label on screen: \(text)")
        }
        shot("32-plan-decisions-top")
        scrollTo(anyElement("plan.source.1"))
        shot("33-plan-decisions-labels")
    }

    /// A session 5 hours ago: the calm heads-up shows, and the lift is held, not pushed.
    func testPlanShowsTheRecencyHeadsUpWhenTheMusclesWereTrainedHoursAgo() throws {
        launchApp(extraArguments: engineHistory + ["-uiTestingRecentHours", "5"])
        openPlanPreview()
        let banner = waitFor(anyElement("plan.recencyWarning"), "Recency heads-up missing")
        XCTAssertTrue(banner.label.contains("You trained chest"), banner.label)
        XCTAssertTrue(banner.label.contains("about 5 hours ago, so today's targets are held or lighter."), banner.label)
        // The 5-hour-old session is the draft, so bench is the draft lift itself.
        XCTAssertEqual(anyElement("plan.source.0").label, "As planned")
        shot("34-plan-recency-warning")
    }

    // MARK: - In-session miss banner

    func testMissBannerAppliesAndRecordsReason() throws {
        launchApp(extraArguments: engineHistory)
        tap(app.buttons["chip.Push"])
        tap(app.buttons["generateButton"])
        let start = waitFor(app.buttons["startWorkoutButton"], "Plan did not appear")
        var attempts = 0
        while !weightField().exists && attempts < 3 {
            var swipes = 0
            while !start.isHittable && swipes < 8 { app.swipeUp(); swipes += 1 }
            if start.exists { start.tap() }
            _ = weightField().waitForExistence(timeout: 15)
            attempts += 1
        }
        waitFor(weightField(), "Active workout did not start")

        // The rows carry role captions and the prescribed rest.
        let caption = waitFor(anyElement("session.setRole.0.0"), "Role caption missing")
        XCTAssertTrue(caption.label.contains("rest"), "Caption should show rest: \(caption.label)")

        // Log the warm-up as prescribed; the next pending row is Set 1.
        tap(app.buttons["setRow.0.0.log"])
        waitFor(app.staticTexts["loggedSet.0.0.weight"], "Warm-up was not logged")
        XCTAssertFalse(anyElement("session.missBanner.0").exists, "Banner must not show for sets that hit target")
        XCTAssertTrue(anyElement("session.setRole.0.1").label.hasPrefix("Set 1"), "Row 2 should be Set 1: \(anyElement("session.setRole.0.1").label)")

        replaceText(in: repsField(), with: "1")
        dismissKeyboardIfNeeded()
        tap(app.buttons["setRow.0.0.log"])

        let banner = waitFor(anyElement("session.missBanner.0"), "Miss banner did not appear")
        XCTAssertTrue(anyElement("session.missBanner.0.message").label.contains("fell short"))
        shot("40-miss-banner")
        _ = banner

        let before = weightField().value as? String
        tap(app.buttons["session.missBanner.0.apply"])
        waitFor(anyElement("session.missBanner.0.applied"), "Applied confirmation missing")
        let after = weightField().value as? String
        XCTAssertNotNil(before)
        XCTAssertNotEqual(before, after, "Back-off prefill should change after Apply")
        if let b = Double(before ?? ""), let a = Double(after ?? "") { XCTAssertLessThan(a, b) }

        tap(app.buttons["session.missReason.0.lowEnergy"])
        let status = waitFor(anyElement("session.missReason.0.status"))
        XCTAssertTrue(status.label.contains("Low energy"), "Reason not recorded: \(status.label)")
        shot("41-miss-banner-applied")
    }

    // MARK: - Lowered weight

    func testLoweringTheWeightAsksWhy() throws {
        launchApp(extraArguments: engineHistory)
        generateAndStartPushWorkout()

        replaceText(in: weightField(), with: "50")
        replaceText(in: repsField(), with: "15")
        dismissKeyboardIfNeeded()
        tap(app.buttons["setRow.0.0.log"])
        waitFor(app.staticTexts["loggedSet.0.0.weight"], "Set 1 was not logged")

        replaceText(in: weightField(), with: "47.5")
        replaceText(in: repsField(), with: "11")
        dismissKeyboardIfNeeded()
        tap(app.buttons["setRow.0.0.log"])
        waitFor(app.staticTexts["loggedSet.0.1.weight"], "Set 2 was not logged")

        waitFor(anyElement("coach.dropReason"), "Lowered-weight question did not appear")
        XCTAssertTrue(anyElement("coach.dropReason.message").label.contains("47.5"))
        shot("42-drop-reason")
        tap(app.buttons["coach.dropReason.plannedDrop"])
        let status = waitFor(anyElement("coach.dropReason.status"))
        XCTAssertTrue(status.label.contains("Planned"), "Reason not recorded: \(status.label)")
    }

    private func logDroppedSet() {
        replaceText(in: weightField(), with: "50")
        replaceText(in: repsField(), with: "15")
        dismissKeyboardIfNeeded()
        tap(app.buttons["setRow.0.0.log"])
        waitFor(app.staticTexts["loggedSet.0.0.weight"], "Set 1 was not logged")

        replaceText(in: weightField(), with: "47.5")
        replaceText(in: repsField(), with: "11")
        dismissKeyboardIfNeeded()
        tap(app.buttons["setRow.0.0.log"])
        waitFor(app.staticTexts["loggedSet.0.1.weight"], "Set 2 was not logged")
        waitFor(anyElement("coach.dropReason"), "Lowered-weight question did not appear")
    }

    func testDismissingLoweredWeightAfterReasonLetsYouPickAgain() throws {
        launchApp(extraArguments: engineHistory)
        generateAndStartPushWorkout()
        logDroppedSet()

        tap(app.buttons["coach.dropReason.plannedDrop"])
        let status = waitFor(anyElement("coach.dropReason.status"))
        XCTAssertTrue(status.label.contains("Planned"), "Reason not recorded: \(status.label)")

        tap(app.buttons["coach.dropReason.dismiss"])
        waitFor(app.buttons["coach.dropReason.plannedDrop"], "Reason chips did not come back after X")
        XCTAssertFalse(anyElement("coach.dropReason.status").exists, "Noted label should be gone after X")

        tap(app.buttons["coach.dropReason.lowEnergy"])
        let again = waitFor(anyElement("coach.dropReason.status"))
        XCTAssertTrue(again.label.contains("Low energy"), "New reason not recorded: \(again.label)")
        shot("43-drop-reason-rechosen")
    }

    func testDismissingLoweredWeightWithoutReasonHidesBanner() throws {
        launchApp(extraArguments: engineHistory)
        generateAndStartPushWorkout()
        logDroppedSet()

        tap(app.buttons["coach.dropReason.dismiss"])
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: anyElement("coach.dropReason"))
        waitForExpectations(timeout: 5)
    }

    // MARK: - Post-workout review

    func testPostWorkoutReviewShowsNextTargetsAndPersistsInHistory() throws {
        launchApp(extraArguments: engineHistory)
        generateAndStartPushWorkout()
        for n in 0..<2 {
            tap(app.buttons["setRow.0.0.log"])
            waitFor(app.staticTexts["loggedSet.0.\(n).weight"], "Set \(n + 1) was not logged")
        }
        finishWorkoutConfirmed()

        waitFor(app.buttons["saveWorkoutButton"], "Post-workout screen did not appear")
        let card = waitFor(anyElement("review.card"), "Review card missing")
        _ = card
        let targets = waitFor(anyElement("review.nextTargets"), "Next session targets missing")
        _ = targets
        shot("50-post-workout-review")

        let save = app.buttons["saveWorkoutButton"]
        let chip = app.buttons["chip.Push"]
        for _ in 0..<3 where !chip.exists {
            scrollTo(save)
            if save.exists && save.isHittable { save.tap() }
            if chip.waitForExistence(timeout: 10) { break }
        }
        waitFor(chip, "Did not return to setup after saving")

        openTab("History")
        let rows = app.buttons.matching(identifier: "historyRow.Push")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: timeout))
        rows.element(boundBy: 0).tap()
        let detailCard = anyElement("review.card")
        scrollTo(detailCard)
        XCTAssertTrue(detailCard.waitForExistence(timeout: 10), "History detail should show the structured review")
        XCTAssertTrue(anyElement("review.nextTargets").exists)
        shot("51-history-review")
    }

    // MARK: - Setup

    func testSetupMoreOptionsExistAndGenerateStillWorks() throws {
        launchApp()
        let more = waitFor(app.buttons["setup.moreOptions"], "More options missing")
        XCTAssertFalse(anyElement("setup.constraints").exists, "Collapsed by default")
        scrollTo(more)
        more.tap()
        let constraints = waitFor(anyElement("setup.constraints"), "Constraints field missing")
        waitFor(anyElement("setup.focus"), "Focus control missing")
        scrollTo(constraints)
        shot("60-setup-more-options")
        type("fasted, knee tweak", into: constraints)
        dismissKeyboardIfNeeded()
        let strength = app.segmentedControls["setup.focus"].buttons["Strength"]
        if strength.exists { strength.tap() }
        openPlanPreviewAfterOptions()
        shot("61-plan-after-options")
    }

    private func openPlanPreviewAfterOptions() {
        // Scroll back up to the chips, pick Push and generate.
        for _ in 0..<8 where !app.buttons["chip.Push"].isHittable { app.swipeDown() }
        tap(app.buttons["chip.Push"])
        tap(app.buttons["generateButton"])
        waitFor(app.buttons["previewCancelButton"], "Plan preview did not appear")
    }
}
