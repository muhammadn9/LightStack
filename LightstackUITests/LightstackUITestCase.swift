import XCTest

/// Shared launch, waiting and screenshot helpers for the UI tests.
class LightstackUITestCase: XCTestCase {

    var app: XCUIApplication!
    /// Generous: CI and a loaded host can make sheets and first renders slow. Waits return as soon as the condition holds.
    let timeout: TimeInterval = 30

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Launch

    /// Launches the app in test mode. `reset` wipes and reseeds the test store first.
    func launchApp(reset: Bool = true, colorScheme: String? = nil, extraArguments: [String] = [],
                   waitForMainUI: Bool = true) {
        let application = XCUIApplication()
        application.launchArguments = ["-uiTesting"] + (reset ? ["-uiTestingReset"] : [])
            + (colorScheme.map { ["-appColorScheme", $0] } ?? []) + extraArguments
        application.launch()
        app = application
        // Wait for the first screen so the first tap never lands on a still-launching UI.
        // Skipped by tests that must observe a transient launch screen (e.g. the restore screen).
        if waitForMainUI { _ = application.tabBars.firstMatch.waitForExistence(timeout: 45) }
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

    /// Waits until the element exists AND is hittable (not mid-animation, not covered by a
    /// presenting sheet), then taps it. Falls back to a plain tap if it never becomes hittable.
    func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        waitFor(element, file: file, line: line)
        waitUntilHittable(element)
        element.tap()
    }

    /// Condition-based wait until the element is on screen and has stopped moving (finished animating).
    /// Uses frames rather than `isHittable`, which records a test failure when the activation point is
    /// momentarily invalid mid-transition.
    @discardableResult
    func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var last = CGRect.null
        while Date() < deadline {
            if element.exists {
                let frame = element.frame
                if !frame.isEmpty, frame == last { return true }
                last = frame
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return false
    }

    /// Taps `trigger` (re-tapping if the tap was lost) until `target` appears.
    @discardableResult
    func tap(_ trigger: XCUIElement, until target: XCUIElement, attempts: Int = 3, perAttempt: TimeInterval = 10) -> Bool {
        for _ in 0..<attempts {
            if target.exists { return true }
            if trigger.waitForExistence(timeout: perAttempt) {
                waitUntilHittable(trigger)
                trigger.tap()
            }
            if target.waitForExistence(timeout: perAttempt) { return true }
        }
        return target.exists
    }

    /// Taps Finish Workout and confirms the "Finish workout?" alert.
    func finishWorkoutConfirmed(file: StaticString = #filePath, line: UInt = #line) {
        tap(app.buttons["finishWorkoutButton"], file: file, line: line)
        tap(app.alerts.buttons["confirmFinishWorkoutButton"].firstMatch, file: file, line: line)
    }

    func dismissKeyboardIfNeeded() {
        // Each presentation root (app, sheets) carries its own pill, so several can exist.
        let pills = app.buttons.matching(identifier: "Dismiss keyboard")
        guard pills.firstMatch.waitForExistence(timeout: 3) else { return }
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
        waitUntilHittable(field)
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        // The first tap can be swallowed while a screen is still settling, so retry once.
        for attempt in 0..<3 {
            if atTrailingEdge {
                field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
            } else {
                field.tap()
            }
            let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: focused, object: field)], timeout: 6)
            if result == .completed { return }
            // Let a half-finished keyboard/sheet animation settle before retrying.
            waitUntilHittable(field, timeout: 3)
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
        waitUntilHittable(tab)
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
        let generate = app.buttons["generateButton"]
        let startButton = app.buttons["startWorkoutButton"]
        // Generation runs through the fake AI; a lost tap on a still-settling screen is retried.
        tap(generate, until: startButton, attempts: 3, perAttempt: 30)
        // Start sits below the fold on the confirm screen; scroll to it and retry a lost tap.
        let start = waitFor(app.buttons["startWorkoutButton"], timeout: 60)
        let firstRow = app.textFields["setRow.0.0.weight"]
        for _ in 0..<3 where !firstRow.exists {
            var swipes = 0
            while !start.isHittable && swipes < 6 { app.swipeUp(); swipes += 1 }
            if waitUntilHittable(start, timeout: 5) { start.tap() }
            if firstRow.waitForExistence(timeout: 15) { break }
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
