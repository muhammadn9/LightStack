import XCTest

final class CoachChatTests: LightstackUITestCase {

    /// The growing (multi-line) chat field is exposed as a text view by SwiftUI.
    private var chatInput: XCUIElement {
        app.textFields["chatInputField"]
    }

    /// Owner bug: long text in the coach chat ran off the right edge on a single line,
    /// and the keyboard Done pill covered it. The field must wrap and stay on screen.
    func testLongChatMessageWrapsAndStaysOnScreen() throws {
        launchApp()
        generateAndStartPushWorkout()
        waitFor(app.staticTexts["Barbell Bench Press"])
        let field = chatInput
        tap(app.buttons["Chat with coach"], until: field)
        waitFor(field)
        let oneLineHeight = field.frame.height
        let long = String(repeating: "I want a heavier bench press today please. ", count: 6)
        type(long, into: field)
        shot("chat-long-message")
        let screen = app.windows.firstMatch.frame
        XCTAssertGreaterThan(field.frame.height, oneLineHeight + 10, "Field did not grow beyond one line")
        XCTAssertLessThanOrEqual(field.frame.maxX, screen.maxX, "Field runs off the right edge")
        XCTAssertGreaterThanOrEqual(field.frame.minX, screen.minX)
        let send = app.buttons["chatSendButton"]
        XCTAssertTrue(send.isHittable, "Send button is covered")
        XCTAssertLessThanOrEqual(send.frame.maxX, screen.maxX)
    }

    /// Owner bug: the coach proposed a change, Apply was tapped, and the workout
    /// didn't change. The coach names exercises loosely ("Bench Press" for
    /// "Barbell Bench Press"), and modified targets never reached the set rows.
    func testAppliedCoachChangeUpdatesTheSetRows() throws {
        launchApp()
        generateAndStartPushWorkout()
        waitFor(app.staticTexts["Barbell Bench Press"])
        let weight = app.textFields["setRow.0.0.weight"]
        waitFor(weight)
        XCTAssertEqual(weight.value as? String, "135")

        let field = chatInput
        tap(app.buttons["Chat with coach"], until: field)
        type("Can I go heavier bench today?", into: chatInput)
        // A tap while the keyboard is still settling can be lost; retry until it sends.
        let apply = app.buttons["Apply Changes"]
        tap(app.buttons["chatSendButton"], until: apply)
        tap(apply)
        shot("coach-change-applied")
        tap(app.buttons["Done"])

        waitFor(weight)
        let updated = NSPredicate(format: "value == '155'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: updated, object: weight)], timeout: 5),
                       .completed, "Bench weight is still \(weight.value ?? "nil") after applying the coach's change")
        XCTAssertEqual(app.textFields["setRow.0.0.reps"].value as? String, "10")
        shot("coach-change-on-rows")
    }

    /// "remove <exercise>" is handled on the phone: the confirmation sheet appears with a
    /// one-line reply and the fake AI (whose canned chat text is "Sounds good...") is never asked.
    func testRemoveCommandNeedsNoAI() throws {
        launchApp()
        generateAndStartPushWorkout()
        waitFor(app.staticTexts["Barbell Bench Press"])

        let field = chatInput
        tap(app.buttons["Chat with coach"], until: field)
        type("remove Cable Triceps Pushdown", into: chatInput)
        let apply = app.buttons["Apply Changes"]
        tap(app.buttons["chatSendButton"], until: apply)
        XCTAssertTrue(apply.exists, "Confirmation sheet never appeared")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Sounds good'")).firstMatch.exists,
                       "The AI was called for a local command")
        shot("local-remove-confirmation")
        tap(apply)

        let removed = app.staticTexts["✓ Removed Cable Triceps Pushdown"]
        XCTAssertTrue(removed.waitForExistence(timeout: 20), "Removal was not confirmed in the chat")
        tap(app.buttons["Done"])
        XCTAssertFalse(app.staticTexts["Cable Triceps Pushdown"].waitForExistence(timeout: 2),
                       "Exercise is still in the workout")
    }
}
