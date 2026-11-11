import XCTest
@testable import Lightstack

final class TrainingDayNudgeTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return c
    }
    private let user = UUID()

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10)) ?? Date()
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }

    private func target(protein: Double = 180, carbs: Double = 250, kcal: Double = 2400) -> NutritionTarget {
        NutritionTarget(id: UUID(), userId: user, effectiveDate: at(0), kcal: kcal, protein: protein, carbs: carbs, fat: 70,
                        kcalOverridden: true, createdAt: at(0), updatedAt: at(0))
    }

    private func entry(created: Date, kcal: Double = 300, p: Double = 0, c: Double = 0, f: Double = 0) -> FoodEntry {
        FoodEntry(id: UUID(), userId: user, date: calendar.startOfDay(for: created), foodId: nil, name: "Food", servings: 1,
                  servingLabel: "1 serving", perServing: NutrientValues(kcal: kcal, protein: p, carbs: c, fat: f),
                  source: .quick, createdAt: created, updatedAt: created, mealSlotId: nil)
    }

    private func make(done: Bool = false, type: String? = "Legs", goal: NutritionGoal? = .maintain, entries: [FoodEntry] = [],
                      target: NutritionTarget? = nil, now: Date) -> TrainingDayNudge? {
        TrainingDayNudge.make(info: TrainingDayInfo(workoutType: type, workoutDone: done), target: target ?? self.target(),
                              entries: entries, goal: goal, now: now, calendar: calendar)
    }

    // MARK: - Content

    func testTitleAndProteinLine() throws {
        let nudge = try XCTUnwrap(make(entries: [entry(created: at(8), p: 45, c: 100)], now: at(9)))
        XCTAssertEqual(nudge.title, "Training day · Legs")
        XCTAssertEqual(nudge.proteinLine, "Protein 45/180 g so far")
        XCTAssertEqual(try XCTUnwrap(make(type: nil, now: at(9))).title, "Training day")
        XCTAssertEqual(try XCTUnwrap(make(type: "  ", now: at(9))).title, "Training day")
    }

    func testNoWorkoutOrNoTargetsHidesTheCard() {
        XCTAssertNil(TrainingDayNudge.make(info: nil, target: target(), entries: [], goal: .lose, now: at(9), calendar: calendar))
        XCTAssertNil(TrainingDayNudge.make(info: TrainingDayInfo(workoutType: "Legs", workoutDone: false), target: nil,
                                           entries: [], goal: .lose, now: at(9), calendar: calendar))
        XCTAssertNil(make(target: target(protein: 0, carbs: 0, kcal: 0), now: at(9)))
    }

    // MARK: - Tip rules

    func testLoseGoalWinsOverEverything() throws {
        let heavy = [entry(created: at(10, 30), kcal: 1000, f: 50)]
        XCTAssertEqual(try XCTUnwrap(make(goal: .lose, entries: heavy, now: at(11))).tip, TrainingDayNudge.loseTip)
        XCTAssertEqual(try XCTUnwrap(make(done: true, goal: .lose, now: at(18))).tip, TrainingDayNudge.loseTip)
    }

    func testLowCarbsBeforeTheWorkoutOrBeforeThreePm() throws {
        // 40 of 250 g is under 25%.
        let low = [entry(created: at(8), c: 40)]
        XCTAssertEqual(try XCTUnwrap(make(entries: low, now: at(17))).tip, TrainingDayNudge.carbsTip, "before the workout, even late")
        XCTAssertEqual(try XCTUnwrap(make(done: true, entries: low, now: at(14))).tip, TrainingDayNudge.carbsTip, "done but before 3pm")
        XCTAssertEqual(try XCTUnwrap(make(done: true, entries: low, now: at(16))).tip, TrainingDayNudge.doneTip, "done and after 3pm")
        // 70 of 250 g is above 25%.
        XCTAssertNotEqual(try XCTUnwrap(make(entries: [entry(created: at(8), c: 70)], now: at(9))).tip, TrainingDayNudge.carbsTip)
    }

    func testHeavyMealJustNowBeforeTheWorkout() throws {
        let carbsOk = entry(created: at(7), c: 100)
        let heavy = entry(created: at(10, 30), kcal: 900, c: 20, f: 40)
        XCTAssertEqual(try XCTUnwrap(make(entries: [carbsOk, heavy], now: at(11))).tip, TrainingDayNudge.heavyMealTip)
        // More than 2 hours ago, too few calories or too little fat: not heavy.
        XCTAssertNil(try XCTUnwrap(make(entries: [carbsOk, entry(created: at(8), kcal: 900, f: 40)], now: at(11))).tip)
        XCTAssertNil(try XCTUnwrap(make(entries: [carbsOk, entry(created: at(10, 30), kcal: 700, f: 40)], now: at(11))).tip)
        XCTAssertNil(try XCTUnwrap(make(entries: [carbsOk, entry(created: at(10, 30), kcal: 900, f: 20)], now: at(11))).tip)
        // Once the workout is done the heavy-meal rule no longer applies.
        XCTAssertEqual(try XCTUnwrap(make(done: true, entries: [carbsOk, heavy], now: at(11))).tip, TrainingDayNudge.doneTip)
    }

    func testRecoveryTipAfterTheWorkoutAndNoTipOtherwise() throws {
        let fed = [entry(created: at(8), c: 100)]
        XCTAssertEqual(try XCTUnwrap(make(done: true, entries: fed, now: at(19))).tip, TrainingDayNudge.doneTip)
        XCTAssertNil(try XCTUnwrap(make(entries: fed, now: at(9))).tip)
    }

    // MARK: - Dismissal per day

    func testDismissalLastsOneDay() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "TrainingDayNudgeTests-\(UUID().uuidString)"))
        let monday = at(9)
        let tuesday = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: monday))
        XCTAssertFalse(TrainingDayPreferences.isDismissed(on: monday, in: defaults, calendar: calendar))
        TrainingDayPreferences.dismiss(on: monday, in: defaults, calendar: calendar)
        XCTAssertTrue(TrainingDayPreferences.isDismissed(on: at(23), in: defaults, calendar: calendar), "same day, later")
        XCTAssertFalse(TrainingDayPreferences.isDismissed(on: tuesday, in: defaults, calendar: calendar), "the next day shows it again")
        XCTAssertEqual(TrainingDayPreferences.dayId(monday, calendar: calendar), "2026-11-10")
    }

    func testTipsSettingDefaultsOn() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "TrainingDayNudgeTests-\(UUID().uuidString)"))
        XCTAssertTrue(TrainingDayPreferences.tipsEnabled(in: defaults))
        defaults.set(false, forKey: TrainingDayPreferences.tipsKey)
        XCTAssertFalse(TrainingDayPreferences.tipsEnabled(in: defaults))
    }
}
