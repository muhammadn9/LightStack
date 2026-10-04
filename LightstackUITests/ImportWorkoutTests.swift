import XCTest

final class ImportWorkoutTests: LightstackUITestCase {

    private let json = "{\"workouts\":[{\"date\":\"2026-09-20\",\"name\":\"Imported Pull\","
        + "\"exercises\":[{\"name\":\"Barbell Row\",\"muscle_group\":\"Back\","
        + "\"sets\":[{\"weight_lbs\":135,\"reps\":8,\"rir\":2}]}]}]}"

    func testImportWorkoutFromJSON() throws {
        launchApp()
        openTab("History")
        tap(app.buttons["importWorkoutsButton"])

        let editor = waitFor(app.textViews["importTextEditor"])
        editor.tap()
        editor.typeText(json)
        dismissKeyboardIfNeeded()
        shot("01-pasted")

        tap(app.buttons["importCheckButton"])
        let confirm = waitFor(app.buttons["importConfirmButton"], "Check did not produce an import button")
        shot("02-checked")
        confirm.tap()

        waitFor(app.buttons["historyRow.Imported Pull"], "Imported workout missing from History")
        shot("03-history")
    }
}
