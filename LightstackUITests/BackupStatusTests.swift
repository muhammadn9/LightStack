import XCTest

/// The Settings backup-status row and the signed-out banner.
final class BackupStatusTests: LightstackUITestCase {

    /// The row sits below the fold of the lazy Settings list, so scroll to it before asserting on it.
    private func scrollToBackupRow() -> XCUIElement {
        let row = app.buttons["settings.backupStatus"]
        scrollUntilHittable(row)
        return waitFor(row)
    }

    func testSettingsShowsBackupStatusRow() {
        launchApp()
        openSettings()
        let row = scrollToBackupRow()
        XCTAssertTrue(row.label.contains("backed up") || row.label.contains("waiting") || row.label.contains("Backing up"),
                      "Unexpected status text: \(row.label)")
        XCTAssertFalse(app.otherElements["sessionExpired.banner"].exists, "No banner for a healthy session")
        shot("backup-status-row")
    }

    func testPendingChangesShowInRow() {
        launchApp(extraArguments: ["-uiTestingPendingSyncOps", "2"])
        openSettings()
        let row = scrollToBackupRow()
        let predicate = NSPredicate(format: "label CONTAINS %@", "2 changes waiting")
        expectation(for: predicate, evaluatedWith: row)
        waitForExpectations(timeout: 10)
    }

    func testExpiredSessionShowsBannerAndSignedOutRow() {
        launchApp(extraArguments: ["-uiTestingExpiredSession"])
        let banner = waitFor(app.otherElements["sessionExpired.banner"])
        XCTAssertTrue(banner.exists)
        XCTAssertTrue(app.buttons["sessionExpired.signIn"].exists)
        shot("session-expired-banner")

        openSettings()
        let row = scrollToBackupRow()
        XCTAssertTrue(row.label.contains("Signed out"), "Row says: \(row.label)")
    }
}
