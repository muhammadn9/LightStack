import XCTest
import CoreData
import Supabase
@testable import Lightstack

/// Nutrition phase 6 data layer: weigh-ins, profile weight follow-through, dashboard stats, Core Data v11,
/// sync encoding, tombstones and restore.
@MainActor
final class NutritionDashboardTests: XCTestCase {

    private let user = UUID()
    private let calendar = Calendar.current
    private let today = Date().startOfDay

    private func day(_ offset: Int, from base: Date? = nil) -> Date {
        let start = (base ?? today).startOfDay
        return calendar.date(byAdding: .day, value: offset, to: start) ?? start
    }

    /// Tuesday 10 November 2026 (a fixed date for week-based tests).
    private var tuesday: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 10)) ?? today }

    // MARK: - Fixtures

    private struct Device {
        let stack: OutboxTestStack
        let repo: NutritionRepository
        let service: SyncRestoreService
        var storage: LocalStorageService { stack.storage }
        func queuedTypes() async -> [QueuedOperationType] {
            await stack.queue.waitForSubmissions()
            return await stack.queue.queuedOperations().map(\.type)
        }
    }

    private func makeDevice(remote: FakeRemote = FakeRemote(), now: @escaping () -> Date = { Date() }) -> Device {
        let uid = user
        let stack = OutboxTestStack(userId: uid, remote: remote)
        let defaults = UserDefaults(suiteName: "nutri-dash-\(UUID().uuidString)") ?? .standard
        let pr = PRRepository(localStorage: stack.storage, offlineQueueManager: stack.queue)
        let service = SyncRestoreService(remote: remote, storage: stack.storage, queue: stack.queue, prRepository: pr,
                                         currentUserId: { uid }, defaults: defaults, pageSize: 2)
        return Device(stack: stack, repo: NutritionRepository(localStorage: stack.storage, offlineQueueManager: stack.queue, now: now),
                      service: service)
    }

    private func entry(_ date: Date, kcal: Double, p: Double = 0, c: Double = 0, f: Double = 0) -> FoodEntry {
        FoodEntry(id: UUID(), userId: user, date: date.startOfDay, foodId: nil, name: "Food", servings: 1, servingLabel: "1 serving",
                  perServing: NutrientValues(kcal: kcal, protein: p, carbs: c, fat: f), source: .quick,
                  createdAt: Date(), updatedAt: Date())
    }

    private func weighIn(_ date: Date, _ lbs: Double, updated: Date = Date()) -> WeighIn {
        WeighIn(id: UUID(), userId: user, date: date.startOfDay, weightLbs: lbs, createdAt: updated, updatedAt: updated)
    }

    private func plan(_ name: String, mask: Int, kcal: Double, updated: Date = Date()) -> NutritionPlan {
        NutritionPlan(id: UUID(), userId: user, name: name, weekdayMask: mask, protein: kcal / 20, carbs: kcal / 10, fat: kcal / 40,
                      kcal: kcal, kcalOverridden: true, sortOrder: 0, isArchived: false, createdAt: updated, updatedAt: updated)
    }

    private func stats(entries: [FoodEntry] = [], plans: [NutritionPlan] = [], history: [NutritionTarget] = [],
                       weighIns: [WeighIn] = [], loggedDays: Set<Date>? = nil) -> NutritionDashboardStats {
        NutritionDashboardStats(entries: entries, plans: plans, history: history, weighIns: weighIns,
                                loggedDays: loggedDays, calendar: calendar)
    }

    private func profileWeight(_ d: Device) -> Double? {
        d.storage.fetchProfile(userId: user).map { UserProfile(from: $0) }?.weightLbs
    }

    private func seedProfile(_ d: Device, weight: Double = 190) {
        d.storage.saveProfile(UserProfile.create(userId: user, displayName: "T", age: 30, heightInches: 70, weightLbs: weight,
                                                 trainingAgeMonths: 12, primaryGoals: [], splitDays: [], avoidExercises: [],
                                                 equipment: [:], customEquipment: nil, notesToCoach: nil))
    }

    private struct AnyEncodable: Encodable {
        let wrapped: Encodable
        init(_ wrapped: Encodable) { self.wrapped = wrapped }
        func encode(to encoder: Encoder) throws { try wrapped.encode(to: encoder) }
    }

    private func jsonObject<T: NutritionRow>(_ row: T, forCloud: Bool) throws -> [String: Any] {
        let data = try JSONEncoder().encode(forCloud ? AnyEncodable(row.cloudRow()) : AnyEncodable(row))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Weigh-ins

    func testLoggingTwiceOnTheSameDayUpdatesThatDaysRow() async throws {
        let d = makeDevice()
        let first = try XCTUnwrap(d.repo.logWeight(userId: user, 180, unit: .lb, on: today))
        let second = try XCTUnwrap(d.repo.logWeight(userId: user, 181.5, unit: .lb, on: Date()))
        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(d.storage.fetchAllWeighIns(userId: user).count, 1)
        XCTAssertEqual(d.repo.weighIn(userId: user, on: today)?.weightLbs ?? 0, 181.5, accuracy: 0.0001)
        let types = await d.queuedTypes()
        XCTAssertTrue(types.contains(.upsertWeighIn))
    }

    func testKilogramsAreStoredAsPoundsAndConvertedBack() throws {
        let d = makeDevice()
        let saved = try XCTUnwrap(d.repo.logWeight(userId: user, 80, unit: .kg, on: today))
        XCTAssertEqual(saved.weightLbs, 80 * BodyWeightUnit.lbPerKg, accuracy: 0.0001)
        XCTAssertEqual(BodyWeightUnit.kg.fromLbs(saved.weightLbs), 80, accuracy: 0.0001)
        let updated = try XCTUnwrap(d.repo.updateWeighIn(id: saved.id, userId: user, value: 175, unit: .lb))
        XCTAssertEqual(updated.weightLbs, 175, accuracy: 0.0001)
    }

    func testUnitPreferenceReadsTheAppWideSetting() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "unit-pref-\(UUID().uuidString)"))
        XCTAssertEqual(BodyWeightUnit.current(defaults: defaults), .lb)
        defaults.set("kg", forKey: "weightUnit")
        XCTAssertEqual(BodyWeightUnit.current(defaults: defaults), .kg)
        defaults.set("lbs", forKey: "weightUnit")
        XCTAssertEqual(BodyWeightUnit.current(defaults: defaults), .lb)
    }

    func testInvalidWeightsAndFutureDaysAreRejected() {
        let d = makeDevice()
        XCTAssertNil(d.repo.logWeight(userId: user, 0, unit: .lb, on: today))
        XCTAssertNil(d.repo.logWeight(userId: user, -3, unit: .kg, on: today))
        XCTAssertNil(d.repo.logWeight(userId: user, .nan, unit: .lb, on: today))
        XCTAssertNil(d.repo.logWeight(userId: user, .infinity, unit: .lb, on: today))
        XCTAssertNil(d.repo.logWeight(userId: user, 180, unit: .lb, on: day(1)))
        XCTAssertTrue(d.storage.fetchAllWeighIns(userId: user).isEmpty)
    }

    func testRangeAndLatestQueries() {
        let d = makeDevice()
        d.repo.logWeight(userId: user, 182, unit: .lb, on: day(-10))
        d.repo.logWeight(userId: user, 181, unit: .lb, on: day(-5))
        d.repo.logWeight(userId: user, 180, unit: .lb, on: day(-1))
        XCTAssertEqual(d.repo.weighIns(userId: user, in: day(-6)...today).map(\.weightLbs), [181, 180])
        XCTAssertEqual(d.repo.weighIns(userId: user, in: day(-10)...day(-10)).map(\.weightLbs), [182])
        XCTAssertEqual(d.repo.latestWeighIn(userId: user)?.weightLbs, 180)
    }

    // MARK: - Profile weight follows the newest weigh-in

    func testProfileWeightFollowsOnlyTheNewestWeighInThroughLogEditAndDelete() async throws {
        let d = makeDevice()
        seedProfile(d, weight: 190)
        let goals = NutritionGoalSettings.draft(userId: user, profile: nil)
        var settings = goals
        settings.currentWeightLbs = 170
        d.storage.saveGoalSettings(settings)

        let newest = try XCTUnwrap(d.repo.logWeight(userId: user, 180, unit: .lb, on: today))
        XCTAssertEqual(profileWeight(d), 180, "first (and newest) weigh-in updates the profile")

        let old = try XCTUnwrap(d.repo.logWeight(userId: user, 175, unit: .lb, on: day(-5)))
        XCTAssertEqual(profileWeight(d), 180, "an older weigh-in leaves the profile alone")
        d.repo.updateWeighIn(id: old.id, userId: user, value: 176, unit: .lb)
        XCTAssertEqual(profileWeight(d), 180, "editing an older weigh-in leaves the profile alone")

        d.repo.updateWeighIn(id: newest.id, userId: user, value: 181, unit: .lb)
        XCTAssertEqual(profileWeight(d), 181, "editing the newest updates the profile")

        let yesterday = try XCTUnwrap(d.repo.logWeight(userId: user, 179, unit: .lb, on: day(-1)))
        XCTAssertEqual(profileWeight(d), 181)

        d.repo.deleteWeighIn(id: newest.id, userId: user)
        XCTAssertEqual(profileWeight(d), 179, "deleting the newest falls back to the next newest")
        d.repo.deleteWeighIn(id: yesterday.id, userId: user)
        XCTAssertEqual(profileWeight(d), 176)
        d.repo.deleteWeighIn(id: old.id, userId: user)
        XCTAssertEqual(profileWeight(d), 176, "no weigh-ins left: the profile stays as it was")

        XCTAssertEqual(d.storage.fetchGoalSettings(userId: user)?.currentWeightLbs, 170, "goal settings are never touched")
        let types = await d.queuedTypes()
        XCTAssertTrue(types.contains(.upsertProfile))
    }

    func testLoggingKeepsWorkingWithoutALocalProfile() {
        let d = makeDevice()
        XCTAssertNotNil(d.repo.logWeight(userId: user, 180, unit: .lb, on: today))
        XCTAssertNil(d.storage.fetchProfile(userId: user))
    }

    func testProfileUpdateSyncsThroughTheQueue() async throws {
        let remote = FakeRemote()
        let d = makeDevice(remote: remote)
        seedProfile(d, weight: 190)
        d.repo.logWeight(userId: user, 183, unit: .lb, on: today)
        await d.stack.flushAll()
        XCTAssertEqual(remote.weighIns.count, 1)
        XCTAssertTrue(remote.calls.contains { $0.hasPrefix("upsertProfile") })
    }

    // MARK: - Week days and per-day targets

    func testWeekDaysStartOnSundayWithTotalsAndPerWeekdayTargets() throws {
        let weekdayPlan = plan("Weekdays", mask: WeekdayMask.weekdays, kcal: 2000)
        let weekendPlan = plan("Weekend", mask: WeekdayMask.weekend, kcal: 2600)
        let sunday = day(-2, from: tuesday)                      // 8 Nov
        let entries = [entry(tuesday, kcal: 500, p: 30, c: 40, f: 10), entry(tuesday, kcal: 700, p: 20, c: 60, f: 15),
                       entry(sunday, kcal: 900)]
        let week = stats(entries: entries, plans: [weekdayPlan, weekendPlan]).weekDays(containing: tuesday)

        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.map { calendar.component(.weekday, from: $0.date) }, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(week.first?.date, sunday)
        XCTAssertEqual(week.last?.date, day(4, from: tuesday))
        XCTAssertEqual(week.map { $0.target?.kcal }, [2600, 2000, 2000, 2000, 2000, 2000, 2600])
        let tue = week[2]
        XCTAssertEqual(tue.totals.kcal, 1200, accuracy: 0.001)
        XCTAssertEqual(tue.totals.protein, 50, accuracy: 0.001)
        XCTAssertEqual(tue.totals.carbs, 100, accuracy: 0.001)
        XCTAssertEqual(tue.totals.fat, 25, accuracy: 0.001)
        XCTAssertEqual(tue.entryCount, 2)
        XCTAssertTrue(tue.hasLog)
        XCTAssertEqual(week[0].totals.kcal, 900)
        XCTAssertFalse(week[1].hasLog)
        XCTAssertEqual(week[1].totals.kcal, 0)
    }

    func testWeekDaysFallBackToTargetHistoryAndCanStartOnMonday() throws {
        let target = NutritionTarget.make(userId: user, effectiveDate: day(-30, from: tuesday), protein: 150, carbs: 200, fat: 60)
        let week = stats(history: [target]).weekDays(containing: tuesday, weekStartsOn: 2)
        XCTAssertEqual(week.map { calendar.component(.weekday, from: $0.date) }, [2, 3, 4, 5, 6, 7, 1])
        XCTAssertEqual(week.first?.date, day(-1, from: tuesday))
        XCTAssertTrue(week.allSatisfy { $0.target?.id == target.id })
        XCTAssertTrue(stats().weekDays(containing: tuesday).allSatisfy { $0.target == nil })
        // A Sunday anchors its own week, and so does a Saturday.
        let sunday = day(-2, from: tuesday)
        XCTAssertEqual(stats().weekDays(containing: sunday).first?.date, sunday)
        let saturday = day(-3, from: tuesday)                    // 7 Nov: still in the week that began on 1 Nov
        XCTAssertEqual(stats().weekDays(containing: saturday).first?.date, day(-7, from: sunday))
        XCTAssertEqual(stats().weekDays(containing: saturday).last?.date, saturday)
    }

    // MARK: - Grids

    func testGridsAreThirtyCellsEndingOnTheDateOldestFirst() {
        let s = stats(entries: [entry(tuesday, kcal: 100), entry(day(-3, from: tuesday), kcal: 100), entry(day(-29, from: tuesday), kcal: 100),
                                entry(day(-30, from: tuesday), kcal: 100)],
                      weighIns: [weighIn(day(-1, from: tuesday), 180), weighIn(day(-29, from: tuesday), 182)])
        let food = s.foodLogGrid(endingOn: tuesday, days: 30)
        XCTAssertEqual(food.count, 30)
        XCTAssertEqual(food.first?.date, day(-29, from: tuesday))
        XCTAssertEqual(food.last?.date, tuesday)
        XCTAssertEqual(food.filter(\.hasLog).map(\.date), [day(-29, from: tuesday), day(-3, from: tuesday), tuesday])
        XCTAssertEqual(s.foodLogGrid(endingOn: tuesday).count, 30, "default is 30 days")

        let weights = s.weighInGrid(endingOn: tuesday, days: 30)
        XCTAssertEqual(weights.count, 30)
        XCTAssertEqual(weights.filter(\.hasWeighIn).map(\.date), [day(-29, from: tuesday), day(-1, from: tuesday)])
        XCTAssertTrue(stats().foodLogGrid(endingOn: tuesday).allSatisfy { !$0.hasLog })
    }

    // MARK: - Streaks

    private func logged(_ offsets: [Int], from base: Date? = nil) -> NutritionDashboardStats {
        stats(entries: offsets.map { entry(day($0, from: base), kcal: 100) })
    }

    func testStreakCountsTodayWhenLogged() {
        let s = logged([0, -1, -2])
        XCTAssertEqual(s.currentLogStreak(asOf: today), 3)
        XCTAssertEqual(s.bestLogStreak, 3)
    }

    func testStreakContinuesFromYesterdayWhenTodayIsNotLoggedYet() {
        let s = logged([-1, -2, -3, -4])
        XCTAssertEqual(s.currentLogStreak(asOf: today), 4)
    }

    func testStreakIsZeroWhenNeitherTodayNorYesterdayIsLogged() {
        let s = logged([-2, -3, -4])
        XCTAssertEqual(s.currentLogStreak(asOf: today), 0)
        XCTAssertEqual(s.bestLogStreak, 3)
        XCTAssertEqual(stats().currentLogStreak(asOf: today), 0)
        XCTAssertEqual(stats().bestLogStreak, 0)
    }

    func testStreakGapsAndBestVersusCurrent() {
        let s = logged([0, -1, -3, -4, -5, -6, -7, -9])
        XCTAssertEqual(s.currentLogStreak(asOf: today), 2, "the gap at -2 ends the run")
        XCTAssertEqual(s.bestLogStreak, 5, "-3 ... -7 is the longest run")
    }

    func testSingleDayStreak() {
        XCTAssertEqual(logged([0]).currentLogStreak(asOf: today), 1)
        XCTAssertEqual(logged([0]).bestLogStreak, 1)
        XCTAssertEqual(logged([-1]).currentLogStreak(asOf: today), 1)
        XCTAssertEqual(logged([-5]).currentLogStreak(asOf: today), 0)
        XCTAssertEqual(logged([-5]).bestLogStreak, 1)
    }

    func testMultipleEntriesOnOneDayCountOnce() {
        let s = stats(entries: [entry(today, kcal: 1), entry(today, kcal: 1), entry(day(-1), kcal: 1)])
        XCTAssertEqual(s.currentLogStreak(asOf: today), 2)
        XCTAssertEqual(s.bestLogStreak, 2)
    }

    func testWiderLoggedDaySetExtendsStreaksBeyondTheEntryWindow() {
        let older = Set((-20...(-10)).map { day($0) })
        let s = stats(entries: [entry(today, kcal: 1)], loggedDays: older)
        XCTAssertEqual(s.currentLogStreak(asOf: today), 1)
        XCTAssertEqual(s.bestLogStreak, 11)
    }

    // MARK: - Weight change

    func testWeightChangeIsLatestMinusEarliestInTheWindow() {
        let s = stats(weighIns: [weighIn(day(-40), 190), weighIn(day(-25), 185), weighIn(day(-10), 183), weighIn(day(-1), 181.5)])
        XCTAssertEqual(try XCTUnwrap(s.weightChange(overDays: 30, endingOn: today)), -3.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(s.weightChange(overDays: 90, endingOn: today)), -8.5, accuracy: 0.0001)
        XCTAssertNil(s.weightChange(overDays: 5, endingOn: today), "only one weigh-in in the last 5 days")
    }

    func testWeightChangeIsNilWithFewerThanTwoWeighIns() {
        XCTAssertNil(stats().weightChange(overDays: 30, endingOn: today))
        XCTAssertNil(stats(weighIns: [weighIn(day(-3), 180)]).weightChange(overDays: 30, endingOn: today))
        XCTAssertNil(stats(weighIns: [weighIn(day(-3), 180), weighIn(day(-60), 190)]).weightChange(overDays: 30, endingOn: today),
                     "the second weigh-in is outside the window")
    }

    func testWeightChangeWindowIsInclusiveOfTheFirstDay() {
        let s = stats(weighIns: [weighIn(day(-29), 200), weighIn(day(-30), 250), weighIn(today, 190)])
        XCTAssertEqual(try XCTUnwrap(s.weightChange(overDays: 30, endingOn: today)), -10, accuracy: 0.0001)
    }

    // MARK: - Range summary

    func testRangeSummaryAveragesOverLoggedDaysOnly() throws {
        let s = stats(entries: [entry(day(-1), kcal: 2000, p: 150, c: 200, f: 60), entry(day(-2), kcal: 1000, p: 50, c: 100, f: 20),
                                entry(day(-2), kcal: 1000, p: 50, c: 100, f: 20), entry(day(-40), kcal: 9999)])
        let r = s.rangeSummary(days: 28, endingOn: today)
        XCTAssertEqual(r.days, 28)
        XCTAssertEqual(r.loggedDays, 2, "27 unlogged days do not drag the average down")
        XCTAssertEqual(r.avgKcal, 2000, accuracy: 0.001)
        XCTAssertEqual(r.avgProtein, 125, accuracy: 0.001)
        XCTAssertEqual(r.avgCarbs, 200, accuracy: 0.001)
        XCTAssertEqual(r.avgFat, 50, accuracy: 0.001)
        let wide = s.rangeSummary(days: 90, endingOn: today)
        XCTAssertEqual(wide.loggedDays, 3)
        XCTAssertEqual(wide.days, 90)
    }

    func testDaysOnTargetUsesTenPercentOfThatDaysTarget() {
        XCTAssertEqual(NutritionDashboardStats.onTargetTolerance, 0.10)
        let target = NutritionTarget.make(userId: user, effectiveDate: day(-100), protein: 0, carbs: 0, fat: 0, kcalOverride: 2000)
        let entries = [entry(day(-1), kcal: 2200),       // exactly +10%: on target
                       entry(day(-2), kcal: 1800),       // exactly -10%: on target
                       entry(day(-3), kcal: 2201),       // just over
                       entry(day(-4), kcal: 1799),       // just under
                       entry(day(-5), kcal: 2000)]
        let r = stats(entries: entries, history: [target]).rangeSummary(days: 28, endingOn: today)
        XCTAssertEqual(r.loggedDays, 5)
        XCTAssertEqual(r.loggedDaysWithTarget, 5)
        XCTAssertEqual(r.daysOnTarget, 3)
    }

    func testDaysOnTargetUsesTheWeekdayPlanOfEachDay() {
        // Weekday plan 2000 kcal, weekend plan 3000 kcal; every logged day eats 2000 kcal.
        let plans = [plan("Weekdays", mask: WeekdayMask.weekdays, kcal: 2000), plan("Weekend", mask: WeekdayMask.weekend, kcal: 3000)]
        let days = (0..<7).map { day(-$0, from: tuesday) }
        let r = stats(entries: days.map { entry($0, kcal: 2000) }, plans: plans).rangeSummary(days: 7, endingOn: tuesday)
        let weekdayCount = days.filter { ![1, 7].contains(calendar.component(.weekday, from: $0)) }.count
        XCTAssertEqual(r.daysOnTarget, weekdayCount)
        XCTAssertEqual(r.loggedDaysWithTarget, 7)
    }

    func testRangeSummaryWithoutTargetsOrLogs() {
        let noTarget = stats(entries: [entry(day(-1), kcal: 1500)]).rangeSummary(days: 28, endingOn: today)
        XCTAssertEqual(noTarget.loggedDays, 1)
        XCTAssertEqual(noTarget.daysOnTarget, 0)
        XCTAssertEqual(noTarget.loggedDaysWithTarget, 0)
        XCTAssertEqual(stats().rangeSummary(days: 90, endingOn: today), .empty(days: 90))
    }

    // MARK: - View model

    func testViewModelDashboardShapeAndUnit() throws {
        UserDefaults.standard.set("kg", forKey: BodyWeightUnit.preferenceKey)
        defer { UserDefaults.standard.removeObject(forKey: BodyWeightUnit.preferenceKey) }
        let d = makeDevice()
        let uid = user
        let vm = NutritionViewModel(repository: d.repo, userIdProvider: { uid })
        vm.reload()
        d.storage.saveFoodEntry(entry(today, kcal: 500))
        d.storage.saveFoodEntry(entry(day(-1), kcal: 500))
        let saved = try XCTUnwrap(vm.logWeight(80))
        XCTAssertEqual(saved.weightLbs, 80 * BodyWeightUnit.lbPerKg, accuracy: 0.0001, "unit defaults to the preference (kg)")
        vm.logWeight(176.37, unit: .lb, on: day(-10))
        XCTAssertEqual(vm.bodyWeightUnit, .kg)

        let dash = try XCTUnwrap(vm.dashboard(for: today))
        XCTAssertEqual(dash.unit, .kg)
        XCTAssertEqual(dash.week.count, 7)
        XCTAssertEqual(dash.foodLogGrid.count, 30)
        XCTAssertEqual(dash.weighInGrid.count, 30)
        XCTAssertEqual(dash.currentStreak, 2)
        XCTAssertEqual(dash.bestStreak, 2)
        XCTAssertEqual(try XCTUnwrap(dash.latestWeight).value, 80, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(dash.weightOnDate).value, 80, accuracy: 0.0001)
        XCTAssertEqual(dash.weightSeries.count, 2)
        XCTAssertEqual(try XCTUnwrap(dash.weightChange30Days), 80 - 176.37 / BodyWeightUnit.lbPerKg, accuracy: 0.001)
        XCTAssertEqual(dash.range28.loggedDays, 2)
        XCTAssertEqual(dash.range90.days, 90)
        XCTAssertNil(try XCTUnwrap(vm.dashboard(for: day(-3))).weightOnDate)

        vm.deleteWeighIn(saved)
        XCTAssertEqual(vm.latestWeighIn()?.weightLbs ?? 0, 176.37, accuracy: 0.0001)
    }

    // MARK: - Core Data v11

    func testMigratesV10StoreToV11AddsWeighInsAndKeepsData() throws {
        let bundle = Bundle(for: LocalStorageService.self)
        let v10URL = try XCTUnwrap(bundle.url(forResource: "Lightstack 10", withExtension: "mom", subdirectory: "Lightstack.momd"))
        let v11URL = try XCTUnwrap(bundle.url(forResource: "Lightstack 11", withExtension: "mom", subdirectory: "Lightstack.momd"))
        let v10Model = try XCTUnwrap(NSManagedObjectModel(contentsOf: v10URL))
        let v11Model = try XCTUnwrap(NSManagedObjectModel(contentsOf: v11URL))
        XCTAssertNil(v10Model.entitiesByName["CDWeighIn"])
        XCTAssertNotNil(v11Model.entitiesByName["CDWeighIn"])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("Lightstack.sqlite")
        let waterId = UUID()
        do {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: v10Model)
            let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
            let ctx = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            ctx.persistentStoreCoordinator = coordinator
            try ctx.performAndWait {
                let e = NSEntityDescription.insertNewObject(forEntityName: "CDWaterEntry", into: ctx)
                e.setValue(waterId, forKey: "id"); e.setValue(UUID(), forKey: "userId")
                e.setValue(Date(), forKey: "date"); e.setValue(500.0, forKey: "amountMl")
                e.setValue(Date(), forKey: "createdAt"); e.setValue(Date(), forKey: "updatedAt")
                try ctx.save()
            }
            try coordinator.remove(store)
        }
        let container = NSPersistentContainer(name: "Lightstack")
        let desc = NSPersistentStoreDescription(url: storeURL)
        desc.shouldMigrateStoreAutomatically = true
        desc.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [desc]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError, "Migration failed: \(String(describing: loadError))")
        let ctx = container.viewContext
        let migrated = try XCTUnwrap(ctx.fetch(CDWaterEntry.fetchRequest() as NSFetchRequest<CDWaterEntry>).first)
        XCTAssertEqual(migrated.id, waterId)
        XCTAssertEqual(migrated.amountMl, 500)
        XCTAssertEqual(try ctx.count(for: CDWeighIn.fetchRequest() as NSFetchRequest<CDWeighIn>), 0)
    }

    func testCoreDataRoundTripOfWeighIns() {
        let d = makeDevice()
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let w = WeighIn(id: UUID(), userId: user, date: today, weightLbs: 181.25, createdAt: stamp, updatedAt: stamp)
        d.storage.saveWeighIn(w)
        XCTAssertEqual(d.storage.fetchWeighIn(id: w.id), w)
        XCTAssertEqual(d.storage.fetchWeighIn(userId: user, on: today.addingTimeInterval(7200)), w)
        XCTAssertEqual(d.storage.fetchLatestWeighIn(userId: user), w)
        XCTAssertEqual(d.storage.deleteWeighIns(ids: [w.id]), 1)
        XCTAssertNil(d.storage.fetchWeighIn(id: w.id))
    }

    // MARK: - Wire format and migration file

    func testWeighInEncodesEveryColumnTheMigrationDefines() throws {
        let stamp = Date()
        let w = WeighIn.make(userId: user, date: today, weightLbs: 180.5, now: stamp)
        for forCloud in [true, false] {
            let json = try jsonObject(w, forCloud: forCloud)
            for column in ["id", "user_id", "date", "weight_lbs", "created_at", "updated_at"] {
                XCTAssertNotNil(json[column], "weigh_ins.\(column) missing (cloud=\(forCloud))")
            }
            XCTAssertEqual(json["weight_lbs"] as? Double, 180.5)
            XCTAssertEqual(json.count, 6)
        }
        XCTAssertEqual(try jsonObject(w, forCloud: true)["date"] as? String, RemoteDate.dayString(today))
        XCTAssertEqual(try JSONDecoder().decode(WeighIn.self, from: JSONEncoder().encode(w)), w)
        let cloudJSON = Data(#"{"id":"\#(w.id.uuidString)","user_id":"\#(user.uuidString)","date":"2026-11-10","weight_lbs":181.2}"#.utf8)
        let decoded = try JSONDecoder().decode(WeighIn.self, from: cloudJSON)
        XCTAssertEqual(decoded.weightLbs, 181.2, accuracy: 0.0001)
        XCTAssertEqual(decoded.date, tuesday)
    }

    func testMigrationFileMatchesTheWireFormatAndKeepsEveryConstraintValue() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let sql = try String(contentsOf: root.appendingPathComponent("supabase/migrations/20261110120000_nutrition_weigh_ins.sql"), encoding: .utf8)
        let schema = try String(contentsOf: root.appendingPathComponent("supabase/supabase_schema.sql"), encoding: .utf8)
        for raw in [sql, schema] {
            let text = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            for column in ["weight_lbs numeric NOT NULL CHECK (weight_lbs > 0)", "UNIQUE (user_id, date)", "created_at", "updated_at",
                           "ENABLE ROW LEVEL SECURITY", "GRANT ALL ON public.weigh_ins TO authenticated", "auth.uid() = user_id"] {
                XCTAssertTrue(text.contains(column), column)
            }
            for entity in ["workout", "exercise", "set", "personal_record", "month_plan", "planned_session", "rest_day",
                           "nutrition_target", "food", "food_entry", "meal_slot", "water_entry", "day_note",
                           "food_collection", "food_collection_item", "weigh_in"] {
                XCTAssertTrue(text.contains("'\(entity)'"), "tombstone entity \(entity)")
            }
        }
        XCTAssertTrue(sql.contains("IF NOT EXISTS") && !sql.contains("DROP TABLE") && sql.contains("DROP POLICY IF EXISTS"))
    }

    func testTombstoneEntityAndQueueTypesHaveTheMigrationNames() {
        XCTAssertEqual(TombstoneEntity.weighIn.rawValue, "weigh_in")
        XCTAssertEqual(SyncErrorClassifier.classify(PostgrestError(code: "PGRST205", message: "x"), opType: .upsertWeighIn), .dependency)
        XCTAssertEqual(SyncErrorClassifier.classify(PostgrestError(code: "23514", message: "check"), opType: .insertTombstone), .dependency)
    }

    // MARK: - Sync

    func testFlushUploadsWeighInsAndTwoDevicesOnOneDayNeverCollide() async throws {
        let remote = FakeRemote()
        let a = makeDevice(remote: remote)
        let b = makeDevice(remote: remote)
        a.repo.logWeight(userId: user, 180, unit: .lb, on: today)
        b.repo.logWeight(userId: user, 181, unit: .lb, on: today)     // different random id, same day
        await a.stack.flushAll()
        await b.stack.flushAll()
        XCTAssertEqual(remote.weighIns.count, 1, "one row per (user, day): the cloud upsert is on (user_id, date)")
        XCTAssertEqual(remote.weighIns.values.first?.weightLbs, 181)
    }

    func testDeleteQueuesDeleteAndTombstoneAndReLoggingGetsAFreshId() async throws {
        let remote = FakeRemote()
        let d = makeDevice(remote: remote)
        let first = try XCTUnwrap(d.repo.logWeight(userId: user, 180, unit: .lb, on: today))
        await d.stack.flushAll()
        XCTAssertNotNil(remote.weighIns[first.id])
        d.repo.deleteWeighIn(id: first.id, userId: user)
        XCTAssertNil(d.repo.weighIn(userId: user, on: today))
        let again = try XCTUnwrap(d.repo.logWeight(userId: user, 182, unit: .lb, on: today))
        XCTAssertNotEqual(again.id, first.id, "a deterministic id would collide with the tombstone")
        let types = await d.queuedTypes()
        XCTAssertTrue(types.contains(.deleteWeighIn) && types.contains(.insertTombstone))
        await d.stack.flushAll()
        XCTAssertTrue(remote.tombstones.contains("weigh_in:\(first.id.uuidString)"))
        XCTAssertEqual(remote.weighIns.count, 1)
        XCTAssertEqual(remote.weighIns[again.id]?.weightLbs, 182)
    }

    func testRestoreBringsBackWeighInsOnAFreshDeviceAndAppliesTombstones() async throws {
        let remote = FakeRemote()
        let cloud = WeighIn.make(userId: user, date: day(-3), weightLbs: 178)
        let gone = WeighIn.make(userId: user, date: day(-2), weightLbs: 179)
        remote.seedWeighIn(cloud)
        remote.seedWeighIn(gone)
        remote.seedTombstone(.weighIn, gone.id)
        let d = makeDevice(remote: remote)
        let stale = WeighIn.make(userId: user, date: day(-7), weightLbs: 190)
        d.storage.saveWeighIn(stale)
        remote.seedTombstone(.weighIn, stale.id)

        _ = try await d.service.restoreAll(userId: user, assumeFreshInstall: true)
        XCTAssertEqual(d.storage.fetchWeighIn(id: cloud.id)?.weightLbs, 178)
        XCTAssertNil(d.storage.fetchWeighIn(id: gone.id), "tombstoned cloud rows are not restored")
        XCTAssertNil(d.storage.fetchWeighIn(id: stale.id), "a tombstone removes the local row")
    }

    func testRestoreDropsAnOlderLocalRowForTheSameDayAndKeepsTheNewerCloudOne() async throws {
        let remote = FakeRemote()
        let d = makeDevice(remote: remote)
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        let local = WeighIn(id: UUID(), userId: user, date: day(-4), weightLbs: 170, createdAt: old, updatedAt: old)
        d.storage.saveWeighIn(local)
        let cloud = WeighIn.make(userId: user, date: day(-4), weightLbs: 171)
        remote.seedWeighIn(cloud)
        _ = try await d.service.restoreAll(userId: user, assumeFreshInstall: true)
        let rows = d.storage.fetchAllWeighIns(userId: user)
        XCTAssertEqual(rows.map(\.id), [cloud.id])
        XCTAssertEqual(rows.first?.weightLbs, 171)
        let types = await d.queuedTypes()
        XCTAssertFalse(types.contains(.upsertWeighIn))
    }

    func testRestoreKeepsAndUploadsANewerLocalRowForTheSameDay() async throws {
        let remote = FakeRemote()
        let d = makeDevice(remote: remote)
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        let cloud = WeighIn(id: UUID(), userId: user, date: day(-4), weightLbs: 171, createdAt: old, updatedAt: old)
        remote.seedWeighIn(cloud)
        let local = WeighIn.make(userId: user, date: day(-4), weightLbs: 172)
        d.storage.saveWeighIn(local)
        _ = try await d.service.restoreAll(userId: user, assumeFreshInstall: true)
        XCTAssertEqual(d.storage.fetchAllWeighIns(userId: user).map(\.id), [local.id])
        await d.stack.flushAll()
        XCTAssertEqual(remote.weighIns.count, 1)
        XCTAssertEqual(remote.weighIns[local.id]?.weightLbs, 172, "the newer edit won in the cloud too")
    }

    func testRepairUploadsALostWeighInButNotOneTheCloudAlreadyHasForThatDay() async throws {
        let remote = FakeRemote()
        let d = makeDevice(remote: remote)
        let lost = WeighIn.make(userId: user, date: day(-1), weightLbs: 180)
        d.storage.saveWeighIn(lost)                                   // no queue: like a lost write
        let summary = try await d.service.restoreAll(userId: user, assumeFreshInstall: true)
        XCTAssertGreaterThanOrEqual(summary.repairedNutrition, 1)
        await d.stack.flushAll()
        XCTAssertNotNil(remote.weighIns[lost.id])
    }

    func testProfileWeightIsNotChangedByRestore() async throws {
        let remote = FakeRemote()
        remote.seedWeighIn(WeighIn.make(userId: user, date: day(-1), weightLbs: 150))
        let d = makeDevice(remote: remote)
        seedProfile(d, weight: 190)
        _ = try await d.service.restoreAll(userId: user, assumeFreshInstall: true)
        XCTAssertEqual(profileWeight(d), 190)
    }
}
