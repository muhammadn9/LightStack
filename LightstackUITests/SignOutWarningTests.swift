import XCTest

/// The sign-out confirmation shown when changes haven't uploaded yet.
final class SignOutWarningTests: LightstackUITestCase {

    private let alertTitle = "Some changes haven't backed up yet"

    /// Sign Out sits at the bottom of a long list; scroll until it can be tapped.
    private func tapSignOut() {
        let button = app.buttons["settings.signOutButton"]
        var swipes = 0
        while !(button.exists && button.isHittable) && swipes < 8 { app.swipeUp(); swipes += 1 }
        tap(button)
    }

    func testSignOutWithPendingChangesWarnsAndCancelKeepsSession() {
        launchApp(extraArguments: ["-uiTestingPendingSyncOps", "2"])
        openSettings()
        tapSignOut()

        let alert = waitFor(app.alerts[alertTitle])
        shot("signout-warning")
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "2 changes are saved on this iPhone")).firstMatch.exists,
                      "Alert should state the pending count")

        tap(alert.buttons.matching(identifier: "Cancel").firstMatch)
        XCTAssertTrue(app.alerts[alertTitle].waitForNonExistence(timeout: 5))
        waitFor(app.buttons["settings.signOutButton"], "Settings should still be visible after Cancel")
        shot("signout-cancelled")
    }

    func testSignOutWithNothingPendingShowsNoWarning() {
        launchApp()
        openSettings()
        tapSignOut()

        // Give an alert time to (wrongly) appear; the test user's UI-test session ignores real sign-out.
        XCTAssertFalse(app.alerts[alertTitle].waitForExistence(timeout: 3), "No backup warning expected when nothing is pending")
        shot("signout-no-warning")
    }
}
