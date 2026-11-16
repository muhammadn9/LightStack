import XCTest

/// A local store that cannot be opened must not crash the app.
final class StoreRecoveryTests: LightstackUITestCase {

    func testCorruptStoreShowsOneTimeMessageInsteadOfCrashing() {
        launchApp(extraArguments: ["-uiTestingCorruptStore"], waitForMainUI: false)
        let alert = waitFor(app.alerts["Your data on this iPhone was set aside"], "Recovery message missing", timeout: 30)
        shot("store-recovery-message")
        tap(alert.buttons["OK"])
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground, "App must still be running")
    }
}
