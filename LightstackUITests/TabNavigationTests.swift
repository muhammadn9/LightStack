import XCTest

/// Regression: build 26 crashed (UINavigationBar layout assertion) when the owner
/// swiped from History to Profile and then tapped Settings.
final class TabNavigationTests: LightstackUITestCase {

    func testSwipeToProfileThenTapSettingsDoesNotCrash() {
        launchApp()
        openTab("History")
        app.swipeLeft()
        XCTAssertTrue(app.buttons["tab.Profile"].waitForExistence(timeout: timeout))
        tap(app.buttons["tab.Settings"])
        shot("settings-after-swipe")

        // Still running, still on Settings, and the screen is usable.
        XCTAssertEqual(app.state, .runningForeground, "App crashed switching to Settings")
        XCTAssertTrue(app.staticTexts["Rest Timer Alerts"].waitForExistence(timeout: timeout))
    }

    func testRapidTabSwitchingDoesNotCrash() {
        launchApp()
        for title in ["History", "Profile", "Settings", "History", "Settings", "Profile", "Settings", "Today", "Settings"] {
            app.buttons["tab.\(title)"].tap()
        }
        app.swipeRight()
        app.swipeRight()
        app.buttons["tab.Settings"].tap()
        XCTAssertEqual(app.state, .runningForeground, "App crashed during rapid tab switching")
        XCTAssertTrue(app.staticTexts["Rest Timer Alerts"].waitForExistence(timeout: timeout))
    }

    /// Settings must have a readable heading in Light mode (it rendered white on white).
    func testSettingsInLightMode() {
        let application = XCUIApplication()
        application.launchArguments = ["-uiTesting", "-uiTestingReset", "-appColorScheme", "light"]
        application.launch()
        app = application
        openTab("Settings")
        shot("settings-light")
    }

    func testSettingsInDarkMode() {
        let application = XCUIApplication()
        application.launchArguments = ["-uiTesting", "-uiTestingReset", "-appColorScheme", "dark"]
        application.launch()
        app = application
        openTab("Settings")
        shot("settings-dark")
    }

    /// Owner's setup: theme switched while the app is running (bar already built).
    func testSwitchingToLightWhileOnSettings() {
        let application = XCUIApplication()
        application.launchArguments = ["-uiTesting", "-uiTestingReset", "-appColorScheme", "dark"]
        application.launch()
        app = application
        openTab("Settings")
        tap(app.buttons["Light"])
        shot("settings-switched-to-light")
        openTab("Profile")
        openTab("Settings")
        shot("settings-switched-to-light-revisited")
    }
}
