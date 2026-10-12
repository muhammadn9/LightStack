import XCTest

final class MergeExercisesTests: LightstackUITestCase {

    private func openManageExercises() {
        openTab("Profile")
        let manage = app.buttons["profile.manageExercises"]
        for _ in 0..<3 where !manage.isHittable { app.swipeUp() }
        tap(manage)
    }

    /// Opens Top Lifts "See all" and returns whether a row exists, then closes it.
    private func prListHas(_ name: String) -> Bool {
        let seeAll = app.buttons["profile.seeAllPRs"]
        for _ in 0..<3 where !seeAll.isHittable { app.swipeUp() }
        tap(seeAll)
        waitFor(app.staticTexts["prList.row.Bench Press"])
        let found = app.staticTexts["prList.row.\(name)"].exists
        shot("pr-list-\(name)")
        tap(app.buttons["prList.done"])
        return found
    }

    /// Today -> Log Manually -> Add Exercise -> Add Custom Exercise (retries a swallowed first tap).
    private func openCustomExerciseAlert() {
        let manual = waitFor(app.buttons["logManuallyButton"])
        let add = app.buttons["Add Exercise"]
        for _ in 0..<3 where !add.exists {
            manual.tap()
            if add.waitForExistence(timeout: 5) { break }
        }
        let custom = app.buttons["addCustomExerciseButton"]
        waitFor(add)
        for _ in 0..<3 where !custom.exists {
            add.tap()
            if custom.waitForExistence(timeout: 5) { break }
        }
        tap(custom)
    }

    /// Taps the confirmation-dialog action, retrying if the first tap was lost.
    private func confirmDialog(_ title: String) {
        let button = waitFor(app.buttons[title])
        for _ in 0..<3 where button.exists {
            button.tap()
            if button.waitForNonExistence(timeout: 3) { break }
        }
    }

    func testMergeDuplicatesLeavesOneTopLift() throws {
        launchApp(colorScheme: "dark", extraArguments: ["-uiTestingDuplicateNames"])
        openTab("Profile")
        waitFor(app.staticTexts["profile.stat.totalWorkouts"])
        XCTAssertTrue(prListHas("Leg Extension"))
        XCTAssertTrue(prListHas("Leg extension machine"), "Seed should have both spellings")

        openManageExercises()
        let group = waitFor(app.buttons["merge.group.0"], "Resolver did not group the two spellings")
        shot("merge-tool-dark")
        group.tap()
        tap(app.buttons["merge.keep.Leg Extension"])
        shot("merge-keep-sheet-dark")
        tap(app.buttons["merge.confirm"])
        shot("merge-confirm-dialog-dark")
        confirmDialog("Merge into Leg Extension")

        waitFor(app.staticTexts["merge.noDuplicates"], "Group should be gone after merging")
        app.navigationBars.buttons.firstMatch.tap()
        waitFor(app.staticTexts["profile.stat.totalWorkouts"])
        XCTAssertTrue(prListHas("Leg Extension"))
        XCTAssertFalse(prListHas("Leg extension machine"), "Old spelling still listed after merge")
        XCTAssertEqual(app.staticTexts["profile.stat.totalWorkouts"].label, "3", "Merging must not change workout count")
    }

    func testManualMultiSelectMerge() throws {
        launchApp(colorScheme: "light", extraArguments: ["-uiTestingDuplicateNames"])
        openManageExercises()
        waitFor(app.buttons["merge.group.0"])
        XCTAssertFalse(app.buttons["merge.mergeSelected"].isEnabled)
        // Two names the resolver does not link.
        let pickPress = app.buttons["merge.pick.Overhead Press"]
        for _ in 0..<4 where !pickPress.isHittable { app.swipeUp() }
        tap(pickPress)
        tap(app.buttons["merge.pick.Bench Press"])
        shot("merge-manual-select-light")
        tap(app.buttons["merge.mergeSelected"])
        tap(app.buttons["merge.keep.Bench Press"])
        shot("merge-keep-sheet-light")
        tap(app.buttons["merge.confirm"])
        confirmDialog("Merge into Bench Press")
        let gone = app.buttons["merge.pick.Overhead Press"]
        XCTAssertTrue(gone.waitForNonExistence(timeout: timeout), "Overhead Press should have been renamed")
    }

    func testDidYouMeanWhenAddingCustomExercise() throws {
        launchApp(colorScheme: "dark", extraArguments: ["-uiTestingDuplicateNames"])
        openCustomExerciseAlert()
        type("leg extensions", into: app.textFields["customExerciseNameField"])
        tap(app.buttons["customExerciseAddButton"])

        let row = waitFor(app.otherElements["nameSuggestion.row"], "No suggestion row")
        let suggested = app.staticTexts["nameSuggestion.text"].label
        XCTAssertTrue(suggested.lowercased().contains("leg extension"), "Unexpected suggestion: \(suggested)")
        // Most recently used spelling wins ties.
        XCTAssertTrue(suggested.contains("Leg extension machine"), "Unexpected suggestion: \(suggested)")
        shot("did-you-mean-dark")
        row.buttons["nameSuggestion.use"].tap()
        // Picker closes and the existing spelling was added.
        waitFor(app.staticTexts["Leg extension machine"])
        XCTAssertFalse(app.staticTexts["leg extensions"].exists)
    }

    func testKeepMineAddsTypedName() throws {
        launchApp(colorScheme: "light", extraArguments: ["-uiTestingDuplicateNames"])
        openCustomExerciseAlert()
        type("leg extensions", into: app.textFields["customExerciseNameField"])
        tap(app.buttons["customExerciseAddButton"])
        waitFor(app.otherElements["nameSuggestion.row"])
        shot("did-you-mean-light")
        tap(app.buttons["nameSuggestion.keep"])
        waitFor(app.staticTexts["leg extensions"])
    }
}
