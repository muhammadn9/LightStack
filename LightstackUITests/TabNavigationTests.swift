import XCTest

/// Regression: build 26 crashed (UINavigationBar layout assertion) when moving
/// between tabs and Settings. Settings now lives behind the gear in Profile.
final class TabNavigationTests: LightstackUITestCase {

    func testProfileGearOpensSettingsDoesNotCrash() {
        launchApp()
        openTab("History")
        openSettings()
        shot("settings-after-history")

        XCTAssertEqual(app.state, .runningForeground, "App crashed opening Settings")
        XCTAssertTrue(app.staticTexts["Rest Timer Alerts"].exists)
    }

    func testRapidTabSwitchingDoesNotCrash() {
        launchApp()
        for title in ["History", "Progress", "Profile", "Today", "Profile", "History", "Progress", "Today", "Profile"] {
            app.tabBars.buttons[title].tap()
        }
        tap(app.buttons["profile.settings"])
        app.tabBars.buttons["Today"].tap()
        app.tabBars.buttons["Profile"].tap()
        XCTAssertEqual(app.state, .runningForeground, "App crashed during rapid tab switching")
        XCTAssertTrue(app.tabBars.buttons["Profile"].exists)
    }

    /// Settings must have a readable heading in Light mode (it rendered white on white).
    func testSettingsInLightMode() {
        let application = XCUIApplication()
        application.launchArguments = ["-uiTesting", "-uiTestingReset", "-appColorScheme", "light"]
        application.launch()
        app = application
        shot("profile-light")
        openSettings()
        shot("settings-light")
    }

    func testSettingsInDarkMode() {
        let application = XCUIApplication()
        application.launchArguments = ["-uiTesting", "-uiTestingReset", "-appColorScheme", "dark"]
        application.launch()
        app = application
        shot("profile-dark")
        openSettings()
        shot("settings-dark")
    }

    /// Owner's setup: theme switched while the app is running (bar already built).
    func testSwitchingToLightWhileOnSettings() {
        let application = XCUIApplication()
        application.launchArguments = ["-uiTesting", "-uiTestingReset", "-appColorScheme", "dark"]
        application.launch()
        app = application
        openSettings()
        tap(app.buttons["Light"])
        shot("settings-switched-to-light")
        app.navigationBars.buttons.firstMatch.tap()
        openTab("History")
        openSettings()
        shot("settings-switched-to-light-revisited")
    }
}
