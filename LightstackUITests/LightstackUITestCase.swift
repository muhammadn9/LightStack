import XCTest

/// Shared launch, waiting and screenshot helpers for the UI tests.
class LightstackUITestCase: XCTestCase {

    var app: XCUIApplication!
    let timeout: TimeInterval = 15

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Launch

    /// Launches the app in test mode. `reset` wipes and reseeds the test store first.
    func launchApp(reset: Bool = true) {
        let application = XCUIApplication()
        application.launchArguments = ["-uiTesting"] + (reset ? ["-uiTestingReset"] : [])
        application.launch()
        app = application
    }

    // MARK: - Screenshots

    func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Interaction

    @discardableResult
    func waitFor(_ element: XCUIElement, _ message: String? = nil, timeout: TimeInterval? = nil,
                 file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let found = element.waitForExistence(timeout: timeout ?? self.timeout)
        XCTAssertTrue(found, message ?? "Missing element: \(element)", file: file, line: line)
        return element
    }

    func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        waitFor(element, file: file, line: line).tap()
    }

    func dismissKeyboardIfNeeded() {
        // Each presentation root (app, sheets) carries its own pill, so several can exist.
        let pills = app.buttons.matching(identifier: "Dismiss keyboard")
        guard pills.firstMatch.waitForExistence(timeout: 2) else { return }
        if let pill = pills.allElementsBoundByIndex.last(where: { $0.isHittable }) {
            pill.tap()
        }
        XCTAssertTrue(pills.firstMatch.waitForNonExistence(timeout: 5), "Keyboard did not dismiss")
    }

    func type(_ text: String, into field: XCUIElement,
              file: StaticString = #filePath, line: UInt = #line) {
        focus(field, file: file, line: line)
        field.typeText(text)
    }

    /// Taps a field and waits until it really has keyboard focus.
    func focus(_ field: XCUIElement, atTrailingEdge: Bool = false,
               file: StaticString = #filePath, line: UInt = #line) {
        waitFor(field, file: file, line: line)
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        // The first tap can be swallowed while a screen is still settling, so retry once.
        for attempt in 0..<3 {
            if atTrailingEdge {
                field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
            } else {
                field.tap()
            }
            let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: focused, object: field)], timeout: 3)
            if result == .completed { return }
            if attempt == 2 {
                XCTFail("Field never got keyboard focus: \(field)", file: file, line: line)
            }
        }
    }

    /// Removes any existing text in a field, then types `text`.
    func replaceText(in field: XCUIElement, with text: String,
                     file: StaticString = #filePath, line: UInt = #line) {
        focus(field, atTrailingEdge: true, file: file, line: line)
        if let current = field.value as? String, !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
    }

    func openTab(_ title: String) {
        let tab = waitFor(app.tabBars.buttons[title])
        // A tap during the first render can be lost, so confirm the tab became selected.
        for _ in 0..<2 where !tab.isSelected {
            tab.tap()
            let selected = NSPredicate(format: "selected == true")
            _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: selected, object: tab)], timeout: 3)
        }
        // Native tab buttons do not always report `selected`; callers verify content.
    }

    /// Profile tab -> gear -> Settings.
    func openSettings() {
        openTab("Profile")
        tap(app.buttons["profile.settings"])
        waitFor(app.staticTexts["Rest Timer Alerts"])
    }

    // MARK: - Flows

    /// Today tab -> Push -> Generate -> Start. Ends on the first exercise page.
    func generateAndStartPushWorkout() {
        tap(app.buttons["chip.Push"])
        tap(app.buttons["generateButton"])
        // Start sits below the fold on the confirm screen; scroll to it and retry a lost tap.
        let start = waitFor(app.buttons["startWorkoutButton"])
        let firstRow = app.textFields["setRow.0.0.weight"]
        for _ in 0..<3 where !firstRow.exists {
            var swipes = 0
            while !start.isHittable && swipes < 4 { app.swipeUp(); swipes += 1 }
            if start.exists { start.tap() }
            if firstRow.waitForExistence(timeout: 8) { break }
        }
        waitFor(firstRow, "Active workout did not show the first set row")
    }

    func weightField(exercise: Int = 0, row: Int = 0) -> XCUIElement {
        app.textFields["setRow.\(exercise).\(row).weight"]
    }
    func repsField(exercise: Int = 0, row: Int = 0) -> XCUIElement {
        app.textFields["setRow.\(exercise).\(row).reps"]
    }
    func rirField(exercise: Int = 0, row: Int = 0) -> XCUIElement {
        app.textFields["setRow.\(exercise).\(row).rir"]
    }
}
