import XCTest
import CoreData
@testable import Lightstack

/// Nutrition journal data layer: Core Data v5 -> v6, meal slots, batch logging, day summary, water, day notes,
/// sync payloads and restore.
@MainActor
final class NutritionJournalTests: XCTestCase {

    private let user = UUID()
    private let today = Date().startOfDay

    private func nutrients(_ kcal: Double, _ p: Double, _ c: Double, _ f: Double, fiber: Double? = nil, sodium: Double? = nil) -> NutrientValues {
        var micros = Micronutrients()
        micros[.fiber] = fiber
        micros[.sodium] = sodium
        return NutrientValues(kcal: kcal, protein: p, carbs: c, fat: f, micros: micros)
    }

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

    private func makeDevice(remote: FakeRemote = FakeRemote(), pageSize: Int = 2) -> Device {
        let uid = user
        let stack = OutboxTestStack(userId: uid, remote: remote)
        let defaults = UserDefaults(suiteName: "nutri-journal-\(UUID().uuidString)") ?? .standard
        let pr = PRRepository(localStorage: stack.storage, offlineQueueManager: stack.queue)
        let service = SyncRestoreService(
            remote: remote, storage: stack.storage, queue: stack.queue, prRepository: pr,
            currentUserId: { uid }, defaults: defaults, pageSize: pageSize
        )
        return Device(stack: stack, repo: NutritionRepository(localStorage: stack.storage, offlineQueueManager: stack.queue), service: service)
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

    // MARK: - Migration 5 -> 6

    func testMigratesV5StoreToV6AddsJournalEntitiesAndKeepsEntries() throws {
        let bundle = Bundle(for: LocalStorageService.self)
        let v5URL = try XCTUnwrap(bundle.url(forResource: "Lightstack 5", withExtension: "mom", subdirectory: "Lightstack.momd"))
        let v6URL = try XCTUnwrap(bundle.url(forResource: "Lightstack 6", withExtension: "mom", subdirectory: "Lightstack.momd"))
        let v5Model = try XCTUnwrap(NSManagedObjectModel(contentsOf: v5URL))
        let v6Model = try XCTUnwrap(NSManagedObjectModel(contentsOf: v6URL))
        for name in ["CDMealSlot", "CDWaterEntry", "CDDayNote"] {
            XCTAssertNil(v5Model.entitiesByName[name])
            XCTAssertNotNil(v6Model.entitiesByName[name])
        }
        XCTAssertNil(v5Model.entitiesByName["CDFoodEntry"]?.attributesByName["mealSlotId"])
        XCTAssertNotNil(v6Model.entitiesByName["CDFoodEntry"]?.attributesByName["mealSlotId"])

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("Lightstack.sqlite")
        let entryId = UUID()

        do {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: v5Model)
            let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
            let ctx = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            ctx.persistentStoreCoordinator = coordinator
            try ctx.performAndWait {
                let e = NSEntityDescription.insertNewObject(forEntityName: "CDFoodEntry", into: ctx)
                e.setValue(entryId, forKey: "id"); e.setValue(UUID(), forKey: "userId")
                e.setValue(Date(), forKey: "date"); e.setValue("Old entry", forKey: "name")
                e.setValue(250.0, forKey: "kcal")
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
        let migrated = try XCTUnwrap(ctx.fetch(CDFoodEntry.fetchRequest() as NSFetchRequest<CDFoodEntry>).first)
        XCTAssertEqual(migrated.id, entryId)
        XCTAssertEqual(migrated.kcal, 250)
        XCTAssertNil(migrated.mealSlotId, "legacy entries have no meal")
        XCTAssertEqual(try ctx.count(for: CDMealSlot.fetchRequest() as NSFetchRequest<CDMealSlot>), 0)

        let slot = CDMealSlot(context: ctx)
        MealSlot.defaults(userId: user)[0].apply(to: slot)
        let water = CDWaterEntry(context: ctx)
        WaterEntry.make(userId: user, date: today, amountMl: 500).apply(to: water)
        let note = CDDayNote(context: ctx)
        DayNote(id: UUID(), userId: user, date: today, text: "hi", createdAt: Date(), updatedAt: Date()).apply(to: note)
        try ctx.save()
        XCTAssertEqual(try ctx.count(for: CDMealSlot.fetchRequest() as NSFetchRequest<CDMealSlot>), 1)
    }

    // MARK: - Meal slots

    func testDefaultSeedingIsIdempotentAndOrdered() {
        let d = makeDevice()
        let first = d.repo.ensureDefaultMealSlots(userId: user)
        let second = d.repo.ensureDefaultMealSlots(userId: user)
        XCTAssertEqual(first.map(\.name), ["Breakfast", "Lunch", "Dinner", "Snack"])
        XCTAssertEqual(second.map(\.id), first.map(\.id))
        XCTAssertEqual(d.storage.fetchMealSlots(userId: user).count, 4)
        XCTAssertEqual(d.repo.mealSlots(userId: user).map(\.sortOrder), [0, 1, 2, 3])
    }

    func testDefaultIdsAreStablePerUser() {
        let a = MealSlot.defaults(userId: user)
        XCTAssertEqual(a.map(\.id), MealSlot.defaults(userId: user).map(\.id))
        XCTAssertNotEqual(a.map(\.id), MealSlot.defaults(userId: UUID()).map(\.id))
        XCTAssertEqual(Set(a.map(\.id)).count, 4)
    }

    func testSeedingDoesNotRecreateDefaultsAfterAnArchive() {
        let d = makeDevice()
        let slots = d.repo.ensureDefaultMealSlots(userId: user)
        for slot in slots { d.repo.archiveMealSlot(id: slot.id) }
        XCTAssertTrue(d.repo.ensureDefaultMealSlots(userId: user).isEmpty)
        XCTAssertEqual(d.storage.fetchMealSlots(userId: user).count, 4, "archived slots count as existing")
    }

    func testMealSlotAddRenameArchiveReorder() {
        let d = makeDevice()
        let defaults = d.repo.ensureDefaultMealSlots(userId: user)
        let pre = d.repo.addMealSlot(userId: user, name: "  Pre-workout ")
        XCTAssertEqual(pre?.name, "Pre-workout")
        XCTAssertEqual(pre?.sortOrder, 4)
        XCTAssertNil(d.repo.addMealSlot(userId: user, name: "   "))

        XCTAssertEqual(d.repo.renameMealSlot(id: defaults[1].id, name: "Midday")?.name, "Midday")
        XCTAssertNil(d.repo.renameMealSlot(id: defaults[1].id, name: ""))

        d.repo.archiveMealSlot(id: defaults[3].id)
        XCTAssertEqual(d.repo.mealSlots(userId: user).count, 4)
        XCTAssertEqual(d.repo.mealSlots(userId: user, includeArchived: true).count, 5)

        let order = [pre?.id, defaults[0].id, defaults[2].id, defaults[1].id].compactMap { $0 }
        d.repo.reorderMealSlots(userId: user, orderedIds: order)
        XCTAssertEqual(d.repo.mealSlots(userId: user).map(\.name), ["Pre-workout", "Breakfast", "Dinner", "Midday"])
        d.repo.unarchiveMealSlot(id: defaults[3].id)
        XCTAssertEqual(d.repo.mealSlots(userId: user).last?.name, "Snack", "unarchived slot keeps its place after the ordered ones")
    }

    // MARK: - Batch logging

    func testBatchLogPutsAllFoodsInOneMealWithOneQueuePass() async {
        let d = makeDevice()
        let slots = d.repo.ensureDefaultMealSlots(userId: user)
        let a = d.repo.saveFood(NutritionFood.make(userId: user, name: "Oats", nutrients: nutrients(150, 5, 27, 3)))
        let b = d.repo.saveFood(NutritionFood.make(userId: user, name: "Egg", nutrients: nutrients(70, 6, 1, 5)))
        let c = d.repo.saveFood(NutritionFood.make(userId: user, name: "Milk", nutrients: nutrients(100, 8, 12, 2)))
        let before = await d.queuedTypes()

        let entries = d.repo.logFoods([PlateItem(food: a, servings: 2), PlateItem(food: b), PlateItem(food: c, servings: 0.5)],
                                      mealSlotId: slots[0].id, on: today)
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries.allSatisfy { $0.mealSlotId == slots[0].id })
        XCTAssertEqual(entries.map(\.servings), [2, 1, 0.5])
        XCTAssertEqual(d.storage.fetchFoodEntries(userId: user, on: today).count, 3)
        XCTAssertNotNil(d.repo.food(id: a.id)?.lastUsedAt)
        XCTAssertEqual(d.repo.logFoods([], mealSlotId: nil, on: today).count, 0)

        let after = await d.queuedTypes()
        func added(_ type: QueuedOperationType) -> Int { after.filter { $0 == type }.count - before.filter { $0 == type }.count }
        XCTAssertEqual(added(.upsertFoodEntry), 3)
        XCTAssertEqual(added(.upsertMealSlot), 1, "an untouched seeded slot is queued next to its entries")
        XCTAssertEqual(after.filter { $0 == .upsertFood }.count, 3, "same record key: one queued op per food")
    }

    func testMoveEntryBetweenMeals() {
        let d = makeDevice()
        let slots = d.repo.ensureDefaultMealSlots(userId: user)
        let entry = d.repo.quickAdd(userId: user, on: today, name: "Bar", nutrients: nutrients(200, 10, 20, 5), mealSlotId: slots[0].id)
        XCTAssertEqual(d.storage.fetchFoodEntry(id: entry.id)?.mealSlotId, slots[0].id)
        d.repo.moveEntry(id: entry.id, toMealSlot: slots[3].id, userId: user)
        XCTAssertEqual(d.storage.fetchFoodEntry(id: entry.id)?.mealSlotId, slots[3].id)
    }

    // MARK: - Day summary

    func testDaySummaryTotalsPerMealWithUnassignedAndArchived() {
        let d = makeDevice()
        let slots = d.repo.ensureDefaultMealSlots(userId: user)
        d.repo.setTarget(userId: user, effectiveDate: today, protein: 100, carbs: 200, fat: 50)
        d.repo.quickAdd(userId: user, on: today, name: "Oats", nutrients: nutrients(300, 10, 50, 5, fiber: 6), servings: 2, mealSlotId: slots[0].id)
        d.repo.quickAdd(userId: user, on: today, name: "Chicken", nutrients: nutrients(400, 40, 0, 10, sodium: 300), mealSlotId: slots[1].id)
        d.repo.quickAdd(userId: user, on: today, name: "Old entry", nutrients: nutrients(100, 1, 2, 3))   // no meal
        d.repo.addWater(userId: user, amountMl: 500, on: today)
        d.repo.addWater(userId: user, amountMl: 250, on: today)
        d.repo.setDayNote(userId: user, on: today, text: "Felt good")

        var summary = d.repo.daySummary(userId: user, on: today)
        XCTAssertEqual(summary.meals.map { $0.slot?.name }, ["Breakfast", "Lunch", "Dinner", "Snack"])
        XCTAssertEqual(summary.meal(for: slots[0].id)?.totals.kcal, 600)
        XCTAssertEqual(summary.meal(for: slots[0].id)?.totals.micros[.fiber], 12)
        XCTAssertEqual(summary.meal(for: slots[1].id)?.totals.protein, 40)
        XCTAssertEqual(summary.meal(for: slots[2].id)?.entries.count, 0, "empty meals are still listed")
        XCTAssertEqual(summary.unassigned.entries.map(\.name), ["Old entry"])
        XCTAssertEqual(summary.unassigned.totals.kcal, 100)
        XCTAssertEqual(summary.totals.kcal, 1100)
        XCTAssertEqual(summary.totals.micros[.sodium], 300)
        XCTAssertNil(summary.totals.micros[.potassium])
        XCTAssertEqual(summary.waterMl, 750)
        XCTAssertEqual(summary.note?.text, "Felt good")
        XCTAssertEqual(summary.target?.protein, 100)
        XCTAssertEqual(summary.remaining?.kcal, 1650 - 1100)
        XCTAssertEqual(summary.meals.reduce(0) { $0 + $1.totals.kcal } + summary.unassigned.totals.kcal, summary.totals.kcal)

        // Archiving a meal that holds entries keeps those entries visible; an empty archived meal disappears.
        d.repo.archiveMealSlot(id: slots[0].id)
        d.repo.archiveMealSlot(id: slots[3].id)
        summary = d.repo.daySummary(userId: user, on: today)
        XCTAssertEqual(summary.meals.map { $0.slot?.name }, ["Lunch", "Dinner", "Breakfast"])
        XCTAssertEqual(summary.totals.kcal, 1100)

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        let empty = d.repo.daySummary(userId: user, on: tomorrow)
        XCTAssertEqual(empty.totals.kcal, 0)
        XCTAssertEqual(empty.waterMl, 0)
        XCTAssertNil(empty.note)
    }

    // MARK: - Water

    func testWaterTotalsPerDayDeleteAndUnits() async {
        let d = makeDevice()
        let a = d.repo.addWater(userId: user, amountMl: 300, on: today)
        d.repo.addWater(userId: user, amountMl: 200, on: today)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        d.repo.addWater(userId: user, amountMl: 999, on: yesterday)
        XCTAssertNil(d.repo.addWater(userId: user, amountMl: 0, on: today))
        XCTAssertEqual(d.repo.waterTotalMl(userId: user, on: today), 500)
        XCTAssertEqual(d.repo.waterTotalMl(userId: user, on: yesterday), 999)

        XCTAssertEqual(d.repo.updateWater(id: a?.id ?? UUID(), userId: user, amountMl: 400)?.amountMl, 400)
        XCTAssertEqual(d.repo.waterTotalMl(userId: user, on: today), 600)
        d.repo.deleteWater(id: a?.id ?? UUID(), userId: user)
        XCTAssertEqual(d.repo.waterTotalMl(userId: user, on: today), 200)
        let types = await d.queuedTypes()
        XCTAssertTrue(types.contains(.deleteWaterEntry))
        XCTAssertTrue(types.contains(.insertTombstone))

        XCTAssertEqual(WaterUnit.flOz.fromMl(WaterUnit.mlPerFlOz * 64), 64, accuracy: 0.0001)
        XCTAssertEqual(WaterUnit.flOz.toMl(8), 236.588, accuracy: 0.001)
        XCTAssertEqual(WaterUnit.ml.fromMl(250), 250)
        XCTAssertEqual(WaterUnit.flOz.format(ml: 1893), "64 fl oz")
        let defaults = UserDefaults(suiteName: "water-\(UUID().uuidString)") ?? .standard
        XCTAssertEqual(WaterUnit.current(defaults: defaults), .flOz, "fl oz is the default")
        WaterUnit.setCurrent(.ml, defaults: defaults)
        XCTAssertEqual(WaterUnit.current(defaults: defaults), .ml)
    }

    // MARK: - Day notes

    func testDayNoteUpsertKeepsOneRowPerDay() async {
        let d = makeDevice()
        XCTAssertNil(d.repo.setDayNote(userId: user, on: today, text: ""), "nothing to save")
        let first = d.repo.setDayNote(userId: user, on: today, text: "Cheat meal")
        let second = d.repo.setDayNote(userId: user, on: today.addingTimeInterval(3600), text: "Cheat meal, no regrets")
        XCTAssertEqual(first?.id, second?.id)
        XCTAssertEqual(first?.id, DayNote.id(userId: user, date: today))
        XCTAssertEqual(d.storage.fetchAllDayNotes(userId: user).count, 1)
        XCTAssertEqual(d.repo.dayNote(userId: user, on: today)?.text, "Cheat meal, no regrets")
        d.repo.setDayNote(userId: user, on: today, text: "")
        XCTAssertEqual(d.repo.dayNote(userId: user, on: today)?.text, "")
        XCTAssertEqual(d.storage.fetchAllDayNotes(userId: user).count, 1, "clearing keeps the row")
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        XCTAssertNil(d.repo.dayNote(userId: user, on: tomorrow))
        XCTAssertNotEqual(DayNote.id(userId: user, date: tomorrow), DayNote.id(userId: user, date: today))
        let types = await d.queuedTypes()
        XCTAssertEqual(types.filter { $0 == .upsertDayNote }.count, 1, "same record key: the queue keeps the latest payload")
    }

    // MARK: - Payloads (every NOT NULL column, always)

    func testJournalPayloadsEncodeEveryNotNullColumn() throws {
        let slot = MealSlot(id: UUID(), userId: user, name: "Snack", sortOrder: 0, isArchived: false, createdAt: Date(), updatedAt: Date())
        let water = WaterEntry.make(userId: user, date: today, amountMl: 0)
        let note = DayNote(id: UUID(), userId: user, date: today, text: "", createdAt: Date(), updatedAt: Date())
        let entry = FoodEntry(id: UUID(), userId: user, date: today, foodId: nil, name: "", servings: 0, servingLabel: "serving",
                              perServing: NutrientValues(), source: .quick, createdAt: Date(), updatedAt: Date())
        for forCloud in [true, false] {
            let s = try jsonObject(slot, forCloud: forCloud)
            for column in ["id", "user_id", "name", "sort_order", "is_archived", "created_at", "updated_at"] {
                XCTAssertNotNil(s[column], "meal_slots.\(column) missing (cloud=\(forCloud))")
            }
            let w = try jsonObject(water, forCloud: forCloud)
            for column in ["id", "user_id", "date", "amount_ml", "created_at", "updated_at"] {
                XCTAssertNotNil(w[column], "water_entries.\(column) missing (cloud=\(forCloud))")
            }
            let n = try jsonObject(note, forCloud: forCloud)
            for column in ["id", "user_id", "date", "text", "created_at", "updated_at"] {
                XCTAssertNotNil(n[column], "day_notes.\(column) missing (cloud=\(forCloud)); empty text must still be sent")
            }
            let e = try jsonObject(entry, forCloud: forCloud)
            XCTAssertTrue(e.keys.contains("meal_slot_id") && e["meal_slot_id"] is NSNull, "meal_slot_id is sent as an explicit null")
        }
        XCTAssertEqual(try jsonObject(water, forCloud: true)["date"] as? String, RemoteDate.dayString(today))
        XCTAssertEqual(try jsonObject(note, forCloud: true)["date"] as? String, RemoteDate.dayString(today))
        var withSlot = entry
        withSlot.mealSlotId = slot.id
        XCTAssertEqual(try jsonObject(withSlot, forCloud: true)["meal_slot_id"] as? String, slot.id.uuidString)
    }

    func testJournalQueueEncodingRoundTrips() throws {
        let slot = MealSlot(id: UUID(), userId: user, name: "Pre", sortOrder: 3, isArchived: true, createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(try JSONDecoder().decode(MealSlot.self, from: JSONEncoder().encode(slot)), slot)
        let water = WaterEntry.make(userId: user, date: today, amountMl: 355)
        XCTAssertEqual(try JSONDecoder().decode(WaterEntry.self, from: JSONEncoder().encode(water)), water)
        let note = DayNote(id: UUID(), userId: user, date: today, text: "x", createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(try JSONDecoder().decode(DayNote.self, from: JSONEncoder().encode(note)), note)
        var entry = FoodEntry.make(from: NutritionFood.make(userId: user, name: "F", nutrients: NutrientValues()), servings: 1, on: today, mealSlotId: slot.id)
        entry.createdAt = Date(timeIntervalSince1970: 5); entry.updatedAt = entry.createdAt
        XCTAssertEqual(try JSONDecoder().decode(FoodEntry.self, from: JSONEncoder().encode(entry)).mealSlotId, slot.id)
    }

    func testOldQueuedEntryPayloadWithoutMealSlotStillDecodes() throws {
        let json = """
        {"id":"\(UUID())","user_id":"\(user)","date":"2026-10-24","name":"Toast","servings":1,"serving_label":"slice",
         "kcal":80,"protein_g":3,"carbs_g":14,"fat_g":1,"source":"quick","created_at":"2026-10-24T10:00:00Z","updated_at":"2026-10-24T10:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertNil(try decoder.decode(FoodEntry.self, from: Data(json.utf8)).mealSlotId)
    }

    // MARK: - Sync

    func testFlushUploadsSlotsBeforeEntriesAndEverythingArrives() async {
        let remote = FakeRemote()
        let d = makeDevice(remote: remote)
        let slots = d.repo.ensureDefaultMealSlots(userId: user)
        let entry = d.repo.quickAdd(userId: user, on: today, name: "Bar", nutrients: nutrients(200, 10, 20, 5), mealSlotId: slots[1].id)
        let water = d.repo.addWater(userId: user, amountMl: 330, on: today)
        let note = d.repo.setDayNote(userId: user, on: today, text: "ok")
        let renamed = d.repo.addMealSlot(userId: user, name: "Supper")
        await d.stack.flushAll()

        let calls = remote.calls
        let slotIndex = calls.firstIndex { $0.hasPrefix("upsertMealSlot:") }
        let entryIndex = calls.firstIndex { $0.hasPrefix("upsertFoodEntry:") }
        XCTAssertNotNil(slotIndex)
        XCTAssertLessThan(slotIndex ?? 0, entryIndex ?? 0, "FK order: meal slots before entries")
        XCTAssertEqual(remote.foodEntries[entry.id]?.mealSlotId, slots[1].id)
        XCTAssertNotNil(remote.mealSlots[slots[1].id])
        XCTAssertNotNil(remote.mealSlots[renamed?.id ?? UUID()])
        XCTAssertNotNil(remote.waterEntries[water?.id ?? UUID()])
        XCTAssertEqual(remote.dayNotes[note?.id ?? UUID()]?.text, "ok")

        d.repo.deleteWater(id: water?.id ?? UUID(), userId: user)
        await d.stack.flushAll()
        XCTAssertNil(remote.waterEntries[water?.id ?? UUID()])
        XCTAssertTrue(remote.tombstones.contains("water_entry:\((water?.id ?? UUID()).uuidString)"))
    }

    func testFreshDeviceRestoresJournalDataWithoutDuplicatingDefaults() async throws {
        let remote = FakeRemote()
        let slots = MealSlot.defaults(userId: user).map { slot -> MealSlot in
            var s = slot
            if s.sortOrder == 1 { s.name = "Midday"; s.updatedAt = Date() }
            return s
        }
        slots.forEach { remote.seedMealSlot($0) }
        let entry = FoodEntry(id: UUID(), userId: user, date: today, foodId: nil, name: "Cloud meal", servings: 1, servingLabel: "serving",
                              perServing: nutrients(100, 1, 1, 1), source: .quick, createdAt: Date(), updatedAt: Date(), mealSlotId: slots[1].id)
        remote.seedFoodEntry(entry)
        for i in 0..<3 { remote.seedWaterEntry(WaterEntry.make(userId: user, date: today, amountMl: Double(100 * (i + 1)))) }
        let note = DayNote(id: DayNote.id(userId: user, date: today), userId: user, date: today, text: "from cloud", createdAt: Date(), updatedAt: Date())
        remote.seedDayNote(note)

        let d = makeDevice(remote: remote, pageSize: 2)
        // The app seeded defaults before the restore finished.
        d.repo.ensureDefaultMealSlots(userId: user)
        let summary = try await d.service.restoreAll(userId: user, assumeFreshInstall: true)

        let local = d.storage.fetchMealSlots(userId: user)
        XCTAssertEqual(local.count, 4, "no duplicate defaults")
        XCTAssertEqual(local.first { $0.id == slots[1].id }?.name, "Midday", "the cloud's rename beats the untouched seed")
        XCTAssertEqual(d.storage.fetchFoodEntry(id: entry.id)?.mealSlotId, slots[1].id)
        XCTAssertEqual(d.repo.waterTotalMl(userId: user, on: today), 600)
        XCTAssertEqual(d.repo.dayNote(userId: user, on: today)?.text, "from cloud")
        XCTAssertEqual(remote.readLog.filter { $0 == "fetchWaterEntriesPage" }.count, 2, "pages of 2 until a short page")
        XCTAssertGreaterThanOrEqual(summary.nutritionApplied, 8)

        await d.stack.flushAll()
        XCTAssertEqual(remote.mealSlots.count, 4)
        XCTAssertEqual(remote.mealSlots[slots[1].id]?.name, "Midday", "the stale seed must not overwrite the rename in the cloud")
    }

    func testRestoreTombstoneRemovesWaterAndRepairUploadsMissingJournalRows() async throws {
        let remote = FakeRemote()
        let d = makeDevice(remote: remote)
        let gone = d.repo.addWater(userId: user, amountMl: 100, on: today)
        remote.seedTombstone(.waterEntry, gone?.id ?? UUID())
        let kept = WaterEntry.make(userId: user, date: today, amountMl: 250)
        d.storage.saveWaterEntry(kept)                       // no queue: like a lost write
        d.storage.saveMealSlots(MealSlot.defaults(userId: user))
        let summary = try await d.service.restoreAll(userId: user, assumeFreshInstall: true)

        XCTAssertNil(d.storage.fetchWaterEntry(id: gone?.id ?? UUID()))
        XCTAssertNotNil(d.storage.fetchWaterEntry(id: kept.id))
        XCTAssertEqual(summary.repairedNutrition, 5, "one water entry and four default meals")
        let types = await d.queuedTypes()
        XCTAssertFalse(types.contains(.upsertFoodEntry))
        await d.stack.flushAll()
        XCTAssertNotNil(remote.waterEntries[kept.id])
        XCTAssertEqual(remote.mealSlots.count, 4)
    }

    // MARK: - Tracker config

    func testTrackerConfigDefaultsAndEditing() {
        let defaults = UserDefaults(suiteName: "trackers-\(UUID().uuidString)") ?? .standard
        let store = NutrientTrackerStore(userId: user, defaults: defaults)
        XCTAssertEqual(store.trackers.map(\.nutrient), [.water, .micro(.fiber), .micro(.sodium)])
        XCTAssertEqual(store.available.count, TrackedNutrient.allCases.count - 3)

        store.add(.micro(.potassium), dailyTarget: 3400)
        store.add(.micro(.potassium))
        XCTAssertEqual(store.trackers.count, 4, "no duplicates")
        store.setTarget(2300, for: .micro(.sodium))
        store.setTarget(2500, for: .water)
        store.remove(.micro(.fiber))
        store.move(from: 2, to: 0)
        let reloaded = NutrientTrackerStore(userId: user, defaults: defaults).trackers
        XCTAssertEqual(reloaded.map(\.nutrient), [.micro(.potassium), .water, .micro(.sodium)])
        XCTAssertEqual(reloaded.first { $0.nutrient == .micro(.sodium) }?.dailyTarget, 2300)
        store.setTarget(0, for: .water)
        XCTAssertNil(store.trackers.first { $0.nutrient == .water }?.dailyTarget)
        XCTAssertEqual(NutrientTrackerStore(userId: UUID(), defaults: defaults).trackers.count, 3, "settings are per user")
    }
}
