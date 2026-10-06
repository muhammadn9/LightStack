import XCTest

/// Captures screenshots of the DEBUG-only Design Lab mock screens.
final class DesignLabTests: XCTestCase {

    private func capture(_ variant: String, _ screen: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-designLab", "-designVariant", variant, "-designScreen", screen,
                               "-appColorScheme", "dark"]
        app.launch()
        let root = app.otherElements["designLab.root"]
        XCTAssertTrue(root.waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 1.0)
        attach("\(variant)-\(screen)")
        if screen != "workout" {
            app.swipeUp(velocity: .fast)
            Thread.sleep(forTimeInterval: 0.8)
            attach("\(variant)-\(screen)-2")
        }
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testATodayScreen() { capture("A", "today") }
    func testAStatsScreen() { capture("A", "stats") }
    func testAWorkoutScreen() { capture("A", "workout") }
    func testBTodayScreen() { capture("B", "today") }
    func testBStatsScreen() { capture("B", "stats") }
    func testBWorkoutScreen() { capture("B", "workout") }
}
