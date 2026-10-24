import XCTest

/// The Settings backup-status row and the signed-out banner.
final class BackupStatusTests: LightstackUITestCase {

    func testSettingsShowsBackupStatusRow() {
        launchApp()
        openSettings()
        let row = waitFor(app.buttons["settings.backupStatus"])
        XCTAssertTrue(row.label.contains("backed up") || row.label.contains("waiting") || row.label.contains("Backing up"),
                      "Unexpected status text: \(row.label)")
        XCTAssertFalse(app.otherElements["sessionExpired.banner"].exists, "No banner for a healthy session")
        shot("backup-status-row")
    }

    func testPendingChangesShowInRow() {
        launchApp(extraArguments: ["-uiTestingPendingSyncOps", "2"])
        openSettings()
        let row = waitFor(app.buttons["settings.backupStatus"])
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
        let row = waitFor(app.buttons["settings.backupStatus"])
        XCTAssertTrue(row.label.contains("Signed out"), "Row says: \(row.label)")
    }
}
