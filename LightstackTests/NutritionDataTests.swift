import XCTest
import CoreData
@testable import Lightstack

/// Nutrition data layer: maths, payload encoding, Core Data v4 -> v5 migration, repository + outbox, restore rules.
@MainActor
final class NutritionDataTests: XCTestCase {

    // MARK: - Fixtures

    private let user = UUID()
    private let today = Date().startOfDay

    private func nutrients(_ kcal: Double, _ p: Double, _ c: Double, _ f: Double, fiber: Double? = nil, sodium: Double? = nil) -> NutrientValues {
        var micros = Micronutrients()
        micros[.fiber] = fiber
        micros[.sodium] = sodium
        return NutrientValues(kcal: kcal, protein: p, carbs: c, fat: f, micros: micros)
    }

    private func entry(_ name: String, servings: Double, _ values: NutrientValues, day: Date? = nil) -> FoodEntry {
        FoodEntry(id: UUID(), userId: user, date: (day ?? today).startOfDay, foodId: nil, name: name, servings: servings,
                  servingLabel: "serving", perServing: values, source: .quick, createdAt: Date(), updatedAt: Date())
    }

    private func jsonObject<T: NutritionRow>(_ row: T, forCloud: Bool) throws -> [String: Any] {
        let data = try JSONEncoder().encode(forCloud ? AnyEncodable(row.cloudRow()) : AnyEncodable(row))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private struct AnyEncodable: Encodable {
        let wrapped: Encodable
        init(_ wrapped: Encodable) { self.wrapped = wrapped }
        func encode(to encoder: Encoder) throws { try wrapped.encode(to: encoder) }
    }

    // MARK: - Maths

    func testKcalDerivesFromMacrosUnlessOverridden() {
        XCTAssertEqual(NutritionMath.derivedKcal(protein: 150, carbs: 200, fat: 60), 1940.0)
        let derived = NutritionTarget.make(userId: user, effectiveDate: today, protein: 150, carbs: 200, fat: 60)
        XCTAssertEqual(derived.kcal, 1940)
        XCTAssertFalse(derived.kcalOverridden)
        XCTAssertEqual(derived.kcalMismatch, 0)
        let typed = NutritionTarget.make(userId: user, effectiveDate: today, protein: 150, carbs: 200, fat: 60, kcalOverride: 2200)
        XCTAssertEqual(typed.kcal, 2200)
        XCTAssertTrue(typed.kcalOverridden)
        XCTAssertEqual(typed.kcalMismatch, 260)
    }

    func testDailyTotalsScaleByServingsAndUnknownMicrosStayNil() {
        let a = entry("Oats", servings: 2, nutrients(150, 5, 27, 3, fiber: 4))
        let b = entry("Egg", servings: 1, nutrients(70, 6, 0.5, 5))
        let totals = NutritionMath.totals(of: [a, b])
        XCTAssertEqual(totals.kcal, 370)
        XCTAssertEqual(totals.protein, 16)
        XCTAssertEqual(totals.carbs, 54.5)
        XCTAssertEqual(totals.fat, 11)
        XCTAssertEqual(totals.micros[.fiber], 8, "only entries that know fiber contribute")
        XCTAssertNil(totals.micros[.sodium], "unknown stays nil, never 0")
        XCTAssertEqual(NutritionMath.totals(of: []).micros[.fiber], nil)
    }

    func testZeroIsDifferentFromUnknown() {
        let known = entry("Water", servings: 1, nutrients(0, 0, 0, 0, sodium: 0))
        XCTAssertEqual(NutritionMath.totals(of: [known]).micros[.sodium], 0)
    }

    func testRemainingGoesNegativeWhenOver() {
        let target = NutritionTarget.make(userId: user, effectiveDate: today, protein: 100, carbs: 100, fat: 50)
        let totals = NutritionMath.totals(of: [entry("Feast", servings: 1, nutrients(2000, 120, 90, 40))])
        let remaining = NutritionMath.remaining(target: target, totals: totals)
        XCTAssertEqual(remaining.protein, -20)
        XCTAssertEqual(remaining.carbs, 10)
        XCTAssertEqual(remaining.fat, 10)
        XCTAssertEqual(remaining.kcal, target.kcal - 2000)
    }

    func testTargetIsVersionedByEffectiveDate() {
        let cal = Calendar.current
        let d1 = cal.date(byAdding: .day, value: -10, to: today) ?? today
        let d2 = cal.date(byAdding: .day, value: -3, to: today) ?? today
        let old = NutritionTarget.make(userId: user, effectiveDate: d1, protein: 100, carbs: 100, fat: 50)
        let new = NutritionTarget.make(userId: user, effectiveDate: d2, protein: 150, carbs: 100, fat: 50)
        let both = [new, old]
        XCTAssertNil(NutritionMath.target(in: both, on: cal.date(byAdding: .day, value: -11, to: today) ?? today))
        XCTAssertEqual(NutritionMath.target(in: both, on: d1)?.id, old.id)
        XCTAssertEqual(NutritionMath.target(in: both, on: cal.date(byAdding: .day, value: -4, to: today) ?? today)?.id, old.id)
        XCTAssertEqual(NutritionMath.target(in: both, on: d2)?.id, new.id)
        XCTAssertEqual(NutritionMath.target(in: both, on: today)?.id, new.id)
    }

    // MARK: - Payload encoding (every NOT NULL column, always)

    private let foodNotNull = ["id", "user_id", "name", "serving_label", "serving_unit", "serving_amount", "kcal", "protein_g",
                               "carbs_g", "fat_g", "other_micros", "source", "is_favorite", "created_at", "updated_at"]

    func testFoodPayloadEncodesEveryNotNullColumnEvenWhenMinimal() throws {
        let food = NutritionFood.make(userId: user, name: "Plain", nutrients: NutrientValues())
        for forCloud in [true, false] {
            let json = try jsonObject(food, forCloud: forCloud)
            for column in foodNotNull { XCTAssertNotNil(json[column], "\(column) missing (cloud=\(forCloud))") }
            for key in MicroKey.allCases { XCTAssertTrue(json.keys.contains(key.column), "\(key.column) must be sent as null") }
            XCTAssertTrue(json.keys.contains("brand") && json.keys.contains("serving_grams") && json.keys.contains("last_used_at"))
            XCTAssertTrue(json["sodium_mg"] is NSNull)
            XCTAssertEqual((json["other_micros"] as? [String: Any])?.count, 0)
        }
    }

    func testEntryAndTargetPayloadsEncodeEveryNotNullColumn() throws {
        let entryJSON = try jsonObject(entry("X", servings: 1, NutrientValues()), forCloud: true)
        for column in ["id", "user_id", "date", "name", "servings", "serving_label", "kcal", "protein_g", "carbs_g", "fat_g",
                       "other_micros", "source", "created_at", "updated_at"] {
            XCTAssertNotNil(entryJSON[column], "\(column) missing")
        }
        XCTAssertTrue(entryJSON.keys.contains("food_id") && entryJSON["food_id"] is NSNull)
        XCTAssertTrue(entryJSON["date"] is String, "DATE column is sent as yyyy-MM-dd")
        XCTAssertEqual(entryJSON["date"] as? String, RemoteDate.dayString(today))

        let target = NutritionTarget.make(userId: user, effectiveDate: today, protein: 0, carbs: 0, fat: 0)
        let targetJSON = try jsonObject(target, forCloud: true)
        for column in ["id", "user_id", "effective_date", "kcal", "protein_g", "carbs_g", "fat_g", "kcal_overridden", "created_at", "updated_at"] {
            XCTAssertNotNil(targetJSON[column], "\(column) missing (zeros and false must still be sent)")
        }
        XCTAssertEqual(targetJSON["effective_date"] as? String, RemoteDate.dayString(today))
    }

    func testQueueEncodingRoundTrips() throws {
        var micros = Micronutrients(other: ["Biotin": 30])
        micros[.fiber] = 3.5
        let food = NutritionFood.make(userId: user, name: "Bar", brand: "Acme", servingLabel: "1 bar (40 g)", servingUnit: "g",
                                      servingAmount: 40, servingGrams: 40, nutrients: NutrientValues(kcal: 180, protein: 10, carbs: 20, fat: 6, micros: micros), source: .scan)
        let decoded = try JSONDecoder().decode(NutritionFood.self, from: JSONEncoder().encode(food))
        XCTAssertEqual(decoded, food)
        let e = FoodEntry.make(from: food, servings: 1.5, on: today)
        XCTAssertEqual(try JSONDecoder().decode(FoodEntry.self, from: JSONEncoder().encode(e)), e)
        let t = NutritionTarget.make(userId: user, effectiveDate: today, protein: 1, carbs: 2, fat: 3)
        XCTAssertEqual(try JSONDecoder().decode(NutritionTarget.self, from: JSONEncoder().encode(t)), t)
    }

    func testDecodesCloudRow() throws {
        let id = UUID(), uid = UUID()
        let json = """
        {"id":"\(id)","user_id":"\(uid)","date":"2026-10-24","food_id":null,"name":"Toast","servings":2,"serving_label":"1 slice",
         "kcal":80,"protein_g":3,"carbs_g":14,"fat_g":1,"fiber_g":2,"sugar_g":null,"other_micros":{"Biotin":1.5},
         "source":"saved","created_at":"2026-10-24T10:00:00Z","updated_at":"2026-10-24T10:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FoodEntry.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(RemoteDate.dayString(decoded.date), "2026-10-24")
        XCTAssertEqual(decoded.perServing.micros[.fiber], 2)
        XCTAssertNil(decoded.perServing.micros[.sugar])
        XCTAssertEqual(decoded.perServing.micros.other["Biotin"], 1.5)
        XCTAssertEqual(decoded.source, .saved)
    }

    // MARK: - Core Data v4 -> v5

    func testMigratesV4StoreToV5AddsNutritionEntities() throws {
        let bundle = Bundle(for: LocalStorageService.self)
        let v4URL = try XCTUnwrap(bundle.url(forResource: "Lightstack 4", withExtension: "mom", subdirectory: "Lightstack.momd"))
        let v5URL = try XCTUnwrap(bundle.url(forResource: "Lightstack 5", withExtension: "mom", subdirectory: "Lightstack.momd"))
        let v4Model = try XCTUnwrap(NSManagedObjectModel(contentsOf: v4URL))
        let v5Model = try XCTUnwrap(NSManagedObjectModel(contentsOf: v5URL))
        for name in ["CDNutritionTarget", "CDFood", "CDFoodEntry"] {
            XCTAssertNil(v4Model.entitiesByName[name])
            XCTAssertNotNil(v5Model.entitiesByName[name])
        }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("Lightstack.sqlite")
        let workoutId = UUID(), restId = UUID()

        do {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: v4Model)
            let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
            let ctx = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            ctx.persistentStoreCoordinator = coordinator
            try ctx.performAndWait {
                let w = NSEntityDescription.insertNewObject(forEntityName: "CDWorkout", into: ctx)
                w.setValue(workoutId, forKey: "id"); w.setValue(UUID(), forKey: "userId")
                w.setValue(Date(), forKey: "date"); w.setValue("Legs", forKey: "workoutType")
                w.setValue(Date(), forKey: "createdAt")
                let r = NSEntityDescription.insertNewObject(forEntityName: "CDRestDay", into: ctx)
                r.setValue(restId, forKey: "id"); r.setValue(UUID(), forKey: "userId")
                r.setValue(Date(), forKey: "date"); r.setValue(Date(), forKey: "createdAt")
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
        XCTAssertEqual(try ctx.fetch(CDWorkout.fetchRequest() as NSFetchRequest<CDWorkout>).first?.id, workoutId)
        XCTAssertEqual(try ctx.fetch(CDRestDay.fetchRequest() as NSFetchRequest<CDRestDay>).first?.id, restId)
        XCTAssertEqual(try ctx.count(for: CDFood.fetchRequest() as NSFetchRequest<CDFood>), 0)

        let food = CDFood(context: ctx)
        NutritionFood.make(userId: user, name: "After migration", nutrients: nutrients(100, 1, 2, 3, fiber: 1)).apply(to: food)
        try ctx.save()
        XCTAssertEqual(try ctx.count(for: CDFood.fetchRequest() as NSFetchRequest<CDFood>), 1)
    }

    func testCoreDataRoundTripKeepsNilMicrosDistinctFromZero() {
        let storage = LocalStorageService(inMemory: true)
        var values = nutrients(100, 1, 2, 3, fiber: 0)
        values.micros.other = ["Biotin": 2]
        let food = NutritionFood.make(userId: user, name: "Zero fiber", nutrients: values)
        storage.saveFood(food)
        let loaded = storage.fetchFood(id: food.id)
        XCTAssertEqual(loaded?.nutrients.micros[.fiber], 0)
        XCTAssertNil(loaded?.nutrients.micros[.sodium])
        XCTAssertEqual(loaded?.nutrients.micros.other["Biotin"], 2)
        XCTAssertNil(loaded?.servingGrams)
    }

    // MARK: - Repository

    private struct Device {
        let stack: OutboxTestStack
        let repo: NutritionRepository
        let service: SyncRestoreService
        let defaults: UserDefaults
        var storage: LocalStorageService { stack.storage }
        var queue: OfflineQueueManager { stack.queue }
        func queuedTypes() async -> [QueuedOperationType] {
            await queue.waitForSubmissions()
            return await queue.queuedOperations().map(\.type)
        }
    }

    private func makeDevice(remote: FakeRemote = FakeRemote(), userId: UUID? = nil, pageSize: Int = 2) -> Device {
        let uid = userId ?? user
        let stack = OutboxTestStack(userId: uid, remote: remote)
        let defaults = UserDefaults(suiteName: "nutri-\(UUID().uuidString)") ?? .standard
        let pr = PRRepository(localStorage: stack.storage, offlineQueueManager: stack.queue)
        let service = SyncRestoreService(
            remote: remote, storage: stack.storage, queue: stack.queue, prRepository: pr,
            currentUserId: { uid }, defaults: defaults, pageSize: pageSize
        )
        return Device(stack: stack, repo: NutritionRepository(localStorage: stack.storage, offlineQueueManager: stack.queue),
                      service: service, defaults: defaults)
    }

    func testRepositoryTargetsAreEffectiveDatedAndUpdatedInPlace() {
        let d = makeDevice()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        let first = d.repo.setTarget(userId: user, effectiveDate: yesterday, protein: 100, carbs: 100, fat: 50)
        XCTAssertEqual(first.kcal, 1250)
        let again = d.repo.setTarget(userId: user, effectiveDate: yesterday, protein: 110, carbs: 100, fat: 50, kcalOverride: 2000)
        XCTAssertEqual(again.id, first.id, "same effective day updates the same target")
        XCTAssertEqual(again.kcal, 2000)
        XCTAssertTrue(again.kcalOverridden)
        let newer = d.repo.setTarget(userId: user, effectiveDate: today, protein: 200, carbs: 100, fat: 50)
        XCTAssertEqual(d.repo.targets(userId: user).count, 2)
        XCTAssertEqual(d.repo.target(userId: user, on: yesterday)?.id, first.id)
        XCTAssertEqual(d.repo.target(userId: user, on: today)?.id, newer.id)
    }

    func testLoggingSnapshotsValuesAndEditingFoodDoesNotRewriteHistory() {
        let d = makeDevice()
        var food = d.repo.saveFood(NutritionFood.make(userId: user, name: "Yogurt", nutrients: nutrients(100, 10, 5, 2)))
        let logged = d.repo.logFood(food, servings: 2, on: today)
        food = d.repo.food(id: food.id) ?? food
        food.nutrients.kcal = 999
        d.repo.saveFood(food)
        let day = d.repo.dailyNutrition(userId: user, on: today)
        XCTAssertEqual(day.entries.count, 1)
        XCTAssertEqual(day.entries.first?.id, logged.id)
        XCTAssertEqual(day.totals.kcal, 200)
        XCTAssertNil(day.target)
        XCTAssertNil(day.remaining)
        XCTAssertNotNil(d.repo.food(id: food.id)?.lastUsedAt)
        XCTAssertEqual(d.repo.recentFoods(userId: user).map(\.id), [food.id])
    }

    func testDailyNutritionRemainingAndQuickAdd() {
        let d = makeDevice()
        d.repo.setTarget(userId: user, effectiveDate: today, protein: 100, carbs: 200, fat: 50)
        d.repo.quickAdd(userId: user, on: today, name: nil, nutrients: nutrients(500, 30, 50, 10))
        let day = d.repo.dailyNutrition(userId: user, on: today)
        XCTAssertEqual(day.entries.first?.name, "Quick add")
        XCTAssertEqual(day.remaining?.protein, 70)
        XCTAssertEqual(day.remaining?.kcal, 1150.0)   // target 100*4 + 200*4 + 50*9 = 1650, eaten 500
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        XCTAssertTrue(d.repo.entries(userId: user, on: tomorrow).isEmpty, "entries are per local day")
    }

    func testFavouritesAndSearch() {
        let d = makeDevice()
        let a = d.repo.saveFood(NutritionFood.make(userId: user, name: "Greek Yogurt", brand: "Fage", nutrients: NutrientValues()))
        _ = d.repo.saveFood(NutritionFood.make(userId: user, name: "Banana", nutrients: NutrientValues()))
        d.repo.setFavorite(foodId: a.id, isFavorite: true)
        XCTAssertEqual(d.repo.favoriteFoods(userId: user).map(\.id), [a.id])
        XCTAssertEqual(d.repo.searchFoods(userId: user, query: "yog").map(\.id), [a.id])
        XCTAssertEqual(d.repo.searchFoods(userId: user, query: "FAGE").map(\.id), [a.id])
        XCTAssertEqual(d.repo.searchFoods(userId: user, query: "").count, 2)
        XCTAssertTrue(d.repo.recentFoods(userId: user).isEmpty, "never-logged foods are not recent")
    }

    func testDeletingFoodKeepsEntriesAndNullsTheLink() async {
        let d = makeDevice()
        let food = d.repo.saveFood(NutritionFood.make(userId: user, name: "Rice", nutrients: nutrients(200, 4, 45, 0)))
        let logged = d.repo.logFood(food, servings: 1, on: today)
        d.repo.deleteFood(id: food.id, userId: user)
        XCTAssertNil(d.repo.food(id: food.id))
        let kept = d.storage.fetchFoodEntry(id: logged.id)
        XCTAssertNotNil(kept)
        XCTAssertNil(kept?.foodId)
        XCTAssertEqual(kept?.name, "Rice")
        let types = await d.queuedTypes()
        XCTAssertTrue(types.contains(.deleteFood))
        XCTAssertTrue(types.contains(.insertTombstone))
    }

    // MARK: - Outbox

    func testFlushUploadsFoodsBeforeEntriesAndDeletesLast() async {
        let remote = FakeRemote()
        let d = makeDevice(remote: remote)
        let food = d.repo.saveFood(NutritionFood.make(userId: user, name: "Oats", nutrients: nutrients(150, 5, 27, 3)))
        let logged = d.repo.logFood(food, servings: 1, on: today)
        d.repo.setTarget(userId: user, effectiveDate: today, protein: 100, carbs: 100, fat: 50)
        let doomed = d.repo.quickAdd(userId: user, on: today, name: "Oops", nutrients: nutrients(1, 0, 0, 0))
        d.repo.deleteEntry(id: doomed.id, userId: user)
        await d.stack.flushAll()

        let calls = remote.calls
        let foodIndex = calls.firstIndex { $0.hasPrefix("upsertFood:") }
        let entryIndex = calls.firstIndex { $0.hasPrefix("upsertFoodEntry:") }
        let deleteIndex = calls.firstIndex { $0.hasPrefix("deleteFoodEntry:") }
        XCTAssertNotNil(foodIndex)
        XCTAssertNotNil(entryIndex)
        XCTAssertLessThan(foodIndex ?? 0, entryIndex ?? 0, "FK order: foods before entries")
        XCTAssertLessThan(entryIndex ?? 0, deleteIndex ?? 0, "deletes last")
        XCTAssertNotNil(remote.foodEntries[logged.id])
        XCTAssertNotNil(remote.foods[food.id])
        XCTAssertEqual(remote.nutritionTargets.count, 1)
        XCTAssertNil(remote.foodEntries[doomed.id])
        XCTAssertTrue(remote.tombstones.contains("food_entry:\(doomed.id.uuidString)"))
    }

    // MARK: - Restore

    func testFreshDeviceRestoresNutritionWithoutQueueingAndPagesEntries() async throws {
        let remote = FakeRemote()
        let food = NutritionFood.make(userId: user, name: "Cloud food", nutrients: nutrients(100, 1, 1, 1))
        remote.seedFood(food)
        remote.seedNutritionTarget(NutritionTarget.make(userId: user, effectiveDate: today, protein: 100, carbs: 100, fat: 50))
        for i in 0..<5 {
            remote.seedFoodEntry(FoodEntry.make(from: food, servings: Double(i + 1), on: today))
        }
        let d = makeDevice(remote: remote, pageSize: 2)
        let summary = try await d.service.restoreAll(userId: user)

        XCTAssertEqual(summary.nutritionApplied, 7)
        XCTAssertEqual(d.storage.fetchFoods(userId: user).count, 1)
        XCTAssertEqual(d.storage.fetchNutritionTargets(userId: user).count, 1)
        XCTAssertEqual(d.storage.fetchFoodEntries(userId: user, on: today).count, 5)
        XCTAssertEqual(remote.readLog.filter { $0 == "fetchFoodEntriesPage" }.count, 3, "pages of 2 until a short page")
        let types = await d.queuedTypes()
        XCTAssertTrue(types.isEmpty, "restore must not queue uploads, found \(types)")
    }

    func testPendingLocalChangeWinsOverCloudCopy() async throws {
        let remote = FakeRemote()
        let d = makeDevice(remote: remote)
        var food = d.repo.saveFood(NutritionFood.make(userId: user, name: "Local name", nutrients: nutrients(100, 1, 1, 1)))
        var cloud = food
        cloud.name = "Cloud name"
        remote.seedFood(cloud)
        _ = try await d.service.restoreAll(userId: user, assumeFreshInstall: true)
        food = try XCTUnwrap(d.storage.fetchFood(id: food.id))
        XCTAssertEqual(food.name, "Local name", "unuploaded local edit wins")

        // Once uploaded, the cloud wins.
        await d.stack.flushAll()
        cloud.name = "Newer cloud name"
        remote.seedFood(cloud)
        _ = try await d.service.restoreAll(userId: user, assumeFreshInstall: true)
        XCTAssertEqual(d.storage.fetchFood(id: food.id)?.name, "Newer cloud name")
    }

    func testTombstonesDeleteLocalRowsAndDropPendingUpserts() async throws {
        let remote = FakeRemote()
        let d = makeDevice(remote: remote)
        let food = d.repo.saveFood(NutritionFood.make(userId: user, name: "Gone", nutrients: nutrients(1, 1, 1, 1)))
        let logged = d.repo.logFood(food, servings: 1, on: today)
        remote.seedTombstone(.food, food.id)
        remote.seedTombstone(.foodEntry, logged.id)
        _ = try await d.service.restoreAll(userId: user, assumeFreshInstall: true)

        XCTAssertNil(d.storage.fetchFood(id: food.id))
        XCTAssertNil(d.storage.fetchFoodEntry(id: logged.id))
        let types = await d.queuedTypes()
        XCTAssertFalse(types.contains(.upsertFood), "pending upserts for tombstoned records are dropped")
        XCTAssertFalse(types.contains(.upsertFoodEntry))
    }

    func testTombstonedFoodDetachesEntriesWithoutDeletingThem() async throws {
        let remote = FakeRemote()
        let d = makeDevice(remote: remote)
        let food = NutritionFood.make(userId: user, name: "Deleted elsewhere", nutrients: nutrients(50, 1, 1, 1))
        let kept = FoodEntry.make(from: food, servings: 1, on: today)
        remote.seedFoodEntry({ var e = kept; e.foodId = nil; return e }())
        remote.seedTombstone(.food, food.id)
        d.storage.restoreFoods([food])
        d.storage.restoreFoodEntries([kept])
        _ = try await d.service.restoreAll(userId: user, assumeFreshInstall: true)
        let entry = d.storage.fetchFoodEntry(id: kept.id)
        XCTAssertNotNil(entry)
        XCTAssertNil(entry?.foodId)
        XCTAssertNil(d.storage.fetchFood(id: food.id))
    }

    func testRepairQueuesLocalRowsTheCloudLacks() async throws {
        let remote = FakeRemote()
        let d = makeDevice(remote: remote)
        let food = NutritionFood.make(userId: user, name: "Lost upload", nutrients: nutrients(1, 1, 1, 1))
        let entry = FoodEntry.make(from: food, servings: 1, on: today)
        let target = NutritionTarget.make(userId: user, effectiveDate: today, protein: 1, carbs: 1, fat: 1)
        d.storage.saveFood(food); d.storage.saveFoodEntry(entry); d.storage.saveNutritionTarget(target)   // no queue: like an old lost write
        let summary = try await d.service.restoreAll(userId: user, assumeFreshInstall: true)
        XCTAssertEqual(summary.repairedNutrition, 3)
        let types = await d.queuedTypes()
        XCTAssertEqual(Set(types), [.upsertFood, .upsertFoodEntry, .upsertNutritionTarget])
        await d.stack.flushAll()
        XCTAssertNotNil(remote.foodEntries[entry.id])
    }

    func testFirstReconciliationKeepsLocalAndUploadsDifference() async throws {
        let remote = FakeRemote()
        let d = makeDevice(remote: remote)
        let food = NutritionFood.make(userId: user, name: "Local edit", nutrients: nutrients(1, 1, 1, 1))
        d.storage.saveFood(food)
        var cloud = food
        cloud.name = "Older cloud"
        remote.seedFood(cloud)
        let cloudOnly = NutritionFood.make(userId: user, name: "Cloud only", nutrients: nutrients(2, 2, 2, 2))
        remote.seedFood(cloudOnly)

        let summary = try await d.service.restoreAll(userId: user)   // existing install: local data, flag not set
        XCTAssertTrue(summary.reconciled)
        XCTAssertEqual(d.storage.fetchFood(id: food.id)?.name, "Local edit")
        XCTAssertEqual(d.storage.fetchFood(id: cloudOnly.id)?.name, "Cloud only")
        let types = await d.queuedTypes()
        XCTAssertEqual(types.filter { $0 == .upsertFood }.count, 1, "only the differing local food is uploaded")
    }
}
