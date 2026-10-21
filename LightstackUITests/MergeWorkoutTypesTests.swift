import XCTest

final class MergeWorkoutTypesTests: LightstackUITestCase {

    private let seedArgs = ["-uiTestingDuplicateWorkoutTypes"]

    private func openManageWorkoutTypes() {
        openTab("Profile")
        let manage = app.buttons["profile.manageWorkoutTypes"]
        for _ in 0..<4 where !manage.isHittable { app.swipeUp() }
        tap(manage)
    }

    /// Taps the confirmation-dialog action, retrying if the first tap was lost.
    private func confirmDialog(_ title: String) {
        let button = waitFor(app.buttons[title])
        for _ in 0..<3 where button.exists {
            button.tap()
            if button.waitForNonExistence(timeout: 3) { break }
        }
    }

    func testMergeSuggestedGroupLeavesOnePushChip() throws {
        launchApp(colorScheme: "dark", extraArguments: seedArgs)
        openTab("History")
        waitFor(app.buttons["chip.Push Day"], "Seed should include a Push Day workout")
        shot("history-chips-before-dark")

        openManageWorkoutTypes()
        let group = waitFor(app.buttons["mergeType.group.0"], "Resolver did not group the Push spellings")
        shot("merge-types-tool-dark")
        group.tap()
        tap(app.buttons["mergeType.keep.Push"])
        shot("merge-types-keep-sheet-dark")
        tap(app.buttons["mergeType.confirm"])
        confirmDialog("Merge into Push")
        waitFor(app.staticTexts["mergeType.noDuplicates"], "Group should be gone after merging")

        openTab("History")
        waitFor(app.buttons["chip.Push"])
        XCTAssertTrue(app.buttons["chip.Legs"].exists)
        XCTAssertFalse(app.buttons["chip.Push Day"].exists, "Push Day should have been merged into Push")
        XCTAssertFalse(app.buttons["chip.push"].exists, "push should have been merged into Push")
        shot("history-chips-after-dark")
    }

    func testManualMultiSelectMerge() throws {
        launchApp(colorScheme: "light", extraArguments: seedArgs)
        openManageWorkoutTypes()
        waitFor(app.buttons["mergeType.group.0"])
        XCTAssertFalse(app.buttons["mergeType.mergeSelected"].isEnabled)
        // Two names the resolver does not link.
        let pickArm = app.buttons["mergeType.pick.Arm Day"]
        for _ in 0..<4 where !pickArm.isHittable { app.swipeUp() }
        tap(pickArm)
        tap(app.buttons["mergeType.pick.Core Day"])
        shot("merge-types-manual-select-light")
        tap(app.buttons["mergeType.mergeSelected"])
        tap(app.buttons["mergeType.keep.Arm Day"])
        tap(app.buttons["mergeType.confirm"])
        confirmDialog("Merge into Arm Day")
        let gone = app.buttons["mergeType.pick.Core Day"]
        XCTAssertTrue(gone.waitForNonExistence(timeout: timeout), "Core Day should have been renamed")
    }
}
