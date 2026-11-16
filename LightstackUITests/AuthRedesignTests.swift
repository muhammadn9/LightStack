import XCTest

/// Welcome, email, legal and first-run setup screens (signed-out and fresh-install states).
final class AuthRedesignTests: LightstackUITestCase {

    private func launchSignedOut(scheme: String? = nil) {
        launchApp(colorScheme: scheme, extraArguments: ["-uiTestingSignedOut"], waitForMainUI: false)
        waitFor(app.buttons["auth.email"], "Welcome screen missing")
    }

    func testWelcomeEmailAndLegal() {
        for scheme in ["light", "dark"] {
            if scheme == "dark" { app?.terminate() }
            launchSignedOut(scheme: scheme)
            XCTAssertTrue(app.staticTexts["Lift, eat, track. A coach that adapts as you progress."].exists)
            XCTAssertTrue(app.buttons["auth.google"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["auth.apple"].exists)
            shot("welcome-\(scheme)")

            tap(app.buttons["auth.terms"])
            waitFor(app.descendants(matching: .any)["legal.terms"])
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Effective date'")).firstMatch.waitForExistence(timeout: 5), "Terms text not bundled")
            shot("terms-\(scheme)")
            tap(app.buttons["legal.done"])
            tap(app.buttons["auth.privacy"])
            waitFor(app.descendants(matching: .any)["legal.privacy"])
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Effective date'")).firstMatch.waitForExistence(timeout: 5), "Privacy text not bundled")
            shot("privacy-\(scheme)")
            tap(app.buttons["legal.done"])

            tap(app.buttons["auth.email"])
            waitFor(app.textFields["auth.email.field"])
            XCTAssertTrue(app.buttons["auth.forgot"].exists)
            shot("email-signin-\(scheme)")
            app.segmentedControls["auth.mode"].buttons["Create account"].tap()
            XCTAssertFalse(app.buttons["auth.forgot"].exists)
            type("a@b.com", into: app.textFields["auth.email.field"])
            shot("email-create-keyboard-\(scheme)")
            XCTAssertTrue(app.secureTextFields["auth.password.field"].isHittable)
        }
    }

    func testForgotPasswordNeedsEmail() {
        launchSignedOut()
        tap(app.buttons["auth.email"])
        tap(app.buttons["auth.forgot"])
        waitFor(app.descendants(matching: .any)["auth.error"])
        shot("email-error")
    }

    func testFirstRunSetupSkipAndPreset() {
        launchApp(extraArguments: ["-uiTestingFreshInstall", "-uiTestingFakeRemote", "online"],
                  waitForMainUI: false)
        waitFor(app.buttons["onboarding.next"], "Setup did not appear", timeout: 40)
        shot("setup-1-about")
        tap(app.buttons["onboarding.next"])
        tap(app.buttons["onboarding.preset.upperLower"])
        shot("setup-2-split")
        tap(app.buttons["onboarding.preset.custom"])
        waitFor(app.textFields["onboarding.day.field"])
        shot("setup-2-custom")
        tap(app.buttons["onboarding.preset.ppl"])
        tap(app.buttons["onboarding.next"])
        shot("setup-3-equipment")
        tap(app.buttons["onboarding.back"])
        tap(app.buttons["onboarding.skip"])
        tap(app.buttons["onboarding.skip"])
        waitFor(app.tabBars.buttons["Today"], "Did not land on Today", timeout: 40)
    }

    func testSettingsLegalRows() {
        launchApp()
        openSettings()
        scrollUntilHittable(app.buttons["settings.privacy"])
        tap(app.buttons["settings.privacy"])
        waitFor(app.descendants(matching: .any)["legal.privacy"])
    }
}
