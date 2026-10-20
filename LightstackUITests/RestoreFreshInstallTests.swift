import XCTest

/// A new device or reinstall: no local data, but the account has history in the cloud
/// (a fake remote stands in for Supabase; nothing touches the network).
final class RestoreFreshInstallTests: LightstackUITestCase {

    private let freshInstallArguments = [
        "-uiTestingFreshInstall", "-uiTestingFakeRemote", "online",
        "-uiTestingRemoteSeed", "history", "-uiTestingRestoreDelay", "10"
    ]

    func testFreshInstallRestoresHistoryAndSkipsOnboarding() {
        // Don't wait for the tab bar here: the restore screen is transient and must be observed.
        launchApp(extraArguments: freshInstallArguments, waitForMainUI: false)

        // The restore screen replaces the onboarding decision while the account is checked.
        let restoring = app.descendants(matching: .any)["restoreProgressView"]
        waitFor(restoring, "Restore screen never appeared", timeout: 20)
        shot("01-restoring-your-history")
        XCTAssertFalse(app.staticTexts["Get Started"].exists, "Onboarding must not show before the cloud is checked")

        // Lands on the app, not on onboarding.
        waitFor(app.tabBars.buttons["Today"], "Did not land on the main tabs", timeout: 40)
        XCTAssertFalse(app.staticTexts["Get Started"].exists, "A restored profile must skip onboarding")
        shot("02-today-after-restore")

        openTab("History")
        waitFor(app.buttons["historyRow.Restored Push"], "Restored Push missing from History")
        XCTAssertTrue(app.buttons["historyRow.Restored Pull"].exists)
        XCTAssertTrue(app.buttons["historyRow.Restored Legs"].exists)
        XCTAssertFalse(app.buttons["historyRow.Ghost Workout"].exists, "A workout deleted on another device came back")
        XCTAssertFalse(app.buttons["historyRow.Empty Junk"].exists, "A workout with nothing in it was restored")
        shot("03-history-restored")
    }

    func testRestoredProfileIsUsedNotReplacedByOnboarding() {
        launchApp(extraArguments: freshInstallArguments)
        waitFor(app.tabBars.buttons["Today"], "Did not land on the main tabs", timeout: 40)
        openTab("Profile")
        // The seeded cloud profile (not an onboarding default) is what the Profile tab shows.
        waitFor(app.staticTexts["Restored Tester"], "Restored profile name missing")
        shot("04-profile-restored")
    }
}
