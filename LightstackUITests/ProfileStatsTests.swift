import XCTest

final class ProfileStatsTests: LightstackUITestCase {

    /// The seeded workout has no duration (imported-style). A workout finished in the app,
    /// even a very short one, must give a non-zero Avg Duration on Profile.
    func testAvgDurationAfterQuickInAppWorkout() throws {
        launchApp()

        // Visit Profile first so a stale-on-first-load screen is part of the flow.
        openTab("Profile")
        waitFor(app.staticTexts["profile.stat.avgDuration"])
        openTab("Today")
        waitFor(app.buttons["chip.Push"])

        generateAndStartPushWorkout()
        replaceText(in: weightField(), with: "100")
        replaceText(in: repsField(), with: "5")
        replaceText(in: rirField(), with: "2")
        dismissKeyboardIfNeeded()
        tap(app.buttons["finishWorkoutButton"])
        let save = waitFor(app.buttons["saveWorkoutButton"], "Post-workout screen did not appear")
        XCTAssertTrue(save.waitForHittable(timeout: timeout), "Save never became enabled")
        let chip = app.buttons["chip.Push"]
        for _ in 0..<3 where !chip.exists {
            if save.exists && save.isHittable { save.tap() }
            if chip.waitForExistence(timeout: 10) { break }
        }
        waitFor(chip, "Did not return to setup after saving")

        openTab("Profile")
        let avg = waitFor(app.staticTexts["profile.stat.avgDuration"])
        shot("profile-stats")
        XCTAssertNotEqual(avg.label, "0 min", "Avg Duration shows 0 min after an in-app workout")
        XCTAssertEqual(app.staticTexts["profile.stat.totalWorkouts"].label, "3",  // 2 seeded + this one
                       "Profile did not refresh after the workout was saved")
    }

    /// Profile -> See all lists every PR, including the seeded Bench Press.
    func testSeeAllPersonalRecords() throws {
        launchApp()
        openTab("Profile")
        let seeAll = app.buttons["profile.seeAllPRs"]
        if !seeAll.exists { app.swipeUp() }
        tap(seeAll)
        waitFor(app.staticTexts["prList.row.Bench Press"], "Bench Press PR missing from full list")
        shot("pr-list")
        let search = app.searchFields.firstMatch
        waitFor(search)
        search.tap()
        search.typeText("overhead")
        waitFor(app.staticTexts["prList.row.Overhead Press"])
        XCTAssertFalse(app.staticTexts["prList.row.Bench Press"].exists)
    }
}
