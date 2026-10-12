import XCTest

final class CoachChatTests: LightstackUITestCase {

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

        let field = app.textFields["Ask your coach..."]
        for _ in 0..<3 where !field.exists {
            app.buttons["Chat with coach"].tap()
            _ = field.waitForExistence(timeout: 5)
        }
        type("Can I go heavier bench today?", into: app.textFields["Ask your coach..."])
        // A tap while the keyboard is still settling can be lost; retry until it sends.
        let apply = app.buttons["Apply Changes"]
        for _ in 0..<3 where !apply.exists {
            app.buttons["chatSendButton"].tap()
            _ = apply.waitForExistence(timeout: 6)
        }
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

        let field = app.textFields["Ask your coach..."]
        for _ in 0..<3 where !field.exists {
            app.buttons["Chat with coach"].tap()
            _ = field.waitForExistence(timeout: 5)
        }
        type("remove Cable Triceps Pushdown", into: app.textFields["Ask your coach..."])
        let apply = app.buttons["Apply Changes"]
        for _ in 0..<3 where !apply.exists {
            app.buttons["chatSendButton"].tap()
            _ = apply.waitForExistence(timeout: 6)
        }
        XCTAssertTrue(apply.exists, "Confirmation sheet never appeared")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Sounds good'")).firstMatch.exists,
                       "The AI was called for a local command")
        shot("local-remove-confirmation")
        tap(apply)

        let removed = app.staticTexts["✓ Removed Cable Triceps Pushdown"]
        XCTAssertTrue(removed.waitForExistence(timeout: 5), "Removal was not confirmed in the chat")
        tap(app.buttons["Done"])
        XCTAssertFalse(app.staticTexts["Cable Triceps Pushdown"].waitForExistence(timeout: 2),
                       "Exercise is still in the workout")
    }
}
