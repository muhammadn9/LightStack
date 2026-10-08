import XCTest

final class WeekStripTests: LightstackUITestCase {

    private static let idFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func dayId(_ offset: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return "weekDay.\(Self.idFormatter.string(from: date))"
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Taps the bubble for a day offset from today, paging back with the arrow if it is in last week.
    private func tapDay(_ offset: Int) {
        let id = dayId(offset)
        let day = element(id)
        for _ in 0..<2 where !day.waitForExistence(timeout: 1) {
            tap(app.buttons["weekStrip.previous"])
        }
        tap(day)
    }

    private func streakValue() -> Int {
        openTab("Profile")
        let label = waitFor(app.staticTexts["profile.streak"]).label
        openTab("Today")
        return Int(label) ?? -1
    }

    /// A past day with a seeded workout opens a sheet listing it, and the detail opens from there.
    func testTapPastWorkoutDayShowsWorkoutAndDetail() throws {
        launchApp()
        waitFor(app.buttons["chip.Push"])
        tapDay(-1)
        waitFor(element("daySheet"))
        let row = waitFor(app.buttons["daySheet.workout.Push"], "Seeded Push workout missing from the day sheet")
        shot("daysheet-workout")
        row.tap()
        waitFor(app.staticTexts["Bench Press"], "Workout detail did not open")
    }

    /// Marking an empty past day as rest bridges the streak; removing it undoes that.
    func testMarkAndRemoveRestDay() throws {
        launchApp()
        waitFor(app.buttons["chip.Push"])
        let before = streakValue()
        XCTAssertEqual(before, 2, "Seeded streak (today + yesterday) expected")

        // Two days ago has no seeded workout; three days ago does.
        tapDay(-2)
        waitFor(app.staticTexts["daySheet.noWorkout"])
        shot("daysheet-empty")
        XCTAssertTrue(app.buttons["daySheet.logWorkout"].exists)
        tap(app.buttons["daySheet.markRest"])
        waitFor(app.staticTexts["daySheet.restLabel"])
        shot("daysheet-rest")
        tap(app.buttons["daySheet.done"])
        waitFor(app.buttons["chip.Push"])
        shot("weekstrip-rest-moon")
        XCTAssertEqual(streakValue(), 4, "Rest day should bridge to the workout 3 days ago")

        // Remove it again.
        tapDay(-2)
        tap(app.buttons["daySheet.removeRest"])
        waitFor(app.staticTexts["daySheet.noWorkout"])
        tap(app.buttons["daySheet.done"])
        XCTAssertEqual(streakValue(), 2)
    }

    /// Today toggle: mark today as a rest day is hidden when a workout exists, so check a past
    /// week navigation instead: arrows page back and the next arrow is disabled on this week.
    func testWeekNavigationAndFutureDaysDisabled() throws {
        launchApp()
        waitFor(app.buttons["chip.Push"])
        XCTAssertFalse(app.buttons["weekStrip.next"].isEnabled)
        tap(app.buttons["weekStrip.previous"])
        XCTAssertTrue(app.buttons["weekStrip.next"].isEnabled)
        shot("weekstrip-previous-week")
        tap(app.buttons["weekStrip.next"])
        XCTAssertFalse(app.buttons["weekStrip.next"].isEnabled)
    }

    /// Rest days must not change workout totals.
    func testRestDayDoesNotChangeTotalWorkouts() throws {
        launchApp()
        waitFor(app.buttons["chip.Push"])
        tapDay(-2)
        tap(app.buttons["daySheet.markRest"])
        tap(app.buttons["daySheet.done"])
        openTab("Profile")
        XCTAssertEqual(waitFor(app.staticTexts["profile.stat.totalWorkouts"]).label, "3")
    }
}
