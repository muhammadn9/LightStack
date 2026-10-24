import XCTest

/// The lock screen / Dynamic Island UI itself can't be driven from XCUITest on the simulator;
/// this covers what the app owns: starting a workout with Live Activity support wired in
/// (the activity is skipped in test mode) and the Settings toggle.
final class LiveActivitySettingsTests: LightstackUITestCase {

    func testSettingsOffersLiveActivityToggleDuringAWorkout() throws {
        launchApp()
        generateAndStartPushWorkout()
        waitFor(app.buttons["finishWorkoutButton"], "Workout did not start")

        openSettings()
        let toggle = waitFor(app.switches["settings.liveActivityToggle"], "Live Activity toggle missing in Settings")
        XCTAssertEqual(toggle.value as? String, "1", "Live Activity should default to on")
        shot("settings-live-activity")
    }
}
