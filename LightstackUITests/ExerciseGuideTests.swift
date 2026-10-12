import XCTest

final class ExerciseGuideTests: LightstackUITestCase {

    func testFormGuideShowsHowToPhotosAndInstructions() throws {
        launchApp()
        generateAndStartPushWorkout()
        waitFor(app.staticTexts["Barbell Bench Press"])

        // A tap during the first render can be lost, so retry opening the menu item.
        let guideButton = app.buttons["Form guide"]
        for _ in 0..<3 where !app.staticTexts["howToHeader"].exists {
            tap(app.buttons["moreActionsButton"])
            if guideButton.waitForExistence(timeout: 3) { guideButton.tap() }
            _ = app.staticTexts["howToHeader"].waitForExistence(timeout: 6)
        }
        waitFor(app.staticTexts["howToHeader"], "How To section missing")
        // Identifiers may surface as other elements or static texts depending on grouping.
        let step = app.descendants(matching: .any).matching(identifier: "howToStep.0").firstMatch
        waitFor(step, "No instruction step shown")
        shot("form-guide-how-to")
    }
}
