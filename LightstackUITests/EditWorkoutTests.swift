import XCTest

final class EditWorkoutTests: LightstackUITestCase {

    func testEditSeededWorkoutWeight() throws {
        launchApp()
        openTab("History")
        shot("00-history")
        let row = app.buttons.matching(identifier: "historyRow.Push").firstMatch
        tap(row)
        waitFor(app.staticTexts["Bench Press"])
        waitFor(app.staticTexts["135.0"])
        shot("01-detail-before")

        tap(app.buttons["editWorkoutButton"])
        let weight = app.textFields["editSet.0.0.weight"]
        replaceText(in: weight, with: "145")
        dismissKeyboardIfNeeded()
        shot("02-editing")

        tap(app.buttons["editSaveButton"])
        waitFor(app.buttons["editWorkoutButton"], "Did not leave edit mode after saving")
        waitFor(app.staticTexts["145.0"], "Detail did not show the new weight")
        shot("03-detail-after")
    }
}
