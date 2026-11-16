import XCTest

/// Production-hardening checks: the AI consent sheet, the Settings privacy controls and the AI failure screen.
/// (The Delete account sheet is covered by DeleteAccountSheetTests; nothing here confirms a deletion.)
final class HardeningChecksTests: LightstackUITestCase {

    private func anyElement(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// The consent sheet appears once on first launch without consent, and not again after Allow.
    func testConsentSheetAppearsOnceThenNeverAgain() throws {
        launchApp(extraArguments: ["-uiTestingNoAIConsent"])
        waitFor(anyElement("aiConsent.sheet"), "Consent sheet should appear on first launch")
        shot("consent-sheet-first-launch")
        tap(app.buttons["aiConsent.allow"])
        XCTAssertTrue(anyElement("aiConsent.sheet").waitForNonExistence(timeout: 10), "Sheet should close after Allow")
        shot("consent-sheet-after-allow")

        // Relaunch WITHOUT resetting: the stored answer must stop the sheet from coming back.
        app.terminate()
        launchApp(reset: false, extraArguments: ["-uiTestingNoAIConsent"])
        XCTAssertFalse(anyElement("aiConsent.sheet").waitForExistence(timeout: 5), "Consent sheet must not reappear after accepting")
        shot("consent-sheet-relaunch-none")
    }

    /// "Not now" is remembered too, and AI stays off until Settings turns it on.
    func testNotNowIsRememberedAndSettingsToggleEnablesAI() throws {
        launchApp(extraArguments: ["-uiTestingNoAIConsent"])
        waitFor(anyElement("aiConsent.sheet"))
        tap(app.buttons["aiConsent.notNow"])
        XCTAssertTrue(anyElement("aiConsent.sheet").waitForNonExistence(timeout: 10))

        openSettings()
        let toggle = app.switches["settings.aiConsentToggle"]
        for _ in 0..<8 where !(toggle.exists && toggle.isHittable) { app.swipeUp() }
        waitFor(toggle, "AI toggle missing")
        XCTAssertEqual(toggle.value as? String, "0", "AI must be off after Not now")
        shot("settings-ai-off-after-not-now")
    }

    /// Settings: the AI toggle exists and flips; the Privacy Policy row exists.
    func testSettingsAIToggleAndPrivacyPolicyRow() throws {
        launchApp()
        openSettings()
        let toggle = app.switches["settings.aiConsentToggle"]
        for _ in 0..<8 where !(toggle.exists && toggle.isHittable) { app.swipeUp() }
        waitFor(toggle, "AI toggle missing")
        let before = toggle.value as? String
        XCTAssertEqual(before, "1", "Test mode starts with consent granted")
        shot("settings-ai-toggle-on")

        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let off = NSPredicate(format: "value == %@", "0")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: off, object: toggle)], timeout: 5), .completed,
                       "Toggle should switch off")
        shot("settings-ai-toggle-off")

        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let on = NSPredicate(format: "value == %@", "1")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: on, object: toggle)], timeout: 5), .completed,
                       "Toggle should switch back on")

        let policy = anyElement("settings.privacy")
        for _ in 0..<5 where !policy.exists { app.swipeUp() }
        waitFor(policy, "Privacy Policy row missing")
        shot("settings-privacy-policy-row")
    }

    /// A forced AI failure no longer blocks building a workout: the engine's plan is shown ("engine only") and no
    /// error appears. (The Retry / Build manually screen, `planFailure.*`, is only for a plan that cannot be built at all.)
    func testAIFailureStillBuildsEnginePlan() throws {
        launchApp(extraArguments: ["-uiTestingAIFail"])
        tap(app.buttons["chip.Push"])
        tap(app.buttons["generateButton"])
        waitFor(app.staticTexts["Workout Ready"], "Plan preview should still open when the AI fails", timeout: 60)
        waitFor(anyElement("plan.coachReview.engineOnly"), "Plan should be marked engine only")
        XCTAssertFalse(app.alerts.firstMatch.exists, "No error alert expected")
        XCTAssertFalse(anyElement("planFailure.message").exists, "Failure screen must not show")
        shot("ai-failure-engine-plan")
    }
}
