import XCTest

/// End-to-end checks of the offline sync queue against a fake remote (no network, no Supabase).
final class OfflineSyncEndToEndTests: LightstackUITestCase {

    private let alertTitle = "Some changes haven't backed up yet"
    private var status: XCUIElement { app.staticTexts["settings.syncQueue.status"] }

    // MARK: - Helpers

    private func tapSignOut() {
        let button = app.buttons["settings.signOutButton"]
        var swipes = 0
        while !(button.exists && button.isHittable) && swipes < 8 { app.swipeUp(); swipes += 1 }
        tap(button)
    }

    private func scrollToStatus() {
        var swipes = 0
        while !(status.exists && status.isHittable) && swipes < 8 { app.swipeUp(); swipes += 1 }
        waitFor(status)
    }

    /// Parses "Sync queue: N pending, M failed" from the debug row.
    private func counts() -> (pending: Int, failed: Int)? {
        scrollToStatus()
        let numbers = status.label.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }
        guard numbers.count == 2 else { return nil }
        return (numbers[0], numbers[1])
    }

    private func cycleForeground() {
        XCUIDevice.shared.press(.home)
        _ = app.wait(for: .runningBackground, timeout: 10)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    /// Polls the row until it reads 0 pending / 0 failed, re-triggering a foreground flush now and then
    /// (failed operations back off 10s+ before they are retried).
    private func waitForDrained(timeout: TimeInterval = 40) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var lastCycle = Date()
        while Date() < deadline {
            if let c = counts(), c.pending == 0, c.failed == 0 { return true }
            if Date().timeIntervalSince(lastCycle) > 12 {
                cycleForeground()
                lastCycle = Date()
            }
            Thread.sleep(forTimeInterval: 1)
        }
        return false
    }

    private func relaunch(_ args: [String]) {
        XCUIDevice.shared.press(.home)
        _ = app.wait(for: .runningBackground, timeout: 10)
        app.terminate()
        app.launchArguments = ["-uiTesting"] + args
        app.launch()
    }

    private func logSet(weight: String, reps: String) {
        replaceText(in: weightField(), with: weight)
        replaceText(in: repsField(), with: reps)
        dismissKeyboardIfNeeded()
        tap(app.buttons["setRow.0.0.log"])
    }

    // MARK: - Tests

    func testOfflineWorkoutQueuesThenUploadsOnForeground() {
        launchApp(extraArguments: ["-uiTestingFakeRemote", "offline"])
        generateAndStartPushWorkout()
        shot("01-active-workout")

        logSet(weight: "100", reps: "5")
        waitFor(app.staticTexts["loggedSet.0.0.weight"], "First set was not logged")
        logSet(weight: "100", reps: "4")
        waitFor(app.staticTexts["loggedSet.0.1.weight"], "Second set was not logged")
        shot("02-two-sets-logged")

        tap(app.buttons["finishWorkoutButton"])
        let save = waitFor(app.buttons["saveWorkoutButton"], "Post-workout screen did not appear")
        XCTAssertTrue(save.waitForHittable(timeout: timeout), "Save never became enabled")
        let chip = app.buttons["chip.Push"]
        for _ in 0..<3 where !chip.exists {
            if save.exists && save.isHittable { save.tap() }
            if chip.waitForExistence(timeout: 10) { break }
        }
        waitFor(chip, "Did not return to setup after saving")
        shot("03-saved")

        openSettings()
        guard let offline = counts() else { return XCTFail("Could not read sync row: \(status.label)") }
        shot("04-settings-offline")
        XCTAssertGreaterThan(offline.pending, 0, "Offline writes should be queued")
        XCTAssertEqual(offline.failed, 0)

        tapSignOut()
        let alert = waitFor(app.alerts[alertTitle])
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "\(offline.pending) change")).firstMatch.exists,
                      "Alert should state the pending count (\(offline.pending))")
        shot("05-signout-warning")
        tap(alert.buttons.matching(identifier: "Cancel").firstMatch)
        XCTAssertTrue(app.alerts[alertTitle].waitForNonExistence(timeout: 5))

        relaunch(["-uiTestingFakeRemote", "online"])
        openSettings()
        XCTAssertTrue(waitForDrained(), "Queue never drained after going online: \(status.label)")
        shot("06-settings-online-drained")

        tapSignOut()
        XCTAssertFalse(app.alerts[alertTitle].waitForExistence(timeout: 3), "No backup warning expected after upload")
        shot("07-signout-no-warning")
    }

    func testForegroundTriggersUpload() {
        launchApp(extraArguments: ["-uiTestingFakeRemote", "offline", "-uiTestingPendingSyncOps", "3"])
        openSettings()
        XCTAssertEqual(counts()?.pending, 3)
        shot("01-three-pending")

        relaunch(["-uiTestingFakeRemote", "online", "-uiTestingSkipLaunchFlush"])
        // Let the retry backoff from any earlier offline attempt expire.
        Thread.sleep(forTimeInterval: 12)
        openSettings()
        let before = counts()
        XCTAssertEqual(before?.pending, 3, "Launch flush must not have run")
        shot("02-still-pending")

        cycleForeground()
        XCTAssertTrue(waitForDrained(timeout: 20), "Foreground did not upload: \(status.label)")
        shot("03-drained-after-foreground")
    }

    func testOfflineStaysQueuedNotDropped() {
        launchApp(extraArguments: ["-uiTestingFakeRemote", "offline", "-uiTestingPendingSyncOps", "2"])
        openSettings()
        XCTAssertEqual(counts()?.pending, 2)
        for _ in 0..<6 {
            cycleForeground()
            Thread.sleep(forTimeInterval: 1)
        }
        guard let after = counts() else { return XCTFail("Could not read sync row") }
        shot("01-after-flushes")
        XCTAssertEqual(after.pending, 2, "Offline operations must stay queued")
        XCTAssertEqual(after.failed, 0, "Nothing may be dropped to the dead-letter list")
    }
}
