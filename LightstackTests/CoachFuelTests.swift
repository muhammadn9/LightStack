import XCTest
import Supabase
@testable import Lightstack

/// Phase 7: the coach's nutrition context (FUEL, PRE-WORKOUT MEALS), the sharing switches, the prompt rules,
/// the fuel guard on the plan's weights and the fuel-aware miss classification.
@MainActor
final class CoachFuelTests: XCTestCase {

    private let user = UUID()
    private let calendar = Calendar.current
    private let service = CoachPromptService(validationService: ValidationService())

    /// Tuesday 10 November 2026, 08:10 local.
    private var now: Date { at(0, 8, 10) }
    private var today: Date { calendar.startOfDay(for: now) }

    /// `daysBack` days before the reference day at hour:minute.
    private func at(_ daysBack: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10)) ?? Date()
        let day = calendar.date(byAdding: .day, value: -daysBack, to: base) ?? base
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private func entry(_ name: String = "Food", on day: Date, created: Date? = nil, kcal: Double, p: Double = 0, c: Double = 0,
                       f: Double = 0, slot: UUID? = nil) -> FoodEntry {
        let stamp = created ?? calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        return FoodEntry(id: UUID(), userId: user, date: calendar.startOfDay(for: day), foodId: nil, name: name, servings: 1,
                         servingLabel: "1 serving", perServing: NutrientValues(kcal: kcal, protein: p, carbs: c, fat: f),
                         source: .quick, createdAt: stamp, updatedAt: stamp, mealSlotId: slot)
    }

    private func weighIn(_ daysBack: Int, _ lbs: Double) -> WeighIn {
        WeighIn(id: UUID(), userId: user, date: calendar.startOfDay(for: at(daysBack, 7)), weightLbs: lbs,
                createdAt: now, updatedAt: now)
    }

    private func target(_ kcal: Double = 2400, protein: Double = 180) -> NutritionTarget {
        NutritionTarget(id: UUID(), userId: user, effectiveDate: at(60, 0), kcal: kcal, protein: protein, carbs: 250, fat: 70,
                        kcalOverridden: true, createdAt: now, updatedAt: now)
    }

    private func goals(_ goal: NutritionGoal = .lose, rate: Double = 0.5) -> NutritionGoalSettings {
        NutritionGoalSettings(id: UUID(), userId: user, goal: goal, sex: .male, age: 30, heightInches: 70, currentWeightLbs: 180,
                              targetWeightLbs: 170, weeklyRateLbs: rate, activityLevel: .active, liftsWeights: true, unit: .lb,
                              completedAt: now, createdAt: now, updatedAt: now)
    }

    /// One logged day per entry of `days` (days back from today), 2000 kcal / 150 P / 200 C / 60 F each.
    private func loggedDays(_ days: [Int], kcal: Double = 2000, protein: Double = 150) -> [FoodEntry] {
        days.map { entry(on: at($0, 12), kcal: kcal, p: protein, c: 200, f: 60) }
    }

    private func build(_ entries: [FoodEntry], weighIns: [WeighIn] = [], goals: NutritionGoalSettings? = nil,
                       targets: [NutritionTarget] = []) -> CoachFuelSummary? {
        CoachFuelBuilder.build(entries: entries, targets: targets, weighIns: weighIns, goals: goals, now: now, calendar: calendar)
    }

    // MARK: - Builder maths

    func testLastSevenDaysAverageOverLoggedDaysOnly() throws {
        // Days 1, 2 and 4 logged; day 3 is "not tracked", not zero.
        var entries = [entry(on: at(1, 12), kcal: 2200, p: 160, c: 220, f: 70),
                       entry(on: at(2, 12), kcal: 2600, p: 200, c: 260, f: 90),
                       entry(on: at(4, 12), kcal: 2400, p: 180, c: 240, f: 80)]
        entries.append(entry(on: at(9, 12), kcal: 9999))   // outside the 7 days
        let fuel = try XCTUnwrap(build(entries, targets: [target(2400, protein: 180)]))
        let week = try XCTUnwrap(fuel.last7)
        XCTAssertEqual(week.loggedDays, 3)
        XCTAssertEqual(week.avgKcal, 2400, accuracy: 0.01)
        XCTAssertEqual(week.avgProtein, 180, accuracy: 0.01)
        XCTAssertEqual(week.avgCarbs, 240, accuracy: 0.01)
        XCTAssertEqual(week.avgFat, 80, accuracy: 0.01)
        XCTAssertEqual(week.avgTargetKcal ?? 0, 2400, accuracy: 0.01)
        XCTAssertEqual(week.avgTargetProtein ?? 0, 180, accuracy: 0.01)
        // 2200 is -8.3%, 2600 is +8.3%, 2400 is 0: all inside the dashboard's +-10% rule.
        XCTAssertEqual(week.daysOnTarget, 3)
        XCTAssertEqual(week.daysWithTarget, 3)
    }

    func testDaysOnTargetUsesTheTenPercentRule() throws {
        let entries = [entry(on: at(1, 12), kcal: 2400), entry(on: at(2, 12), kcal: 2000), entry(on: at(3, 12), kcal: 2700)]
        let week = try XCTUnwrap(build(entries, targets: [target(2400)])?.last7)
        XCTAssertEqual(week.daysOnTarget, 1, "2000 is -16.7% and 2700 is +12.5%")
        XCTAssertEqual(week.daysWithTarget, 3)
    }

    func testYesterdayFieldsKeepWorking() throws {
        let fuel = try XCTUnwrap(build([entry(on: at(1, 12), kcal: 2450, p: 150)], goals: goals(), targets: [target(2600, protein: 180)]))
        XCTAssertEqual(fuel.yesterdayKcal, 2450)
        XCTAssertEqual(fuel.targetKcal, 2600)
        XCTAssertEqual(fuel.proteinG, 150)
        XCTAssertEqual(fuel.targetProteinG, 180)
        XCTAssertEqual(fuel.goal, "lose")
        XCTAssertEqual(fuel.weeklyRate, 0.5)
    }

    func testTodaySoFarCountsOnlyWhatWasLoggedByNow() throws {
        let breakfast = entry("Oats", on: today, created: at(0, 7, 30), kcal: 450, p: 35)
        let later = entry("Dinner", on: today, created: at(0, 19), kcal: 900, p: 60)
        let today = try XCTUnwrap(build([breakfast, later], targets: [target()])?.today)
        XCTAssertEqual(today.kcalSoFar, 450)
        XCTAssertEqual(today.proteinSoFar, 35)
        XCTAssertEqual(today.targetKcal, 2400)
        XCTAssertEqual(today.timeLabel, "8:10am")
        XCTAssertTrue(today.hasEntries)
    }

    func testNoDataAtAllGivesNoSummary() {
        XCTAssertNil(build([]))
        XCTAssertNotNil(build([], goals: goals()), "a finished goal alone is something to say")
    }

    func testTimeOfDayLabel() {
        XCTAssertEqual(CoachFuelBuilder.timeLabel(at(0, 8, 10), calendar: calendar), "8:10am")
        XCTAssertEqual(CoachFuelBuilder.timeLabel(at(0, 13, 45), calendar: calendar), "1:45pm")
        XCTAssertEqual(CoachFuelBuilder.timeLabel(at(0, 0, 5), calendar: calendar), "12:05am")
        XCTAssertEqual(CoachFuelBuilder.timeLabel(at(0, 12, 0), calendar: calendar), "12:00pm")
    }

    // MARK: - Weight trend

    func testWeightTrendIsPoundsPerWeek() throws {
        // 0.5 lb lost every 3.5 days is 1 lb/week, over 14 days.
        let weighIns = [weighIn(13, 182), weighIn(9, 181.4), weighIn(6, 180.6), weighIn(0, 180)]
        let trend = try XCTUnwrap(CoachFuelBuilder.weightTrend(weighIns, days: 14, now: now, calendar: calendar))
        XCTAssertEqual(trend, -1.0, accuracy: 0.2)
        let fuel = try XCTUnwrap(build([], weighIns: weighIns))
        XCTAssertNotNil(fuel.weightTrend14)
        XCTAssertNotNil(fuel.weightTrend30)
    }

    func testWeightTrendNeedsTwoWeighInsAndAFewDays() {
        XCTAssertNil(CoachFuelBuilder.weightTrend([weighIn(0, 180)], days: 14, now: now, calendar: calendar))
        XCTAssertNil(CoachFuelBuilder.weightTrend([weighIn(3, 181), weighIn(0, 180)], days: 14, now: now, calendar: calendar),
                     "three days apart is too short to read")
        XCTAssertNil(CoachFuelBuilder.weightTrend([weighIn(20, 185), weighIn(0, 180)], days: 14, now: now, calendar: calendar),
                     "the 20-day-old weigh-in is outside the 14-day window")
        XCTAssertNotNil(CoachFuelBuilder.weightTrend([weighIn(20, 185), weighIn(0, 180)], days: 30, now: now, calendar: calendar))
    }

    // MARK: - Data quality

    func testDataQualityThresholds() throws {
        for (count, expected) in [(0, FuelDataQuality.unreliable), (1, .unreliable), (2, .partial), (4, .partial),
                                  (5, .good), (7, .good)] {
            XCTAssertEqual(FuelDataQuality.forLoggedDays(count), expected, "\(count) days")
        }
        let partial = try XCTUnwrap(build(loggedDays([1, 3, 6]), goals: goals()))
        XCTAssertEqual(partial.dataQuality, .partial)
        let good = try XCTUnwrap(build(loggedDays([1, 2, 3, 5, 6])))
        XCTAssertEqual(good.dataQuality, .good)
        let none = try XCTUnwrap(build([], goals: goals()))
        XCTAssertEqual(none.dataQuality, .unreliable)
    }

    // MARK: - Pre-workout meals

    private func meals(_ entries: [FoodEntry], start: Date? = nil) -> PreWorkoutMeals? {
        PreWorkoutMealsBuilder.build(entries: entries, before: start ?? at(0, 10), calendar: calendar)
    }

    func testEntriesInOneSlotAndDayAreOneMeal() throws {
        let slot = UUID()
        let result = try XCTUnwrap(meals([
            entry("Burger", on: at(0, 8), created: at(0, 8, 0), kcal: 700, p: 30, c: 50, f: 40, slot: slot),
            entry("Fries", on: at(0, 8), created: at(0, 8, 20), kcal: 400, p: 10, c: 45, f: 20, slot: slot),
            entry("Shake", on: at(0, 8), created: at(0, 8, 40), kcal: 100, p: 5, c: 10, f: 2, slot: UUID())
        ]))
        XCTAssertEqual(result.meals.count, 2)
        let burger = try XCTUnwrap(result.meals.first { $0.foods.contains("Burger") })
        XCTAssertEqual(burger.foods, ["Burger", "Fries"])
        XCTAssertEqual(burger.kcal, 1100)
        XCTAssertEqual(burger.protein, 40)
        XCTAssertEqual(burger.carbs, 95)
        XCTAssertEqual(burger.fat, 60)
        XCTAssertEqual(burger.hoursBefore, 1.7, accuracy: 0.001, "the meal is dated by its last entry (8:20), workout at 10:00")
    }

    func testEntriesWithoutASlotGroupByFortyFiveMinutes() throws {
        let result = try XCTUnwrap(meals([
            entry("Eggs", on: at(0, 6), created: at(0, 6, 0), kcal: 200),
            entry("Toast", on: at(0, 6), created: at(0, 6, 40), kcal: 100),        // 40 min later: same meal
            entry("Coffee", on: at(0, 6), created: at(0, 7, 20), kcal: 20),        // 40 min after the toast: still the chain
            entry("Banana", on: at(0, 8), created: at(0, 8, 30), kcal: 100)        // 70 min gap: a new meal
        ]))
        XCTAssertEqual(result.meals.count, 2)
        XCTAssertEqual(result.meals[0].foods, ["Banana"])
        XCTAssertEqual(Set(result.meals[1].foods), ["Eggs", "Toast", "Coffee"])
        XCTAssertEqual(result.meals[1].kcal, 320)
    }

    func testFoodsAreTheTopThreeByCaloriesWithAMoreCount() throws {
        let slot = UUID()
        let items = [("Rice", 200.0), ("Chicken", 400.0), ("Oil", 120.0), ("Salsa", 20.0), ("Beans", 150.0)]
        let result = try XCTUnwrap(meals(items.enumerated().map { i, item in
            entry(item.0, on: at(0, 8), created: at(0, 8, i), kcal: item.1, slot: slot)
        }))
        let meal = try XCTUnwrap(result.meals.first)
        XCTAssertEqual(meal.foods, ["Chicken", "Rice", "Beans"])
        XCTAssertEqual(meal.moreCount, 2)
        XCTAssertEqual(meal.kcal, 890)
    }

    func testMealsAreNewestFirstCappedAtFourAndWindowIsTwentyFourHours() throws {
        let start = at(0, 18)
        // Hourly snacks (own slots) 9:00-17:00 plus one 25 hours back and one after the workout began.
        var entries = (9...17).map { entry("Snack\($0)", on: at(0, $0), created: at(0, $0), kcal: 100, c: 10, slot: UUID()) }
        entries.append(entry("Old", on: at(2, 16), created: at(2, 16), kcal: 500, c: 70, slot: UUID()))   // 50 h back
        entries.append(entry("Yesterday", on: at(1, 19, 30), created: at(1, 19, 30), kcal: 600, c: 60, slot: UUID()))   // 22.5 h back
        entries.append(entry("After", on: at(0, 19), created: at(0, 19), kcal: 300, c: 30, slot: UUID()))
        let result = try XCTUnwrap(meals(entries, start: start))
        XCTAssertEqual(result.meals.count, 4)
        XCTAssertEqual(result.meals.map(\.hoursBefore), [1.0, 2.0, 3.0, 4.0])
        XCTAssertEqual(result.meals[0].foods, ["Snack17"])
        // Carbs count every entry in the window (9 snacks + yesterday's dinner), not only the four listed.
        XCTAssertEqual(result.carbs24h, 9 * 10 + 60, accuracy: 0.001)
    }

    func testBackFilledAndEmptyWindowsGiveNoMeals() {
        // Logged today for yesterday: no real eating time, so it is ignored.
        let backfill = entry("Dinner", on: at(1, 19), created: at(0, 9), kcal: 800)
        XCTAssertNil(meals([backfill]))
        XCTAssertNil(meals([]))
    }

    // MARK: - Settings

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "coach-fuel-\(UUID().uuidString)") ?? .standard
    }

    func testSharingSettingsDefaultOnAndStoreLikeOtherPreferences() {
        let defaults = freshDefaults()
        XCTAssertTrue(CoachPreferences.shareNutritionSummary(in: defaults))
        XCTAssertTrue(CoachPreferences.sharePreWorkoutMeals(in: defaults))
        defaults.set(false, forKey: CoachPreferences.shareNutritionSummaryKey)
        defaults.set(false, forKey: CoachPreferences.sharePreWorkoutMealsKey)
        XCTAssertFalse(CoachPreferences.shareNutritionSummary(in: defaults))
        XCTAssertFalse(CoachPreferences.sharePreWorkoutMeals(in: defaults))
    }

    private func contextBuilder(defaults: UserDefaults) -> (CoachContextBuilder, UUID) {
        let stack = OutboxTestStack()
        let workouts = WorkoutRepository(localStorage: stack.storage, offlineQueueManager: stack.queue)
        let profiles = ProfileRepository(localStorage: stack.storage, supabaseService: SupabaseServiceFactory.unreachable(),
                                         offlineQueueManager: stack.queue)
        let fuel = CoachFuelSummary(yesterdayKcal: 2450, targetKcal: 2600, proteinG: 150, targetProteinG: 180)
        let sample = PreWorkoutMeals(meals: [PreWorkoutMeal(hoursBefore: 2, foods: ["Burger"], moreCount: 0, kcal: 1000,
                                                            protein: 40, carbs: 90, fat: 55)], carbs24h: 200)
        let builder = CoachContextBuilder(
            profileRepository: profiles, workoutRepository: workouts, localStorage: stack.storage,
            validationService: ValidationService(), fuel: { _, _ in fuel }, meals: { _, _ in sample }, defaults: defaults)
        return (builder, stack.userId)
    }

    func testBothSettingsOnSendFuelAndMeals() {
        let (builder, userId) = contextBuilder(defaults: freshDefaults())
        let context = builder.buildContext(userId: userId, workoutType: "Push")
        XCTAssertNotNil(context.fuel)
        XCTAssertNotNil(context.meals)
    }

    func testSummaryOffSendsNoFuelAtAllNotEvenYesterday() {
        let defaults = freshDefaults()
        defaults.set(false, forKey: CoachPreferences.shareNutritionSummaryKey)
        let (builder, userId) = contextBuilder(defaults: defaults)
        let context = builder.buildContext(userId: userId, workoutType: "Push")
        XCTAssertNil(context.fuel)
        XCTAssertNil(context.meals, "no summary means no meals either")
        XCTAssertFalse(FuelRules.assess(fuel: context.fuel, meals: context.meals).isLow, "nothing to judge, so no guard")
    }

    func testMealsOffKeepsTheSummaryButDropsTheMeals() {
        let defaults = freshDefaults()
        defaults.set(false, forKey: CoachPreferences.sharePreWorkoutMealsKey)
        let (builder, userId) = contextBuilder(defaults: defaults)
        let context = builder.buildContext(userId: userId, workoutType: "Push")
        XCTAssertNotNil(context.fuel)
        XCTAssertNil(context.meals)
        XCTAssertNil(service.mealsBlock(context.meals))
    }

    // MARK: - Prompt blocks

    private func fullFuel() -> CoachFuelSummary {
        CoachFuelSummary(
            yesterdayKcal: 2450, targetKcal: 2600, proteinG: 150, targetProteinG: 180, goal: "lose", weeklyRate: 0.5,
            today: FuelToday(kcalSoFar: 450, proteinSoFar: 35, targetKcal: 2400, targetProteinG: 180, timeLabel: "8:10am", hasEntries: true),
            last7: FuelWeek(loggedDays: 6, avgKcal: 2150, avgProtein: 150, avgCarbs: 220, avgFat: 70, avgTargetKcal: 2400,
                            avgTargetProtein: 180, daysOnTarget: 4, daysWithTarget: 6),
            weightTrend14: -0.6, weightTrend30: -0.4, dataQuality: .good)
    }

    func testFuelBlockContentAndBudget() throws {
        let block = try XCTUnwrap(service.fuelBlock(fullFuel()))
        XCTAssertEqual(block, """
            FUEL: data good (6/7 days logged)
            Today by 8:10am: 450/2400 kcal, P35/180 so far (day not over)
            7d avg of logged days: 2150/2400 kcal, P150/180 C220 F70; on target 4/6 days
            Weight: -0.6 lb/wk (14d), -0.4 lb/wk (30d); goal lose 0.5 lb/wk
            Yesterday: 2450/2600 kcal, P150/180
            """)
        XCTAssertLessThan(block.count, 400)
    }

    func testUnreliableFuelTellsTheAIToIgnoreIntake() throws {
        var fuel = fullFuel()
        fuel.dataQuality = .unreliable
        fuel.last7?.loggedDays = 1
        let block = try XCTUnwrap(service.fuelBlock(fuel))
        XCTAssertTrue(block.contains("data unreliable (1/7 days logged): ignore the intake numbers."), block)
        XCTAssertLessThan(block.count, 400)
    }

    func testFuelBlockWithNothingLoggedTodayAndNoFuel() throws {
        var fuel = fullFuel()
        fuel.today = FuelToday(kcalSoFar: 0, proteinSoFar: 0, targetKcal: 2400, targetProteinG: 180, timeLabel: "7:05am", hasEntries: false)
        XCTAssertTrue(try XCTUnwrap(service.fuelBlock(fuel)).contains("Today by 7:05am: nothing logged yet (day not over)"))
        XCTAssertNil(service.fuelBlock(nil))
    }

    func testMealsBlockContentAndBudget() throws {
        let block = try XCTUnwrap(service.mealsBlock(PreWorkoutMeals(
            meals: [PreWorkoutMeal(hoursBefore: 2.0, foods: ["burger", "fries"], moreCount: 1, kcal: 1100, protein: 40, carbs: 95, fat: 60),
                    PreWorkoutMeal(hoursBefore: 9.5, foods: ["oats", "eggs", "milk"], moreCount: 0, kcal: 520, protein: 32, carbs: 58, fat: 16)],
            carbs24h: 180)))
        XCTAssertEqual(block, """
            PRE-WORKOUT MEALS (newest first; carbs in the last 24h: 180 g):
            - 2.0h before: burger, fries (+1 more) — 1100 kcal P40 C95 F60
            - 9.5h before: oats, eggs, milk — 520 kcal P32 C58 F16
            """)
        XCTAssertLessThan(block.count, 4 * 110)
        XCTAssertNil(service.mealsBlock(nil))
        XCTAssertNil(service.mealsBlock(PreWorkoutMeals(meals: [], carbs24h: 0)))
    }

    func testPlanMessageCarriesBothBlocksAndNothingWhenOff() {
        let on = service.buildWorkoutRequestMessage(
            workoutType: "Push", time: 45, energy: 6, notes: nil,
            coach: CoachPromptService.PlanPromptExtras(fuelBlock: "FUEL-MARKER", mealsBlock: "MEALS-MARKER"))
        XCTAssertTrue(on.contains("FUEL-MARKER"))
        XCTAssertTrue(on.contains("MEALS-MARKER"))
        let off = service.buildWorkoutRequestMessage(workoutType: "Push", time: 45, energy: 6, notes: nil,
                                                     coach: CoachPromptService.PlanPromptExtras())
        XCTAssertFalse(off.contains("FUEL"))
        XCTAssertFalse(off.contains("PRE-WORKOUT MEALS"))
    }

    func testPostWorkoutMessageCarriesBothBlocks() {
        let message = service.buildPostWorkoutMessage(workoutType: "Push", exercises: [], sets: [:],
                                                      fuelBlock: "FUEL-MARKER", mealsBlock: "MEALS-MARKER")
        XCTAssertTrue(message.contains("FUEL-MARKER"))
        XCTAssertTrue(message.contains("MEALS-MARKER"))
        XCTAssertFalse(service.buildPostWorkoutMessage(workoutType: "Push", exercises: [], sets: [:]).contains("FUEL"))
    }

    func testRulesAreInAllThreePrompts() {
        let plan = service.buildSystemPrompt(profile: nil, task: .plan, aiSetsWeights: true)
        let review = service.buildSystemPrompt(profile: nil, task: .plan, aiSetsWeights: false)
        let chat = service.buildSystemPrompt(profile: nil, task: .chat)
        let post = service.buildSystemPrompt(profile: nil, task: .postWorkout)
        for (name, prompt) in [("plan", plan), ("review", review), ("chat", chat), ("post", post)] {
            XCTAssertTrue(prompt.contains("FUEL AND MEALS"), name)
            XCTAssertTrue(prompt.contains("eating closer to your targets would help"), name)
            XCTAssertTrue(prompt.contains("unreliable"), name)
        }
        for prompt in [plan, review] {
            XCTAssertTrue(prompt.contains("large high-fat meal within about 2 h"))
            XCTAssertTrue(prompt.contains("very low carbs in the last 24 h"))
            XCTAssertTrue(prompt.contains("more than 20% under target"))
            XCTAssertTrue(prompt.contains("under 80% of target"))
            XCTAssertTrue(prompt.contains("1.5x the goal rate"))
            XCTAssertTrue(prompt.contains("normal progression is fine"))
            XCTAssertTrue(prompt.contains("that exercise's one-line reason"))
        }
        XCTAssertTrue(post.contains("bad day"))
        XCTAssertTrue(post.contains("not lost strength"))
        XCTAssertTrue(chat.contains("how to eat today"))
    }

    // MARK: - Fuel rules

    private func lowFuel() -> CoachFuelSummary {
        var fuel = fullFuel()
        fuel.last7?.avgKcal = 1700   // 29% under 2400
        return fuel
    }

    func testAssessmentFlagsEachLowFuelSignal() {
        XCTAssertFalse(FuelRules.assess(fuel: fullFuel(), meals: nil).isLow, "2150 of 2400 and 150 of 180 protein is fine")
        XCTAssertEqual(FuelRules.assess(fuel: lowFuel(), meals: nil).primaryReason, "eating well under target this week")

        var protein = fullFuel()
        protein.last7?.avgProtein = 120   // 67% of 180
        XCTAssertEqual(FuelRules.assess(fuel: protein, meals: nil).reasons, ["protein is low this week"])

        var fastLoss = fullFuel()
        fastLoss.weightTrend14 = -1.0   // goal is 0.5/wk, so 1.5x is 0.75
        XCTAssertEqual(FuelRules.assess(fuel: fastLoss, meals: nil).reasons, ["weight is dropping faster than planned"])
        var onPace = fullFuel()
        onPace.weightTrend14 = -0.7
        XCTAssertFalse(FuelRules.assess(fuel: onPace, meals: nil).isLow)
        var gaining = fullFuel()
        gaining.goal = "gain"
        gaining.weightTrend14 = 0.6
        XCTAssertFalse(FuelRules.assess(fuel: gaining, meals: nil).isLow, "a gaining phase is well fuelled")

        let heavy = PreWorkoutMeals(meals: [PreWorkoutMeal(hoursBefore: 1.5, foods: ["Burger"], moreCount: 0, kcal: 1100,
                                                           protein: 40, carbs: 95, fat: 60)], carbs24h: 150)
        XCTAssertEqual(FuelRules.assess(fuel: fullFuel(), meals: heavy).reasons, ["a heavy meal just before training"])
        let early = PreWorkoutMeals(meals: [PreWorkoutMeal(hoursBefore: 3.5, foods: ["Burger"], moreCount: 0, kcal: 1100,
                                                           protein: 40, carbs: 95, fat: 60)], carbs24h: 150)
        XCTAssertFalse(FuelRules.assess(fuel: fullFuel(), meals: early).isLow, "3.5 h is not just before")
        let light = PreWorkoutMeals(meals: [PreWorkoutMeal(hoursBefore: 1.0, foods: ["Oats"], moreCount: 0, kcal: 400,
                                                           protein: 15, carbs: 60, fat: 8)], carbs24h: 150)
        XCTAssertFalse(FuelRules.assess(fuel: fullFuel(), meals: light).isLow)
    }

    func testUnreliableDataIsNeverLow() {
        var fuel = lowFuel()
        fuel.dataQuality = .unreliable
        XCTAssertFalse(FuelRules.assess(fuel: fuel, meals: nil).isLow)
        XCTAssertFalse(FuelRules.assess(fuel: nil, meals: nil).isLow)
    }

    // MARK: - The guard on the plan

    private let bench = "Smith Machine Flat Bench Press"

    private func history() -> ExerciseHistoryIndex {
        func day(_ d: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: 12)) ?? Date() }
        let sessions = [HistorySession(date: day(20), sets: [HistorySet(160, 3, rir: 4), HistorySet(185, 6, rir: 1), HistorySet(185, 6, rir: 1)])]
        return ExerciseHistoryIndex(groups: [ExerciseHistoryGroup(names: [bench], sessions: sessions, best: HistorySet(230, 1))])
    }

    private func set(_ weight: Double, _ reps: Int, _ rir: Int) -> SetTarget {
        SetTarget(weight: String(format: "%g", weight), reps: String(reps), rir: String(rir), restSeconds: 120)
    }

    private func apply(_ sets: [SetTarget], fuel: FuelAssessment?, goal: GoalAllowance? = nil) -> (AppliedPlan, Exercise) {
        let e = Exercise.create(workoutId: UUID(), name: bench, muscleGroup: "Chest", orderIndex: 0, targetSets: sets.count,
                                targetReps: nil, targetRir: nil, restSeconds: nil, coachNote: nil)
        var parsed = WorkoutSessionService.ParsedPlan(exercises: [e], setTargets: [e.id: sets])
        parsed.coachSetIds = [e.id]
        parsed.reasons = [e.id: "Last 185x6@1, e1RM up."]
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12)) ?? Date()
        let applied = PlanProgressionApplier.apply(
            plan: parsed, history: history(), energy: 6, feedback: nil,
            coach: PlanCoachContext(now: day, goalAllowances: goal.map { [$0] } ?? [], fuelHold: fuel))
        return (applied, e)
    }

    private var raise: [SetTarget] { [set(150, 10, 2), set(195, 5, 1)] }

    func testGuardHoldsARaiseUnderLowFuel() throws {
        let assessment = FuelRules.assess(fuel: lowFuel(), meals: nil)
        let (applied, e) = apply(raise, fuel: assessment)
        let targets = try XCTUnwrap(applied.setTargets[e.id])
        XCTAssertEqual(targets.map(\.prefillWeight), ["150", "185"], "195 is held at the last top set, 185")
        XCTAssertEqual(applied.reasons.first?.text, "Held at 185: eating well under target this week")
        XCTAssertFalse(applied.reasons.first?.railFallback ?? true)
        XCTAssertEqual(applied.evidence[e.id]?.rationale, "Held at 185: eating well under target this week")
        XCTAssertTrue(applied.adjustments.contains { $0.contains("fuel guard held the top weight at 185") })
    }

    func testGuardAllowsTheRaiseWhenWellFuelled() throws {
        let (applied, e) = apply(raise, fuel: FuelRules.assess(fuel: fullFuel(), meals: nil))
        XCTAssertEqual(applied.setTargets[e.id]?.map(\.prefillWeight), ["150", "195"])
        XCTAssertEqual(applied.reasons.first?.text, "Last 185x6@1, e1RM up.")
    }

    func testGuardIgnoresFuelWhenTheDataIsUnreliable() throws {
        var fuel = lowFuel()
        fuel.dataQuality = .unreliable
        let (applied, e) = apply(raise, fuel: FuelRules.assess(fuel: fuel, meals: nil))
        XCTAssertEqual(applied.setTargets[e.id]?.map(\.prefillWeight), ["150", "195"])
    }

    func testGuardLeavesAHoldOrAReductionAlone() throws {
        let assessment = FuelRules.assess(fuel: lowFuel(), meals: nil)
        let hold = apply([set(150, 10, 2), set(185, 5, 1)], fuel: assessment)
        XCTAssertEqual(hold.0.setTargets[hold.1.id]?.map(\.prefillWeight), ["150", "185"])
        XCTAssertEqual(hold.0.reasons.first?.text, "Last 185x6@1, e1RM up.", "nothing changed, so the coach's reason stands")
        let reduce = apply([set(140, 10, 2), set(175, 5, 1)], fuel: assessment)
        XCTAssertEqual(reduce.0.setTargets[reduce.1.id]?.map(\.prefillWeight), ["140", "175"])
    }

    func testGoalAttemptBypassesTheGuardAndGetsAWarning() throws {
        let assessment = FuelRules.assess(fuel: lowFuel(), meals: nil)
        let attempt = GoalAllowance(name: bench, weight: 195, reps: 5)
        let (applied, e) = apply(raise, fuel: assessment, goal: attempt)
        XCTAssertEqual(applied.setTargets[e.id]?.map(\.prefillWeight), ["150", "195"], "the attempt is not lowered")
        XCTAssertEqual(applied.reasons.first?.text, "Goal attempt kept; note: eating well under target this week")
        // Well fuelled: the attempt and the coach's own reason are untouched.
        let fine = apply(raise, fuel: nil, goal: attempt)
        XCTAssertEqual(fine.0.setTargets[fine.1.id]?.map(\.prefillWeight), ["150", "195"])
        XCTAssertEqual(fine.0.reasons.first?.text, "Last 185x6@1, e1RM up.")
    }

    func testHeavyMealWithinTwoHoursHoldsTheLift() throws {
        let heavy = PreWorkoutMeals(meals: [PreWorkoutMeal(hoursBefore: 1.0, foods: ["Burger"], moreCount: 0, kcal: 1100,
                                                           protein: 40, carbs: 95, fat: 60)], carbs24h: 150)
        let (applied, e) = apply(raise, fuel: FuelRules.assess(fuel: fullFuel(), meals: heavy))
        XCTAssertEqual(applied.setTargets[e.id]?.map(\.prefillWeight), ["150", "185"])
        XCTAssertEqual(applied.reasons.first?.text, "Held at 185: a heavy meal just before training")
    }

    func testHoldDoesNotTouchWarmupsOrWithoutAHistory() {
        let assessment = FuelRules.assess(fuel: lowFuel(), meals: nil)
        let warm = SetTarget(weight: "200", reps: "5", rir: "4", isWarmup: true)
        XCTAssertEqual(PlanGuardrails.applyFuelHold([warm], lastTopWeight: 185, hold: assessment).targets, [warm])
        XCTAssertNil(PlanGuardrails.applyFuelHold(raise, lastTopWeight: nil, hold: assessment).heldAt)
        XCTAssertNil(PlanGuardrails.applyFuelHold(raise, lastTopWeight: 185, hold: nil).heldAt)
    }

    // MARK: - Post-workout classification

    private func missedBench(fuel: FuelAssessment?, energy: Int = 8, reasons: [String: String] = [:]) throws -> ExerciseAnalysis {
        let sets = [HistorySet(160, 3, rir: 4), HistorySet(185, 5, rir: 0)]
        let prescription = ExercisePrescription(name: bench, muscleGroup: "Chest", sets: [
            PrescribedSet(weight: 185, reps: 6, rir: 1, role: .top, restSeconds: 150)])
        let analysis = SessionAnalyzer.analyze(
            logged: [LoggedExercise(name: bench, muscleGroup: "Chest", sets: sets, hitPR: false)],
            prescription: [prescription], energy: energy, userNote: nil, reasons: reasons, previous: [], history: history(),
            focus: .hypertrophy, now: nil, fuel: fuel)
        return try XCTUnwrap(analysis.exercises.first)
    }

    func testMissAfterAHeavyMealOrLowFuelIsABadDayFromTheData() throws {
        let low = FuelRules.assess(fuel: lowFuel(), meals: nil)
        let miss = try missedBench(fuel: low)
        XCTAssertEqual(miss.outcome, .missed)
        XCTAssertEqual(miss.miss?.cause, .poorRecovery)
        XCTAssertEqual(miss.miss?.decision, .retry)
        XCTAssertTrue(miss.miss?.reason.contains("eating well under target this week") ?? false, miss.miss?.reason ?? "")

        let heavy = PreWorkoutMeals(meals: [PreWorkoutMeal(hoursBefore: 1.5, foods: ["Burger"], moreCount: 0, kcal: 1100,
                                                           protein: 40, carbs: 95, fat: 60)], carbs24h: 150)
        XCTAssertEqual(try missedBench(fuel: FuelRules.assess(fuel: fullFuel(), meals: heavy)).miss?.cause, .poorRecovery)
    }

    func testMissWithGoodFuelIsNotBlamedOnFood() throws {
        let miss = try missedBench(fuel: FuelRules.assess(fuel: fullFuel(), meals: nil))
        XCTAssertNotEqual(miss.miss?.cause, .poorRecovery)
        let none = try missedBench(fuel: nil)
        XCTAssertNotEqual(none.miss?.cause, .poorRecovery)
    }

    func testTooHeavyStillWinsOverFuel() throws {
        let miss = try missedBench(fuel: FuelRules.assess(fuel: lowFuel(), meals: nil),
                                   reasons: [bench: MissReason.tooHeavy.rawValue])
        XCTAssertEqual(miss.miss?.cause, .strengthLoss)
    }

    // MARK: - What the coach saw

    func testSnapshotKeepsTheExactBlocksAndTheSharingState() throws {
        let defaults = freshDefaults()
        let store = CoachDebugStore(defaults: defaults)
        let id = UUID()
        store.recordRequest(userId: id, workoutType: "Push", model: "m", systemPromptName: "plan", systemPromptLength: 10,
                            userMessage: "hi", nutritionShared: true, mealsShared: true,
                            fuelBlock: "FUEL: x", mealsBlock: "PRE-WORKOUT MEALS: y")
        let saved = try XCTUnwrap(CoachDebugStore(defaults: defaults).lastPlan(forUser: id))
        XCTAssertEqual(saved.fuelBlock, "FUEL: x")
        XCTAssertEqual(saved.mealsBlock, "PRE-WORKOUT MEALS: y")
        XCTAssertEqual(CoachSawView.nutritionText(saved), ["", "NUTRITION SENT", "FUEL: x", "PRE-WORKOUT MEALS: y"])

        store.recordRequest(userId: id, workoutType: "Push", model: "m", systemPromptName: "plan", systemPromptLength: 10,
                            userMessage: "hi", nutritionShared: false, mealsShared: true)
        let off = try XCTUnwrap(store.lastPlan(forUser: id))
        XCTAssertEqual(CoachSawView.nutritionText(off), ["", "NUTRITION SENT", "Nutrition sharing is off"])
    }
}
