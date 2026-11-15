import XCTest

final class ExerciseGuideTests: LightstackUITestCase {

    func testFormGuideDark() throws { try runGuideFlow(scheme: "dark") }
    func testFormGuideLight() throws { try runGuideFlow(scheme: "light") }

    private func runGuideFlow(scheme: String) throws {
        launchApp(colorScheme: scheme)
        generateAndStartPushWorkout()
        waitFor(app.staticTexts["Barbell Bench Press"])

        // A tap during the first render can be lost, so retry opening the menu item.
        let stage = app.descendants(matching: .any)["formGuide.stage"]
        let guideButton = app.buttons["Form guide"]
        for _ in 0..<3 where !stage.exists {
            tap(app.buttons["moreActionsButton"])
            if guideButton.waitForExistence(timeout: 8) { guideButton.tap() }
            _ = stage.waitForExistence(timeout: 12)
        }
        waitFor(stage, "3D stage missing")
        shot("guide-\(scheme)-top")

        for preset in ["front", "threeQuarter", "back", "side"] {
            tap(app.buttons["formGuide.camera.\(preset)"])
            if preset == "front" { sleepBriefly(); shot("guide-\(scheme)-front") }
        }

        let phase = app.staticTexts["formGuide.phase"]
        waitFor(phase, "Phase label missing")
        tap(app.buttons["formGuide.playPause"])
        XCTAssertEqual(app.buttons["formGuide.playPause"].label, "Play", "Pause should flip the button to Play")
        let slider = app.sliders["formGuide.scrubber"]
        waitFor(slider, "Scrubber missing")
        slider.adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertEqual(app.buttons["formGuide.playPause"].label, "Play")
        tap(app.buttons["formGuide.speed"])
        XCTAssertEqual(app.buttons["formGuide.speed"].value as? String, "Half speed")

        let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'formGuide.muscle.'"))
        waitFor(chips.firstMatch, "Muscle chips missing")
        tap(chips.firstMatch)
        XCTAssertTrue(chips.firstMatch.isSelected)
        tap(chips.firstMatch)
        XCTAssertFalse(chips.firstMatch.isSelected)

        for id in ["formGuide.setup", "formGuide.perform", "formGuide.avoid"] {
            let card = app.descendants(matching: .any)[id]
            for _ in 0..<6 where !card.exists || !card.isHittable { app.swipeUp() }
            waitFor(card, "\(id) card missing")
            let row = app.descendants(matching: .any)["\(id).0"]
            XCTAssertTrue(row.exists, "\(id) has no steps")
        }
        shot("guide-\(scheme)-content")

        waitFor(app.staticTexts["howToHeader"], "Step by step section missing")
        let step = app.descendants(matching: .any)["howToStep.0"]
        waitFor(step, "No instruction step shown")
        let photos = app.descendants(matching: .any)["howToPhotos"]
        for _ in 0..<8 where !photos.exists { app.swipeUp() }
        waitFor(photos, "Reference photos missing")
        waitFor(app.buttons["formGuide.photo.start"], "Start photo missing")
        waitFor(app.buttons["formGuide.photo.end"], "End photo missing")
        shot("guide-\(scheme)-photos")

        tap(app.buttons["formGuide.close"])
        XCTAssertTrue(stage.waitForNonExistence(timeout: 10))
    }

    private func sleepBriefly() { Thread.sleep(forTimeInterval: 0.8) }
}
