import XCTest
import CoreData
import Supabase
@testable import Lightstack

/// Nutrition phase 2 data layer: Core Data v6 -> v7, goal calculator, weekday plans, persistence, wire format,
/// sync and the missing-table safety net.
@MainActor
final class NutritionGoalsTests: XCTestCase {

    private let user = UUID()
    private let today = Date().startOfDay

    private struct Device {
        let stack: OutboxTestStack
        let repo: NutritionRepository
        let service: SyncRestoreService
        var storage: LocalStorageService { stack.storage }
    }

    private func makeDevice(remote: FakeRemote = FakeRemote()) -> Device {
        let uid = user
        let stack = OutboxTestStack(userId: uid, remote: remote)
        let defaults = UserDefaults(suiteName: "nutri-goals-\(UUID().uuidString)") ?? .standard
        let pr = PRRepository(localStorage: stack.storage, offlineQueueManager: stack.queue)
        let service = SyncRestoreService(remote: remote, storage: stack.storage, queue: stack.queue, prRepository: pr,
                                         currentUserId: { uid }, defaults: defaults, pageSize: 2)
        return Device(stack: stack, repo: NutritionRepository(localStorage: stack.storage, offlineQueueManager: stack.queue), service: service)
    }

    private func settings(goal: NutritionGoal = .lose, sex: NutritionSex = .male, age: Int = 30, height: Double = 70,
                          weight: Double = 180, target: Double = 165, rate: Double = 1, activity: NutritionActivityLevel = .lightlyActive,
                          lifts: Bool = true) -> NutritionGoalSettings {
        NutritionGoalSettings(id: NutritionGoalSettings.id(userId: user), userId: user, goal: goal, sex: sex, age: age,
                              heightInches: height, currentWeightLbs: weight, targetWeightLbs: target, weeklyRateLbs: rate,
                              activityLevel: activity, liftsWeights: lifts, unit: .lb, completedAt: nil,
                              createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 100))
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

    // Calendar weekdays
    private let sun = 1, mon = 2, tue = 3, wed = 4, thu = 5, fri = 6, sat = 7

    /// The next date (from a fixed anchor) falling on the given Calendar weekday.
    private func date(weekday: Int) -> Date {
        var d = Date(timeIntervalSince1970: 1_800_000_000).startOfDay
        while Calendar.current.component(.weekday, from: d) != weekday { d = d.addingTimeInterval(86_400) }
        return d.startOfDay
    }

    // MARK: - Migration 6 -> 7

    func testMigratesV6StoreToV7AddsGoalEntitiesAndKeepsData() throws {
        let bundle = Bundle(for: LocalStorageService.self)
        let v6URL = try XCTUnwrap(bundle.url(forResource: "Lightstack 6", withExtension: "mom", subdirectory: "Lightstack.momd"))
        let v7URL = try XCTUnwrap(bundle.url(forResource: "Lightstack 7", withExtension: "mom", subdirectory: "Lightstack.momd"))
        let v6Model = try XCTUnwrap(NSManagedObjectModel(contentsOf: v6URL))
        let v7Model = try XCTUnwrap(NSManagedObjectModel(contentsOf: v7URL))
        for name in ["CDNutritionPlan", "CDNutritionGoalSettings"] {
            XCTAssertNil(v6Model.entitiesByName[name])
            XCTAssertNotNil(v7Model.entitiesByName[name])
        }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("Lightstack.sqlite")
        let slotId = UUID()

        do {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: v6Model)
            let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
            let ctx = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            ctx.persistentStoreCoordinator = coordinator
            try ctx.performAndWait {
                let e = NSEntityDescription.insertNewObject(forEntityName: "CDMealSlot", into: ctx)
                e.setValue(slotId, forKey: "id"); e.setValue(UUID(), forKey: "userId")
                e.setValue("Breakfast", forKey: "name")
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
        let migrated = try XCTUnwrap(ctx.fetch(CDMealSlot.fetchRequest() as NSFetchRequest<CDMealSlot>).first)
        XCTAssertEqual(migrated.id, slotId)
        XCTAssertEqual(migrated.name, "Breakfast")
        XCTAssertEqual(try ctx.count(for: CDNutritionPlan.fetchRequest() as NSFetchRequest<CDNutritionPlan>), 0)

        let plan = CDNutritionPlan(context: ctx)
        NutritionPlan(id: UUID(), userId: user, name: "P", weekdayMask: 127, protein: 1, carbs: 1, fat: 1, kcal: 17,
                      kcalOverridden: false, sortOrder: 0, isArchived: false, createdAt: Date(), updatedAt: Date()).apply(to: plan)
        let goals = CDNutritionGoalSettings(context: ctx)
        settings().apply(to: goals)
        try ctx.save()
        XCTAssertEqual(try ctx.count(for: CDNutritionPlan.fetchRequest() as NSFetchRequest<CDNutritionPlan>), 1)
    }

    // MARK: - Calculator

    func testMifflinBmrKnownValues() {
        // Male 30y, 70 in (177.8 cm), 180 lb (81.6466 kg): 816.466 + 1111.25 - 150 + 5
        XCTAssertEqual(NutritionCalculator.bmr(sex: .male, age: 30, heightInches: 70, weightLbs: 180), 1782.72, accuracy: 0.05)
        // Female 30y, 64 in (162.56 cm), 140 lb (63.5029 kg): 635.029 + 1016 - 150 - 161
        XCTAssertEqual(NutritionCalculator.bmr(sex: .female, age: 30, heightInches: 64, weightLbs: 140), 1340.03, accuracy: 0.05)
    }

    func testActivityMultipliers() {
        XCTAssertEqual(NutritionActivityLevel.allCases.map(\.multiplier), [1.2, 1.375, 1.55, 1.725])
        let bmr = 1782.72
        XCTAssertEqual(NutritionCalculator.tdee(bmr: bmr, activity: .active), bmr * 1.55, accuracy: 0.001)
    }

    func testMaintainEqualsTdeeAndMacrosAddUp() {
        let s = settings(goal: .maintain, target: 180, rate: 0, lifts: false)
        let r = NutritionCalculator.calculate(s)
        XCTAssertEqual(r.tdee, 1782.72 * 1.375, accuracy: 0.1)
        XCTAssertEqual(r.kcal, r.tdee, accuracy: 15, "within rounding of TDEE")
        XCTAssertEqual(r.proteinGrams, 144)                     // 0.8 g/lb x 180
        XCTAssertEqual(r.fatGrams, (r.kcal * 0.27 / 9).rounded(), accuracy: 3)
        XCTAssertEqual(r.kcal, r.proteinGrams * 4 + r.carbsGrams * 4 + r.fatGrams * 9, accuracy: 0.001)
        XCTAssertEqual(r.proteinPercent + r.carbsPercent + r.fatPercent, 100, accuracy: 2)
        XCTAssertNil(r.projectedGoalDate)
        XCTAssertEqual(r.weeklyRateLbs, 0)
    }

    func testLoseSubtractsRateTimes500AndUsesTargetWeightForProtein() {
        let r = NutritionCalculator.calculate(settings(goal: .lose, weight: 180, target: 165, rate: 1, lifts: true))
        XCTAssertEqual(r.kcal, r.tdee - 500, accuracy: 15)
        XCTAssertEqual(r.proteinGrams, 165, "1.0 g/lb of target weight when losing and lifting")
        XCTAssertFalse(r.flooredByMinimum)
        XCTAssertEqual(r.weeklyRateLbs, 1)
    }

    func testGainAddsSurplus() {
        let r = NutritionCalculator.calculate(settings(goal: .gain, weight: 160, target: 170, rate: 0.5))
        XCTAssertEqual(r.kcal, r.tdee + 250, accuracy: 15)
        XCTAssertEqual(r.proteinGrams, 160, "current weight when gaining")
    }

    func testRateClampAndRecommended() {
        // 200 lb: lose range 0.25 ... 2.0 (1% = 2.0); asking for 5 lb/week is clamped.
        XCTAssertEqual(NutritionCalculator.calculate(settings(weight: 200, target: 180, rate: 5)).weeklyRateLbs, 2.0)
        XCTAssertEqual(NutritionCalculator.calculate(settings(weight: 200, target: 180, rate: 0.01)).weeklyRateLbs, 0.25)
        // 120 lb: max loss is 1% = 1.2
        XCTAssertEqual(NutritionCalculator.rateRange(goal: .lose, weightLbs: 120).max, 1.2, accuracy: 0.001)
        XCTAssertEqual(NutritionCalculator.recommendedRate(goal: .lose, weightLbs: 200), 1.5)   // 0.75% = 1.5
        XCTAssertEqual(NutritionCalculator.recommendedRate(goal: .lose, weightLbs: 120), 1.0)   // 0.9 -> 1.0 (nearest 0.25)
        XCTAssertEqual(NutritionCalculator.recommendedRate(goal: .gain, weightLbs: 100), 0.25)
        XCTAssertEqual(NutritionCalculator.recommendedRate(goal: .gain, weightLbs: 160), 0.5)
        XCTAssertEqual(NutritionCalculator.recommendedRate(goal: .gain, weightLbs: 240), 0.5)
        XCTAssertEqual(NutritionCalculator.recommendedRate(goal: .maintain, weightLbs: 180), 0)
        // Maintain ignores any rate.
        XCTAssertEqual(NutritionCalculator.calculate(settings(goal: .maintain, rate: 2)).weeklyRateLbs, 0)
    }

    func testCalorieFloorAndAdjustedRate() {
        // Small sedentary woman asking for a big deficit hits the 1200 floor.
        let s = settings(goal: .lose, sex: .female, age: 45, height: 60, weight: 110, target: 100, rate: 1, activity: .sedentary, lifts: false)
        let r = NutritionCalculator.calculate(s)
        XCTAssertTrue(r.flooredByMinimum)
        XCTAssertEqual(r.kcal, 1200, accuracy: 15)
        XCTAssertLessThan(r.weeklyRateLbs, 1, "the applied rate is gentler than the one asked for")
        XCTAssertEqual(NutritionCalculator.calorieFloor(for: .male), 1500)
        let male = NutritionCalculator.calculate(settings(goal: .lose, sex: .male, age: 60, height: 62, weight: 130, target: 120, rate: 1, activity: .sedentary))
        XCTAssertGreaterThanOrEqual(male.kcal, 1490)
    }

    func testProjectedGoalDate() {
        let now = date(weekday: mon)
        let s = settings(goal: .lose, weight: 180, target: 170, rate: 1)
        let r = NutritionCalculator.calculate(s, now: now)
        let expected = Calendar.current.date(byAdding: .day, value: 70, to: now)   // 10 lb at 1 lb/week
        XCTAssertEqual(r.projectedGoalDate, expected)
        // Target on the wrong side of the goal: no date.
        XCTAssertNil(NutritionCalculator.calculate(settings(goal: .lose, weight: 180, target: 190, rate: 1), now: now).projectedGoalDate)
    }

    // MARK: - Weekday masks and resolution

    func testWeekdayMaskHelpers() {
        XCTAssertEqual(WeekdayMask.bit(weekday: sun), 1)
        XCTAssertEqual(WeekdayMask.bit(weekday: sat), 64)
        XCTAssertEqual(WeekdayMask.mask(weekdays: [mon, tue, wed, thu, fri]), WeekdayMask.weekdays)
        XCTAssertEqual(WeekdayMask.weekdays(in: WeekdayMask.weekend), [sun, sat])
        XCTAssertEqual(WeekdayMask.weekdays(in: WeekdayMask.all).count, 7)
    }

    func testPlanResolutionUsesPlanThenFallsBackToTargetHistory() {
        let d = makeDevice()
        d.repo.setTarget(userId: user, effectiveDate: date(weekday: mon).addingTimeInterval(-86_400 * 30), protein: 100, carbs: 200, fat: 50)
        let training = d.repo.savePlan(userId: user, id: nil, name: "Training", weekdayMask: WeekdayMask.weekdays,
                                       protein: 180, carbs: 300, fat: 70, kcalOverride: nil)
        XCTAssertNotNil(training)
        // Monday: the plan. Saturday: no plan, falls back to the old target.
        XCTAssertEqual(d.repo.target(userId: user, on: date(weekday: mon))?.protein, 180)
        let expectedKcal: Double = 180 * 4 + 300 * 4 + 70 * 9
        XCTAssertEqual(d.repo.target(userId: user, on: date(weekday: mon))?.kcal, expectedKcal)
        XCTAssertEqual(d.repo.target(userId: user, on: date(weekday: sat))?.protein, 100)
        XCTAssertEqual(d.repo.uncoveredWeekdays(userId: user), [sun, sat])
        XCTAssertEqual(d.repo.plan(userId: user, on: date(weekday: wed))?.name, "Training")
        XCTAssertNil(d.repo.plan(userId: user, on: date(weekday: sun)))
    }

    func testNoPlanAndNoHistoryMeansNoTarget() {
        let d = makeDevice()
        XCTAssertNil(d.repo.target(userId: user, on: today))
    }

    func testDaySummaryAndDailyNutritionUseThePlan() {
        let d = makeDevice()
        d.repo.savePlan(userId: user, id: nil, name: "All", weekdayMask: WeekdayMask.all, protein: 150, carbs: 250, fat: 60, kcalOverride: nil)
        let day = date(weekday: thu)
        d.repo.quickAdd(userId: user, on: day, name: "x", nutrients: NutrientValues(kcal: 500, protein: 50, carbs: 50, fat: 10))
        let summary = d.repo.daySummary(userId: user, on: day)
        XCTAssertEqual(summary.target?.protein, 150)
        XCTAssertEqual(summary.remaining?.protein, 100)
        XCTAssertEqual(d.repo.dailyNutrition(userId: user, on: day).remaining?.protein, 100)
    }

    func testSavingAPlanMovesWeekdaysAndArchivesEmptiedPlans() {
        let d = makeDevice()
        let weekdays = d.repo.savePlan(userId: user, id: nil, name: "Weekdays", weekdayMask: WeekdayMask.weekdays,
                                       protein: 1, carbs: 1, fat: 1, kcalOverride: nil)
        let weekend = d.repo.savePlan(userId: user, id: nil, name: "Weekend", weekdayMask: WeekdayMask.weekend,
                                      protein: 2, carbs: 2, fat: 2, kcalOverride: nil)
        XCTAssertEqual(d.repo.uncoveredWeekdays(userId: user), [])
        // A "Friday" plan takes Friday from Weekdays; Weekend is untouched.
        let friday = d.repo.savePlan(userId: user, id: nil, name: "Friday", weekdayMask: WeekdayMask.bit(weekday: fri),
                                     protein: 3, carbs: 3, fat: 3, kcalOverride: nil)
        let byId = Dictionary(uniqueKeysWithValues: d.repo.plans(userId: user).map { ($0.id, $0) })
        XCTAssertEqual(byId[weekdays?.id ?? UUID()]?.weekdays, [mon, tue, wed, thu])
        XCTAssertEqual(byId[weekend?.id ?? UUID()]?.weekdays, [sun, sat])
        XCTAssertEqual(d.repo.plan(userId: user, on: date(weekday: fri))?.id, friday?.id)

        // No overlaps between any two plans.
        let masks: [Int] = d.repo.plans(userId: user).map(\.weekdayMask)
        var union = 0, total = 0
        for m in masks { union |= m; total += m }
        XCTAssertEqual(union, total, "masks are disjoint")

        // A plan that takes every day archives all the others.
        let everything = d.repo.savePlan(userId: user, id: nil, name: "All", weekdayMask: WeekdayMask.all, protein: 9, carbs: 9, fat: 9, kcalOverride: nil)
        XCTAssertEqual(d.repo.plans(userId: user).map(\.id), [everything?.id ?? UUID()])
        XCTAssertEqual(d.repo.plans(userId: user, includeArchived: true).count, 4)
    }

    func testEditingPlanDaysFreesThemAndArchiveFallsBack() {
        let d = makeDevice()
        d.repo.setTarget(userId: user, effectiveDate: today.addingTimeInterval(-86_400 * 400), protein: 77, carbs: 1, fat: 1)
        let plan = d.repo.savePlan(userId: user, id: nil, name: "Lift", weekdayMask: WeekdayMask.all, protein: 150, carbs: 200, fat: 50, kcalOverride: 2500)
        XCTAssertEqual(plan?.kcal, 2500)
        XCTAssertEqual(plan?.kcalOverridden, true)
        // Edit to Mon only.
        let edited = d.repo.savePlan(userId: user, id: plan?.id, name: "Lift", weekdayMask: WeekdayMask.bit(weekday: mon),
                                     protein: 150, carbs: 200, fat: 50, kcalOverride: nil)
        XCTAssertEqual(edited?.id, plan?.id)
        XCTAssertEqual(d.repo.target(userId: user, on: date(weekday: tue))?.protein, 77)
        d.repo.archivePlan(id: plan?.id ?? UUID(), userId: user)
        XCTAssertEqual(d.repo.target(userId: user, on: date(weekday: mon))?.protein, 77)
        // Invalid input is refused.
        XCTAssertNil(d.repo.savePlan(userId: user, id: nil, name: "  ", weekdayMask: 1, protein: 1, carbs: 1, fat: 1, kcalOverride: nil))
        XCTAssertNil(d.repo.savePlan(userId: user, id: nil, name: "Empty", weekdayMask: 0, protein: 1, carbs: 1, fat: 1, kcalOverride: nil))
    }

    func testOverlappingPlansFromTwoDevicesResolveDeterministically() {
        let a = NutritionPlan(id: UUID(), userId: user, name: "A", weekdayMask: 0b11, protein: 1, carbs: 1, fat: 1, kcal: 1,
                              kcalOverridden: false, sortOrder: 0, isArchived: false, createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 10))
        var b = a
        b = NutritionPlan(id: UUID(), userId: user, name: "B", weekdayMask: 0b10, protein: 2, carbs: 2, fat: 2, kcal: 2,
                          kcalOverridden: false, sortOrder: 1, isArchived: false, createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 20))
        let monday = date(weekday: mon)
        XCTAssertEqual(NutritionPlanResolver.plan(in: [a, b], on: monday)?.name, "B", "latest edit wins")
        XCTAssertEqual(NutritionPlanResolver.plan(in: [b, a], on: monday)?.name, "B", "order does not matter")
        XCTAssertEqual(NutritionPlanResolver.plan(in: [a, b], on: date(weekday: sun))?.name, "A")
    }

    func testReorderPlans() {
        let d = makeDevice()
        let a = d.repo.savePlan(userId: user, id: nil, name: "A", weekdayMask: 1, protein: 1, carbs: 1, fat: 1, kcalOverride: nil)
        let b = d.repo.savePlan(userId: user, id: nil, name: "B", weekdayMask: 2, protein: 1, carbs: 1, fat: 1, kcalOverride: nil)
        d.repo.reorderPlans(userId: user, orderedIds: [b?.id ?? UUID(), a?.id ?? UUID()])
        XCTAssertEqual(d.repo.plans(userId: user).map(\.name), ["B", "A"])
    }

    // MARK: - Goal settings

    func testGoalSettingsDraftPrefillsFromProfileAndSavingUpdatesProfile() async {
        let d = makeDevice()
        XCTAssertFalse(d.repo.isSetupComplete(userId: user))
        d.storage.saveProfile(UserProfile.create(userId: user, displayName: "T", age: 41, heightInches: 68, weightLbs: 190,
                                                 trainingAgeMonths: nil, primaryGoals: [], splitDays: [], avoidExercises: [],
                                                 equipment: [:], customEquipment: nil, notesToCoach: nil))
        let draft = d.repo.goalSettingsOrDraft(userId: user)
        XCTAssertEqual(draft.age, 41)
        XCTAssertEqual(draft.heightInches, 68)
        XCTAssertEqual(draft.currentWeightLbs, 190)
        XCTAssertFalse(draft.isComplete)

        var edited = draft
        edited.age = 42; edited.heightInches = 69; edited.currentWeightLbs = 185
        let result = d.repo.completeSetup(settings: edited, calculation: NutritionCalculator.calculate(edited))
        XCTAssertTrue(d.repo.isSetupComplete(userId: user))
        XCTAssertNotNil(result.plan)
        XCTAssertEqual(result.plan?.weekdayMask, WeekdayMask.all)

        let profile = d.storage.fetchProfile(userId: user).map { UserProfile(from: $0) }
        XCTAssertEqual(profile?.age, 42)
        XCTAssertEqual(profile?.heightInches, 69)
        XCTAssertEqual(profile?.weightLbs, 185)
        await d.stack.queue.waitForSubmissions()
        let types = await d.stack.queue.queuedOperations().map(\.type)
        XCTAssertTrue(types.contains(.upsertProfile))
        XCTAssertTrue(types.contains(.upsertGoalSettings))
        XCTAssertTrue(types.contains(.upsertNutritionPlan))
    }

    func testGoalSettingsAreOneRowPerUserAndRoundTrip() {
        let d = makeDevice()
        var s = settings()
        s.completedAt = Date(timeIntervalSince1970: 500)
        let first = d.repo.saveGoalSettings(s)
        s.targetWeightLbs = 160
        let second = d.repo.saveGoalSettings(s)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.id, NutritionGoalSettings.id(userId: user))
        let loaded = d.repo.goalSettings(userId: user)
        XCTAssertEqual(loaded?.targetWeightLbs, 160)
        XCTAssertEqual(loaded?.completedAt, Date(timeIntervalSince1970: 500))
        XCTAssertEqual(loaded?.sex, .male)
        XCTAssertEqual(loaded?.activityLevel, .lightlyActive)
        XCTAssertEqual(loaded?.unit, .lb)
    }

    func testPlanPersistenceRoundTripAndOwnership() {
        let d = makeDevice()
        let plan = d.repo.savePlan(userId: user, id: nil, name: "Rest", weekdayMask: 0b1000001, protein: 140, carbs: 180, fat: 60, kcalOverride: 2000)
        let loaded = d.storage.fetchNutritionPlan(id: plan?.id ?? UUID())
        XCTAssertEqual(loaded, plan)
        XCTAssertEqual(d.repo.plans(userId: UUID()), [], "other users see nothing")
        XCTAssertNil(d.repo.archivePlan(id: plan?.id ?? UUID(), userId: UUID()))
    }

    // MARK: - Wire format

    func testPayloadsEncodeEveryNotNullColumn() throws {
        var s = settings()
        let plan = NutritionPlan(id: UUID(), userId: user, name: "", weekdayMask: 0, protein: 0, carbs: 0, fat: 0, kcal: 0,
                                 kcalOverridden: false, sortOrder: 0, isArchived: false, createdAt: Date(), updatedAt: Date())
        for forCloud in [true, false] {
            let g = try jsonObject(s, forCloud: forCloud)
            for column in ["id", "user_id", "goal", "sex", "age", "height_inches", "current_weight_lbs", "target_weight_lbs",
                           "weekly_rate_lbs", "activity_level", "lifts_weights", "unit", "completed_at", "created_at", "updated_at"] {
                XCTAssertNotNil(g[column], "nutrition_goal_settings.\(column) missing (cloud=\(forCloud))")
            }
            XCTAssertTrue(g["completed_at"] is NSNull, "completed_at is an explicit null while setup is unfinished")
            let p = try jsonObject(plan, forCloud: forCloud)
            for column in ["id", "user_id", "name", "weekday_mask", "protein_g", "carbs_g", "fat_g", "kcal", "kcal_overridden",
                           "sort_order", "is_archived", "created_at", "updated_at"] {
                XCTAssertNotNil(p[column], "nutrition_plans.\(column) missing (cloud=\(forCloud)); zero/false must still be sent")
            }
        }
        s.completedAt = Date()
        XCTAssertFalse(try jsonObject(s, forCloud: true)["completed_at"] is NSNull)
    }

    func testQueueEncodingRoundTrips() throws {
        var s = settings(goal: .gain, sex: .female, activity: .veryActive)
        s.completedAt = Date(timeIntervalSince1970: 1_000)
        s.unit = .kg
        XCTAssertEqual(try JSONDecoder().decode(NutritionGoalSettings.self, from: JSONEncoder().encode(s)), s)
        let plan = NutritionPlan(id: UUID(), userId: user, name: "Heavy", weekdayMask: 0b0101010, protein: 200, carbs: 350, fat: 80,
                                 kcal: 2400, kcalOverridden: true, sortOrder: 2, isArchived: true,
                                 createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(try JSONDecoder().decode(NutritionPlan.self, from: JSONEncoder().encode(plan)), plan)
    }

    // MARK: - Sync

    func testFlushUploadsGoalsAndPlans() async {
        let remote = FakeRemote()
        let d = makeDevice(remote: remote)
        let result = d.repo.completeSetup(settings: settings(), calculation: NutritionCalculator.calculate(settings()))
        await d.stack.flushAll()
        XCTAssertNotNil(remote.goalSettings[result.settings.id])
        XCTAssertNotNil(remote.nutritionPlans[result.plan?.id ?? UUID()])
    }

    func testFreshDeviceRestoresGoalsAndPlansAndRepairUploadsMissingOnes() async throws {
        let remote = FakeRemote()
        var s = settings(); s.completedAt = Date()
        remote.seedGoalSettings(s)
        let plan = NutritionPlan(id: UUID(), userId: user, name: "Cloud", weekdayMask: WeekdayMask.all, protein: 150, carbs: 250, fat: 60,
                                 kcal: 2140, kcalOverridden: false, sortOrder: 0, isArchived: false, createdAt: Date(), updatedAt: Date())
        remote.seedNutritionPlan(plan)
        let d = makeDevice(remote: remote)
        _ = try await d.service.restoreAll(userId: user, assumeFreshInstall: true)
        XCTAssertTrue(d.repo.isSetupComplete(userId: user))
        XCTAssertEqual(d.repo.plans(userId: user).map(\.name), ["Cloud"])

        // A plan only this device has gets uploaded by the repair step.
        let local = NutritionPlan(id: UUID(), userId: user, name: "Local", weekdayMask: 0, protein: 1, carbs: 1, fat: 1, kcal: 17,
                                  kcalOverridden: false, sortOrder: 1, isArchived: false, createdAt: Date(), updatedAt: Date())
        d.storage.saveNutritionPlan(local)
        let summary = try await d.service.restoreAll(userId: user, assumeFreshInstall: false)
        XCTAssertGreaterThanOrEqual(summary.repairedNutrition, 1)
        await d.stack.flushAll()
        XCTAssertNotNil(remote.nutritionPlans[local.id])
    }

    // MARK: - Missing server tables must not wedge the queue

    func testMissingTableErrorsClassifyAsRetryNotDeadLetter() {
        XCTAssertTrue(SyncErrorClassifier.isMissingTable(PostgrestError(code: "PGRST205", message: "no table")))
        XCTAssertTrue(SyncErrorClassifier.isMissingTable(PostgrestError(code: "42P01", message: "undefined_table")))
        XCTAssertFalse(SyncErrorClassifier.isMissingTable(PostgrestError(code: "23505", message: "dup")))
        XCTAssertEqual(SyncErrorClassifier.classify(PostgrestError(code: "PGRST205", message: "x"), opType: .upsertNutritionPlan), .dependency)
        XCTAssertEqual(SyncErrorClassifier.classify(PostgrestError(code: "42P01", message: "x"), opType: .upsertGoalSettings), .dependency)
        // Other PostgREST/permission errors are unchanged.
        XCTAssertEqual(SyncErrorClassifier.classify(PostgrestError(code: "PGRST204", message: "x"), opType: .upsertNutritionPlan), .permanent)
    }

    func testMissingTablesKeepTheOperationAndLetOtherWritesThrough() async {
        let remote = FakeRemote()
        remote.script = { type, _ in
            (type == .upsertNutritionPlan || type == .upsertGoalSettings)
                ? PostgrestError(code: "PGRST205", message: "Could not find the table in the schema cache") : nil
        }
        let d = makeDevice(remote: remote)
        // The table-less writes first, then ordinary nutrition writes behind them.
        d.repo.completeSetup(settings: settings(), calculation: NutritionCalculator.calculate(settings()))
        let entry = d.repo.quickAdd(userId: user, on: today, name: "Bar", nutrients: NutrientValues(kcal: 100, protein: 1, carbs: 1, fat: 1))
        let water = d.repo.addWater(userId: user, amountMl: 250, on: today)
        await d.stack.flushAll()

        XCTAssertNotNil(remote.foodEntries[entry.id], "other writes still go through")
        XCTAssertNotNil(remote.waterEntries[water?.id ?? UUID()])
        let failed = await d.stack.queue.failedOperations()
        XCTAssertTrue(failed.isEmpty, "nothing was dead-lettered")
        let types = await d.stack.queue.queuedOperations().map(\.type)
        XCTAssertTrue(types.contains(.upsertNutritionPlan) && types.contains(.upsertGoalSettings), "still queued for when the tables exist")
    }

    func testRestoreSurvivesMissingGoalTables() async throws {
        let remote = FakeRemote()
        remote.readScript = { name, _ in
            (name == "fetchGoalSettings" || name == "fetchNutritionPlans")
                ? PostgrestError(code: "PGRST205", message: "Could not find the table") : nil
        }
        let d = makeDevice(remote: remote)
        let plan = d.repo.savePlan(userId: user, id: nil, name: "Mine", weekdayMask: WeekdayMask.all, protein: 1, carbs: 1, fat: 1, kcalOverride: nil)
        _ = try await d.service.restoreAll(userId: user, assumeFreshInstall: false)
        XCTAssertEqual(d.repo.plans(userId: user).map(\.id), [plan?.id ?? UUID()], "local plans are untouched")
    }

    // MARK: - View model

    func testViewModelExposesSetupAndPlans() {
        let d = makeDevice()
        let uid = user
        let vm = NutritionViewModel(repository: d.repo, userIdProvider: { uid })
        vm.reload()
        XCTAssertFalse(vm.isSetupComplete)
        let draft = vm.goalSettingsOrDraft()
        XCTAssertNotNil(draft)
        XCTAssertGreaterThan(vm.calculate(draft ?? settings()).kcal, 0)
        vm.completeSetup(draft ?? settings())
        XCTAssertTrue(vm.isSetupComplete)
        XCTAssertEqual(vm.plans.count, 1)
        XCTAssertEqual(vm.plan(for: today)?.weekdayMask, WeekdayMask.all)
        let saved = vm.savePlan(id: nil, name: "Rest", weekdayMask: WeekdayMask.weekend, protein: 100, carbs: 100, fat: 50, kcalOverride: nil)
        XCTAssertEqual(vm.plans.count, 2)
        if let saved { vm.deletePlan(saved) }
        XCTAssertEqual(vm.plans.count, 1)
        XCTAssertEqual(vm.uncoveredWeekdays().sorted(), [sun, sat])
    }
}
