import XCTest
import CoreData
import Supabase
@testable import Lightstack

/// Nutrition phase 5 data layer: saved meals, recipes, serving-unit conversion, Core Data v10, sync and restore.
@MainActor
final class NutritionKitchenTests: XCTestCase {

    private let user = UUID()
    private let today = Date().startOfDay

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
        let defaults = UserDefaults(suiteName: "nutri-kitchen-\(UUID().uuidString)") ?? .standard
        let pr = PRRepository(localStorage: stack.storage, offlineQueueManager: stack.queue)
        let service = SyncRestoreService(remote: remote, storage: stack.storage, queue: stack.queue, prRepository: pr,
                                         currentUserId: { uid }, defaults: defaults, pageSize: pageSize)
        return Device(stack: stack, repo: NutritionRepository(localStorage: stack.storage, offlineQueueManager: stack.queue), service: service)
    }

    private func nutrients(_ kcal: Double, _ p: Double, _ c: Double, _ f: Double, fiber: Double? = nil, sodium: Double? = nil) -> NutrientValues {
        var micros = Micronutrients()
        micros[.fiber] = fiber
        micros[.sodium] = sodium
        return NutrientValues(kcal: kcal, protein: p, carbs: c, fat: f, micros: micros)
    }

    @discardableResult
    private func addFood(_ d: Device, _ name: String, _ n: NutrientValues, unit: String = "serving", amount: Double = 1,
                         grams: Double? = nil) -> NutritionFood {
        d.repo.saveFood(NutritionFood.make(userId: user, name: name, servingLabel: "1 serving", servingUnit: unit,
                                           servingAmount: amount, servingGrams: grams, nutrients: n))
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

    private func food(_ unit: String = "serving", amount: Double = 1, grams: Double? = nil) -> NutritionFood {
        NutritionFood.make(userId: user, name: "F", servingUnit: unit, servingAmount: amount, servingGrams: grams,
                           nutrients: NutrientValues(kcal: 100))
    }

    // MARK: - Recipe maths

    func testRecipePerServingSumsIngredientsIncludingMicrosAndDividesByYield() throws {
        let d = makeDevice()
        let egg = addFood(d, "Egg", nutrients(70, 6, 0.5, 5, fiber: 0, sodium: 70))
        let oats = addFood(d, "Oats", nutrients(150, 5, 27, 3, fiber: 4))
        let recipe = try XCTUnwrap(d.repo.saveRecipe(userId: user, name: "Bowl",
                                                     ingredients: [PlateItem(food: egg, servings: 4), PlateItem(food: oats, servings: 2)],
                                                     servingsYield: 4))
        // total: kcal 4*70+2*150 = 580 -> 145 per serving
        let derived = try XCTUnwrap(d.repo.recipeFood(recipeId: recipe.id))
        XCTAssertEqual(derived.source, .recipe)
        XCTAssertEqual(derived.nutrients.kcal, 145, accuracy: 0.0001)
        XCTAssertEqual(derived.nutrients.protein, (4 * 6 + 2 * 5) / 4.0, accuracy: 0.0001)
        XCTAssertEqual(derived.nutrients.carbs, (4 * 0.5 + 2 * 27) / 4.0, accuracy: 0.0001)
        XCTAssertEqual(derived.nutrients.fat, (4 * 5 + 2 * 3) / 4.0, accuracy: 0.0001)
        XCTAssertEqual(derived.nutrients.micros[.fiber] ?? -1, (0 + 8) / 4.0, accuracy: 0.0001)
        XCTAssertEqual(derived.nutrients.micros[.sodium] ?? -1, 70, accuracy: 0.0001, "only the egg knows sodium: 280 / 4")
        XCTAssertNil(derived.nutrients.micros[.iron], "unknown stays unknown")
        XCTAssertEqual(recipe.perServing, derived.nutrients)
        XCTAssertEqual(derived.id, recipe.collection.derivedFoodId)
    }

    func testCookedWeightSetsServingGramsOnlyWhenGiven() throws {
        let d = makeDevice()
        let rice = addFood(d, "Rice", nutrients(200, 4, 44, 0))
        let plain = try XCTUnwrap(d.repo.saveRecipe(userId: user, name: "Rice pot", ingredients: [PlateItem(food: rice)], servingsYield: 4))
        XCTAssertNil(d.repo.recipeFood(recipeId: plain.id)?.servingGrams)
        let weighed = try XCTUnwrap(d.repo.saveRecipe(userId: user, id: plain.id, name: "Rice pot", ingredients: [PlateItem(food: rice)],
                                                      servingsYield: 4, cookedWeightGrams: 1000))
        XCTAssertEqual(d.repo.recipeFood(recipeId: weighed.id)?.servingGrams ?? 0, 250, accuracy: 0.0001)
        let zero = try XCTUnwrap(d.repo.saveRecipe(userId: user, id: plain.id, name: "Rice pot", ingredients: [PlateItem(food: rice)],
                                                   servingsYield: 4, cookedWeightGrams: 0))
        XCTAssertNil(zero.collection.cookedWeightGrams)
        XCTAssertNil(d.repo.recipeFood(recipeId: zero.id)?.servingGrams)
    }

    func testRecipeRequiresPositiveYieldNameAndIngredients() {
        let d = makeDevice()
        let egg = addFood(d, "Egg", nutrients(70, 6, 0, 5))
        XCTAssertNil(d.repo.saveRecipe(userId: user, name: "A", ingredients: [PlateItem(food: egg)], servingsYield: 0))
        XCTAssertNil(d.repo.saveRecipe(userId: user, name: "A", ingredients: [PlateItem(food: egg)], servingsYield: -1))
        XCTAssertNil(d.repo.saveRecipe(userId: user, name: "  ", ingredients: [PlateItem(food: egg)], servingsYield: 1))
        XCTAssertNil(d.repo.saveRecipe(userId: user, name: "A", ingredients: [], servingsYield: 1))
        XCTAssertTrue(d.repo.recipes(userId: user).isEmpty)
    }

    func testRecipeIsLoggableLikeAFoodAndSearchable() throws {
        let d = makeDevice()
        let egg = addFood(d, "Egg", nutrients(100, 8, 0, 7))
        let recipe = try XCTUnwrap(d.repo.saveRecipe(userId: user, name: "Omelette", ingredients: [PlateItem(food: egg, servings: 2)], servingsYield: 2))
        XCTAssertTrue(d.repo.searchFoods(userId: user, query: "omel").contains { $0.source == .recipe })
        let entry = try XCTUnwrap(d.repo.logRecipe(id: recipe.id, userId: user, servings: 1.5, on: today))
        XCTAssertEqual(entry.foodId, recipe.collection.derivedFoodId)
        XCTAssertEqual(entry.total.kcal, 150, accuracy: 0.0001)
        // history keeps its snapshot when the recipe changes or goes
        _ = d.repo.saveRecipe(userId: user, id: recipe.id, name: "Omelette", ingredients: [PlateItem(food: egg, servings: 4)], servingsYield: 2)
        XCTAssertEqual(d.storage.fetchFoodEntry(id: entry.id)?.perServing.kcal ?? 0, 100, accuracy: 0.0001)
        d.repo.deleteRecipe(id: recipe.id, userId: user)
        XCTAssertEqual(d.storage.fetchFoodEntry(id: entry.id)?.perServing.kcal ?? 0, 100, accuracy: 0.0001)
        XCTAssertNil(d.storage.fetchFoodEntry(id: entry.id)?.foodId, "link dropped, snapshot kept")
    }

    func testDeleteRecipeRemovesItsDerivedFoodItemsAndQueuesTombstones() async throws {
        let d = makeDevice()
        let egg = addFood(d, "Egg", nutrients(100, 8, 0, 7))
        let recipe = try XCTUnwrap(d.repo.saveRecipe(userId: user, name: "R", ingredients: [PlateItem(food: egg)], servingsYield: 1))
        let derivedId = recipe.collection.derivedFoodId
        XCTAssertNotNil(d.storage.fetchFood(id: derivedId))
        d.repo.deleteRecipe(id: recipe.id, userId: user)
        XCTAssertNil(d.storage.fetchFood(id: derivedId))
        XCTAssertNil(d.storage.fetchFoodCollection(id: recipe.id))
        XCTAssertTrue(d.storage.fetchAllFoodCollectionItems(userId: user).isEmpty)
        XCTAssertNotNil(d.storage.fetchFood(id: egg.id), "ingredients are untouched")
        await d.stack.flushAll()
        XCTAssertTrue(d.stack.remote.tombstones.contains("food_collection:\(recipe.id.uuidString)"))
        XCTAssertTrue(d.stack.remote.tombstones.contains("food:\(derivedId.uuidString)"))
        XCTAssertNil(d.stack.remote.foodCollections[recipe.id])
        XCTAssertNil(d.stack.remote.foods[derivedId])
    }

    func testDeletingTheDerivedFoodDeletesTheRecipe() throws {
        let d = makeDevice()
        let egg = addFood(d, "Egg", nutrients(100, 8, 0, 7))
        let recipe = try XCTUnwrap(d.repo.saveRecipe(userId: user, name: "R", ingredients: [PlateItem(food: egg)], servingsYield: 1))
        d.repo.deleteFood(id: recipe.collection.derivedFoodId, userId: user)
        XCTAssertNil(d.storage.fetchFoodCollection(id: recipe.id))
        XCTAssertTrue(d.storage.fetchAllFoodCollectionItems(userId: user).isEmpty)
    }

    // MARK: - Recompute

    func testRecipeRecomputesWhenAnIngredientChanges() throws {
        let d = makeDevice()
        var egg = addFood(d, "Egg", nutrients(100, 8, 0, 7))
        let recipe = try XCTUnwrap(d.repo.saveRecipe(userId: user, name: "R", ingredients: [PlateItem(food: egg, servings: 2)], servingsYield: 2))
        XCTAssertEqual(d.repo.recipeFood(recipeId: recipe.id)?.nutrients.kcal ?? 0, 100, accuracy: 0.0001)
        egg.nutrients.kcal = 120
        d.repo.saveFood(egg)
        XCTAssertEqual(d.repo.recipeFood(recipeId: recipe.id)?.nutrients.kcal ?? 0, 120, accuracy: 0.0001)
    }

    func testRecipeDropsDeletedIngredientAndRecomputes() async throws {
        let d = makeDevice()
        let egg = addFood(d, "Egg", nutrients(100, 8, 0, 7))
        let oats = addFood(d, "Oats", nutrients(150, 5, 27, 3))
        let meal = try XCTUnwrap(d.repo.saveMeal(userId: user, name: "M", items: [PlateItem(food: egg), PlateItem(food: oats)]))
        let recipe = try XCTUnwrap(d.repo.saveRecipe(userId: user, name: "R",
                                                     ingredients: [PlateItem(food: egg), PlateItem(food: oats)], servingsYield: 1))
        XCTAssertEqual(d.repo.recipeFood(recipeId: recipe.id)?.nutrients.kcal ?? 0, 250, accuracy: 0.0001)
        d.repo.deleteFood(id: oats.id, userId: user)
        let reloaded = try XCTUnwrap(d.repo.kitchenCollection(id: recipe.id))
        XCTAssertEqual(reloaded.items.count, 1)
        XCTAssertEqual(d.repo.recipeFood(recipeId: recipe.id)?.nutrients.kcal ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(d.repo.kitchenCollection(id: meal.id)?.items.count, 1, "saved meals drop the food too")
        await d.stack.flushAll()
        XCTAssertEqual(d.stack.remote.foodCollectionItems.values.filter { $0.collectionId == recipe.id }.count, 1)
        XCTAssertEqual(d.stack.remote.foods[recipe.collection.derivedFoodId]?.nutrients.kcal ?? 0, 100, accuracy: 0.0001)
    }

    func testEditingARecipeReusesItemRowsAndDeletesRemovedOnes() async throws {
        let d = makeDevice()
        let egg = addFood(d, "Egg", nutrients(100, 8, 0, 7))
        let oats = addFood(d, "Oats", nutrients(150, 5, 27, 3))
        let first = try XCTUnwrap(d.repo.saveRecipe(userId: user, name: "R", ingredients: [PlateItem(food: egg), PlateItem(food: oats)], servingsYield: 1))
        let eggItemId = try XCTUnwrap(first.items.first { $0.foodId == egg.id }?.id)
        let second = try XCTUnwrap(d.repo.saveRecipe(userId: user, id: first.id, name: "R2", ingredients: [PlateItem(food: egg, servings: 3)], servingsYield: 1))
        XCTAssertEqual(second.items.count, 1)
        XCTAssertEqual(second.items.first?.id, eggItemId)
        XCTAssertEqual(second.items.first?.servings, 3)
        XCTAssertEqual(d.repo.recipeFood(recipeId: second.id)?.name, "R2")
        await d.stack.flushAll()
        XCTAssertEqual(d.stack.remote.foodCollectionItems.count, 1)
        XCTAssertEqual(d.stack.remote.tombstones.filter { $0.hasPrefix("food_collection_item:") }.count, 1)
    }

    // MARK: - Cycle guard

    func testRecipeCannotContainItsOwnDerivedFood() throws {
        let d = makeDevice()
        let egg = addFood(d, "Egg", nutrients(100, 8, 0, 7))
        let recipe = try XCTUnwrap(d.repo.saveRecipe(userId: user, name: "R", ingredients: [PlateItem(food: egg)], servingsYield: 1))
        let own = try XCTUnwrap(d.repo.recipeFood(recipeId: recipe.id))
        XCTAssertFalse(d.repo.canUseAsIngredient(foodId: own.id, inRecipe: recipe.id, userId: user))
        XCTAssertTrue(d.repo.canUseAsIngredient(foodId: egg.id, inRecipe: recipe.id, userId: user))
        XCTAssertTrue(d.repo.canUseAsIngredient(foodId: own.id, inRecipe: nil, userId: user), "an unsaved recipe cannot be referenced yet")
        let edited = try XCTUnwrap(d.repo.saveRecipe(userId: user, id: recipe.id, name: "R",
                                                     ingredients: [PlateItem(food: egg), PlateItem(food: own)], servingsYield: 1))
        XCTAssertEqual(edited.items.map(\.foodId), [egg.id], "the self reference is left out")
        XCTAssertNil(d.repo.saveRecipe(userId: user, id: recipe.id, name: "R", ingredients: [PlateItem(food: own)], servingsYield: 1),
                     "nothing usable left")
    }

    func testIndirectCycleIsRefusedAndRecipesCanNest() throws {
        let d = makeDevice()
        let egg = addFood(d, "Egg", nutrients(100, 8, 0, 7))
        let inner = try XCTUnwrap(d.repo.saveRecipe(userId: user, name: "Inner", ingredients: [PlateItem(food: egg, servings: 2)], servingsYield: 1))
        let innerFood = try XCTUnwrap(d.repo.recipeFood(recipeId: inner.id))
        let outer = try XCTUnwrap(d.repo.saveRecipe(userId: user, name: "Outer", ingredients: [PlateItem(food: innerFood)], servingsYield: 2))
        XCTAssertEqual(d.repo.recipeFood(recipeId: outer.id)?.nutrients.kcal ?? 0, 100, accuracy: 0.0001, "200 / 2")
        let outerFood = try XCTUnwrap(d.repo.recipeFood(recipeId: outer.id))
        XCTAssertFalse(d.repo.canUseAsIngredient(foodId: outerFood.id, inRecipe: inner.id, userId: user), "Outer already uses Inner")
        // a change deep inside flows up
        var bigger = egg
        bigger.nutrients.kcal = 150
        d.repo.saveFood(bigger)
        XCTAssertEqual(d.repo.recipeFood(recipeId: outer.id)?.nutrients.kcal ?? 0, 150, accuracy: 0.0001)
    }

    // MARK: - Saved meals

    func testLogMealCreatesOneLinkedEntryPerItemInTheSlotAndDay() throws {
        let d = makeDevice()
        let slots = d.repo.ensureDefaultMealSlots(userId: user)
        let lunch = try XCTUnwrap(slots.first { $0.name == "Lunch" })
        let egg = addFood(d, "Egg", nutrients(70, 6, 0, 5))
        let toast = addFood(d, "Toast", nutrients(80, 3, 14, 1))
        let meal = try XCTUnwrap(d.repo.saveMeal(userId: user, name: "Usual breakfast",
                                                 items: [PlateItem(food: egg, servings: 3), PlateItem(food: toast, servings: 2)]))
        let day = Calendar.current.date(byAdding: .day, value: -2, to: today) ?? today
        let entries = d.repo.logMeal(id: meal.id, userId: user, mealSlotId: lunch.id, on: day)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.servings), [3, 2])
        XCTAssertEqual(entries.map(\.foodId), [egg.id, toast.id])
        XCTAssertTrue(entries.allSatisfy { $0.mealSlotId == lunch.id && $0.date == day.startOfDay })
        XCTAssertEqual(d.storage.fetchFoodEntries(userId: user, on: day).count, 2)
        XCTAssertEqual(d.repo.daySummary(userId: user, on: day).totals.kcal, 3 * 70 + 2 * 80, accuracy: 0.0001)
        let doubled = d.repo.logMeal(id: meal.id, userId: user, mealSlotId: nil, on: today, servingsMultiplier: 2)
        XCTAssertEqual(doubled.map(\.servings), [6, 4])
        XCTAssertNotNil(d.repo.kitchenCollection(id: meal.id)?.collection.lastUsedAt)
    }

    func testLogMealRefusesRecipesAndOtherUsers() throws {
        let d = makeDevice()
        let egg = addFood(d, "Egg", nutrients(70, 6, 0, 5))
        let recipe = try XCTUnwrap(d.repo.saveRecipe(userId: user, name: "R", ingredients: [PlateItem(food: egg)], servingsYield: 1))
        let meal = try XCTUnwrap(d.repo.saveMeal(userId: user, name: "M", items: [PlateItem(food: egg)]))
        XCTAssertTrue(d.repo.logMeal(id: recipe.id, userId: user, mealSlotId: nil, on: today).isEmpty)
        XCTAssertTrue(d.repo.logMeal(id: meal.id, userId: UUID(), mealSlotId: nil, on: today).isEmpty)
    }

    func testSaveMealFromJournalEntriesUsesTheirServingsAndSnapshotsQuickAdds() throws {
        let d = makeDevice()
        let egg = addFood(d, "Egg", nutrients(70, 6, 0, 5))
        let e1 = d.repo.logFood(egg, servings: 3, on: today)
        let quick = d.repo.quickAdd(userId: user, on: today, name: "Mystery", nutrients: nutrients(300, 10, 30, 12), servings: 0.5)
        let meal = try XCTUnwrap(d.repo.saveMeal(userId: user, name: "Saved from journal", from: [e1, quick]))
        XCTAssertEqual(meal.lines.count, 2)
        XCTAssertEqual(meal.lines[0].food.id, egg.id)
        XCTAssertEqual(meal.lines[0].servings, 3)
        XCTAssertEqual(meal.lines[1].servings, 0.5)
        XCTAssertEqual(meal.lines[1].food.name, "Mystery")
        XCTAssertEqual(meal.lines[1].food.nutrients.kcal, 300, "the quick add became a saved food from its snapshot")
        XCTAssertEqual(meal.total.kcal, 3 * 70 + 0.5 * 300, accuracy: 0.0001)
        XCTAssertNil(d.repo.saveMeal(userId: user, name: "Empty", from: [FoodEntry]()))
    }

    func testSaveMealFromPlate() throws {
        let d = makeDevice()
        let egg = addFood(d, "Egg", nutrients(70, 6, 0, 5))
        let oats = addFood(d, "Oats", nutrients(150, 5, 27, 3))
        let meal = try XCTUnwrap(d.repo.saveMeal(userId: user, name: " Plate ", from: [PlateItem(food: egg, servings: 2), PlateItem(food: oats, servings: 0.5)]))
        XCTAssertEqual(meal.name, "Plate")
        XCTAssertEqual(meal.kind, .meal)
        XCTAssertEqual(meal.lines.map(\.servings), [2, 0.5])
        XCTAssertEqual(d.repo.savedMeals(userId: user, query: "oats").count, 1, "search also matches item names")
        XCTAssertEqual(d.repo.savedMeals(userId: user, query: "plat").count, 1)
        XCTAssertTrue(d.repo.recipes(userId: user).isEmpty)
        XCTAssertEqual(d.repo.kitchenCollections(userId: user).count, 1)
        d.repo.deleteMeal(id: meal.id, userId: user)
        XCTAssertTrue(d.repo.kitchenCollections(userId: user).isEmpty)
    }

    func testViewModelKitchenAPIs() throws {
        let d = makeDevice()
        let uid = user
        let vm = NutritionViewModel(repository: d.repo, userIdProvider: { uid })
        vm.reload()
        let egg = addFood(d, "Egg", nutrients(70, 6, 0, 5, fiber: 1))
        let meal = try XCTUnwrap(vm.saveMeal(name: "Eggs", from: [PlateItem(food: egg, servings: 3)]))
        let slot = try XCTUnwrap(vm.slots.first)
        let before = vm.kitchenVersion
        XCTAssertEqual(vm.logMeal(meal, mealSlotId: slot.id).count, 1)
        XCTAssertGreaterThan(vm.kitchenVersion, before)
        XCTAssertEqual(vm.summary?.meal(for: slot.id)?.entries.count, 1)
        let journalMeal = try XCTUnwrap(vm.saveMeal(name: "From journal", fromJournalMeal: slot.id))
        XCTAssertEqual(journalMeal.lines.first?.servings, 3)
        let recipe = try XCTUnwrap(vm.saveRecipe(name: "Pot", ingredients: [PlateItem(food: egg, servings: 6)], servingsYield: 3))
        XCTAssertEqual(vm.recipes().count, 1)
        XCTAssertEqual(vm.kitchenItems().count, 3)
        XCTAssertEqual(vm.kitchenItems(kind: .meal, query: "journal").count, 1)
        XCTAssertNotNil(vm.logRecipe(recipe, servings: 1, mealSlotId: slot.id))
        XCTAssertFalse(vm.canUseAsIngredient(try XCTUnwrap(d.repo.recipeFood(recipeId: recipe.id)), in: recipe))
        let preview = NutritionViewModel.recipePreview(ingredients: [PlateItem(food: egg, servings: 6)], servingsYield: 3, cookedWeightGrams: 600)
        XCTAssertEqual(preview.perServing.kcal, 140, accuracy: 0.0001)
        XCTAssertEqual(preview.servingGrams ?? 0, 200, accuracy: 0.0001)
        vm.deleteRecipe(recipe)
        vm.deleteMeal(meal)
        XCTAssertEqual(vm.kitchenItems().count, 1)
    }

    // MARK: - Serving units

    func testUnitsAvailableForAMassFoodAndAServingOnlyFood() {
        let grams = food("g", amount: 30)
        XCTAssertEqual(ServingUnitConverter.availableUnits(for: grams), [.serving, .g, .oz])
        let plain = food("serving")
        XCTAssertEqual(ServingUnitConverter.availableUnits(for: plain), [.serving])
        let withGrams = food("piece", amount: 1, grams: 45)
        XCTAssertEqual(ServingUnitConverter.availableUnits(for: withGrams), [.serving, .g, .oz])
        let ozFood = food("oz", amount: 2)
        XCTAssertEqual(ServingUnitConverter.gramsPerServing(of: ozFood) ?? 0, 56.699, accuracy: 0.001)
    }

    func testVolumeFoodOffersVolumeUnitsAndConvertsBetweenThem() {
        let milk = food("cup", amount: 1)
        XCTAssertEqual(ServingUnitConverter.availableUnits(for: milk), [.serving, .ml, .flOz, .cup, .tbsp, .tsp])
        XCTAssertEqual(ServingUnitConverter.convert(1, from: .cup, to: .ml, for: milk) ?? 0, 236.588, accuracy: 0.0001)
        XCTAssertEqual(ServingUnitConverter.convert(1, from: .cup, to: .tbsp, for: milk) ?? 0, 236.588 / 14.7868, accuracy: 0.0001)
        XCTAssertEqual(ServingUnitConverter.convert(1, from: .flOz, to: .tsp, for: milk) ?? 0, 29.5735 / 4.92892, accuracy: 0.0001)
        XCTAssertEqual(ServingUnitConverter.servings(amount: 118.294, unit: .ml, for: milk) ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(ServingUnitConverter.servings(amount: 8, unit: .tbsp, for: milk) ?? 0, 8 * 14.7868 / 236.588, accuracy: 0.0001)
        let shot = food("ml", amount: 30)
        XCTAssertEqual(ServingUnitConverter.servings(amount: 60, unit: .ml, for: shot) ?? 0, 2, accuracy: 0.0001)
        XCTAssertEqual(ServingUnitConverter.amount(forServings: 2, in: .flOz, for: shot) ?? 0, 60 / 29.5735, accuracy: 0.0001)
    }

    func testGramAndOunceConversions() {
        let bar = food("g", amount: 40)
        XCTAssertEqual(ServingUnitConverter.servings(amount: 80, unit: .g, for: bar) ?? 0, 2, accuracy: 0.0001)
        XCTAssertEqual(ServingUnitConverter.servings(amount: 1, unit: .oz, for: bar) ?? 0, 28.3495 / 40, accuracy: 0.0001)
        XCTAssertEqual(ServingUnitConverter.convert(100, from: .g, to: .oz, for: bar) ?? 0, 100 / 28.3495, accuracy: 0.0001)
        XCTAssertEqual(ServingUnitConverter.servings(amount: 3, unit: .serving, for: bar), 3)
        let ratio = food("piece", amount: 1, grams: 50)
        XCTAssertEqual(ServingUnitConverter.servings(amount: 150, unit: .g, for: ratio) ?? 0, 3, accuracy: 0.0001)
    }

    func testMassAndVolumeAreNotConvertedWithoutBoth() {
        let grams = food("g", amount: 30)
        XCTAssertNil(ServingUnitConverter.servings(amount: 1, unit: .cup, for: grams))
        XCTAssertNil(ServingUnitConverter.convert(30, from: .g, to: .ml, for: grams))
        let milk = food("cup", amount: 1)
        XCTAssertNil(ServingUnitConverter.servings(amount: 100, unit: .g, for: milk))
        XCTAssertNil(ServingUnitConverter.convert(1, from: .cup, to: .oz, for: milk))
        XCTAssertNil(ServingUnitConverter.servings(amount: 1, unit: .piece, for: grams), "piece is not a loggable unit")
        XCTAssertNil(ServingUnitConverter.servings(amount: -1, unit: .serving, for: grams))
        // a cup with known grams measures both ways, each through the serving
        let oats = food("cup", amount: 1, grams: 90)
        XCTAssertEqual(ServingUnitConverter.availableUnits(for: oats), [.serving, .g, .oz, .ml, .flOz, .cup, .tbsp, .tsp])
        XCTAssertEqual(ServingUnitConverter.convert(45, from: .g, to: .cup, for: oats) ?? 0, 0.5, accuracy: 0.0001)
    }

    func testUnitLabelsAndFavoriteOrdering() {
        XCTAssertEqual(ServingUnitConverter.label(amount: 150, unit: .g), "150 g")
        XCTAssertEqual(ServingUnitConverter.label(amount: 1.5, unit: .cup), "1.5 cup")
        XCTAssertEqual(ServingUnitConverter.label(amount: 0.333, unit: .flOz), "0.33 fl oz")
        XCTAssertEqual(ServingUnitConverter.label(amount: 1, unit: .serving), "1 serving")
        XCTAssertEqual(ServingUnitConverter.label(amount: 2, unit: .serving), "2 servings")
        let bar = food("g", amount: 50)
        XCTAssertEqual(ServingUnitConverter.label(servings: 3, in: .g, for: bar), "150 g")
        XCTAssertEqual(ServingUnitConverter.label(servings: 2, in: .cup, for: bar), "2 servings", "falls back when the unit does not apply")

        let units = ServingUnitConverter.availableUnits(for: bar)
        XCTAssertEqual(ServingUnitConverter.ordered(units, favorites: [.oz, .cup, .g]), [.oz, .g, .serving])
        XCTAssertEqual(ServingUnitConverter.ordered(units, favorites: []), [.serving, .g, .oz])

        let defaults = UserDefaults(suiteName: "fav-units-\(UUID().uuidString)") ?? .standard
        XCTAssertEqual(ServingUnitPreferences.favorites(defaults: defaults), [])
        ServingUnitPreferences.setFavorites([.g, .cup, .g, .tbsp], defaults: defaults)
        XCTAssertEqual(ServingUnitPreferences.favorites(defaults: defaults), [.g, .cup, .tbsp])
    }

    func testViewModelLogsByAmountAndUnit() throws {
        let d = makeDevice()
        let uid = user
        let vm = NutritionViewModel(repository: d.repo, userIdProvider: { uid })
        vm.reload()
        let rice = addFood(d, "Rice", nutrients(200, 4, 44, 0), unit: "g", amount: 100)
        XCTAssertTrue(vm.log(rice, amount: 150, unit: .g))
        XCTAssertFalse(vm.log(rice, amount: 1, unit: .cup))
        XCTAssertEqual(vm.summary?.entries.count, 1)
        let entry = try XCTUnwrap(vm.summary?.entries.first)
        XCTAssertEqual(entry.servings, 150, accuracy: 0.0001)
        XCTAssertEqual(entry.servingLabel, NutritionUnit.g.displayName)
        // Totals stay exact: the food's per-serving values (one serving = 100 g) x 1.5.
        let expected = rice.nutrients.scaled(by: 1.5)
        XCTAssertEqual(entry.total.kcal, expected.kcal, accuracy: 0.01)
        XCTAssertEqual(entry.total.protein, expected.protein, accuracy: 0.01)
        XCTAssertEqual(entry.total.carbs, expected.carbs, accuracy: 0.01)
        XCTAssertEqual(entry.total.fat, expected.fat, accuracy: 0.01)
        XCTAssertEqual(vm.servings(amount: 200, unit: .g, for: rice) ?? 0, 2, accuracy: 0.0001)
        XCTAssertEqual(vm.unitLabel(servings: 1.5, in: .g, for: rice), "150 g")
        XCTAssertEqual(vm.servingUnits(for: rice).first, .serving)
    }

    // MARK: - Core Data v10

    func testMigratesV9StoreToV10AddsKitchenEntitiesAndKeepsFoods() throws {
        let bundle = Bundle(for: LocalStorageService.self)
        let v9URL = try XCTUnwrap(bundle.url(forResource: "Lightstack 9", withExtension: "mom", subdirectory: "Lightstack.momd"))
        let v10URL = try XCTUnwrap(bundle.url(forResource: "Lightstack 10", withExtension: "mom", subdirectory: "Lightstack.momd"))
        let v9Model = try XCTUnwrap(NSManagedObjectModel(contentsOf: v9URL))
        let v10Model = try XCTUnwrap(NSManagedObjectModel(contentsOf: v10URL))
        for name in ["CDFoodCollection", "CDFoodCollectionItem"] {
            XCTAssertNil(v9Model.entitiesByName[name])
            XCTAssertNotNil(v10Model.entitiesByName[name])
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("Lightstack.sqlite")
        let foodId = UUID()
        do {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: v9Model)
            let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
            let ctx = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            ctx.persistentStoreCoordinator = coordinator
            try ctx.performAndWait {
                let e = NSEntityDescription.insertNewObject(forEntityName: "CDFood", into: ctx)
                e.setValue(foodId, forKey: "id"); e.setValue(UUID(), forKey: "userId")
                e.setValue("Old food", forKey: "name"); e.setValue(111.0, forKey: "kcal")
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
        let migrated = try XCTUnwrap(ctx.fetch(CDFood.fetchRequest() as NSFetchRequest<CDFood>).first)
        XCTAssertEqual(migrated.id, foodId)
        XCTAssertEqual(migrated.kcal, 111)
        XCTAssertEqual(try ctx.count(for: CDFoodCollection.fetchRequest() as NSFetchRequest<CDFoodCollection>), 0)
    }

    func testCoreDataRoundTripOfCollectionsAndItems() {
        let d = makeDevice()
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let collection = FoodCollection(id: UUID(), userId: user, kind: .recipe, name: "Chili", servingsYield: 4.5,
                                        cookedWeightGrams: 1234, lastUsedAt: stamp, createdAt: stamp, updatedAt: stamp)
        let plain = FoodCollection(id: UUID(), userId: user, kind: .meal, name: "Plain", servingsYield: 1,
                                   cookedWeightGrams: nil, lastUsedAt: nil, createdAt: stamp, updatedAt: stamp)
        let item = FoodCollectionItem(id: UUID(), userId: user, collectionId: collection.id, foodId: UUID(), servings: 2.5,
                                      sortOrder: 3, createdAt: stamp, updatedAt: stamp)
        d.storage.saveFoodCollection(collection)
        d.storage.saveFoodCollection(plain)
        d.storage.saveFoodCollectionItems([item])
        XCTAssertEqual(d.storage.fetchFoodCollection(id: collection.id), collection)
        XCTAssertEqual(d.storage.fetchFoodCollection(id: plain.id), plain)
        XCTAssertNil(d.storage.fetchFoodCollection(id: plain.id)?.cookedWeightGrams)
        XCTAssertEqual(d.storage.fetchFoodCollectionItems(collectionId: collection.id), [item])
        XCTAssertEqual(d.storage.fetchFoodCollections(userId: user, kind: .meal).map(\.id), [plain.id])
        XCTAssertEqual(d.storage.fetchFoodCollections(userId: user).count, 2)
        XCTAssertEqual(d.storage.deleteFoodCollections(ids: [collection.id]), 1)
        XCTAssertTrue(d.storage.fetchAllFoodCollectionItems(userId: user).isEmpty, "items go with their collection")
    }

    // MARK: - Wire format

    func testPayloadsEncodeEveryColumnTheMigrationDefines() throws {
        let stamp = Date()
        let collection = FoodCollection.make(userId: user, kind: .meal, name: "M", now: stamp)
        let item = FoodCollectionItem(id: UUID(), userId: user, collectionId: collection.id, foodId: UUID(), servings: 1,
                                      sortOrder: 0, createdAt: stamp, updatedAt: stamp)
        for forCloud in [true, false] {
            let c = try jsonObject(collection, forCloud: forCloud)
            for column in ["id", "user_id", "kind", "name", "servings_yield", "cooked_weight_g", "last_used_at", "created_at", "updated_at"] {
                XCTAssertNotNil(c[column], "food_collections.\(column) missing (cloud=\(forCloud))")
            }
            XCTAssertTrue(c["cooked_weight_g"] is NSNull, "explicit null so a cleared weight overwrites the old one")
            XCTAssertEqual(c["kind"] as? String, "meal")
            let i = try jsonObject(item, forCloud: forCloud)
            for column in ["id", "user_id", "collection_id", "food_id", "servings", "sort_order", "created_at", "updated_at"] {
                XCTAssertNotNil(i[column], "food_collection_items.\(column) missing (cloud=\(forCloud))")
            }
        }
        XCTAssertEqual(try JSONDecoder().decode(FoodCollection.self, from: JSONEncoder().encode(collection)), collection)
        XCTAssertEqual(try JSONDecoder().decode(FoodCollectionItem.self, from: JSONEncoder().encode(item)), item)
        let derived = RecipeMath.derivedFood(for: FoodCollection.make(userId: user, kind: .recipe, name: "R"), lines: [], existing: nil, now: stamp)
        XCTAssertEqual(try jsonObject(derived, forCloud: true)["source"] as? String, "recipe")
    }

    func testMigrationFileMatchesTheWireFormatAndKeepsEveryConstraintValue() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let sql = try String(contentsOf: root.appendingPathComponent("supabase/migrations/20261108120000_nutrition_kitchen.sql"), encoding: .utf8)
        let schema = try String(contentsOf: root.appendingPathComponent("supabase/supabase_schema.sql"), encoding: .utf8)
        for text in [sql, schema] {
            for column in ["servings_yield", "cooked_weight_g", "collection_id", "food_id", "sort_order", "last_used_at"] {
                XCTAssertTrue(text.contains(column), column)
            }
            XCTAssertTrue(text.contains("'quick','scan','off','ai','recipe'") || text.contains("'quick','scan','off','ai','recipe')"))
            for entity in ["workout", "exercise", "set", "personal_record", "month_plan", "planned_session", "rest_day",
                           "nutrition_target", "food", "food_entry", "meal_slot", "water_entry", "day_note",
                           "food_collection", "food_collection_item"] {
                XCTAssertTrue(text.contains("'\(entity)'"), "tombstone entity \(entity)")
            }
            XCTAssertTrue(text.contains("ENABLE ROW LEVEL SECURITY"))
            XCTAssertTrue(text.contains("GRANT ALL ON public.food_collection_items TO authenticated"))
        }
        XCTAssertTrue(sql.contains("f.user_id = auth.uid()") && sql.contains("c.user_id = auth.uid()"), "cross-user check on items")
        XCTAssertTrue(sql.contains("IF NOT EXISTS") && !sql.contains("DROP TABLE"))
    }

    func testTombstoneEntitiesHaveTheMigrationNames() {
        XCTAssertEqual(TombstoneEntity.foodCollection.rawValue, "food_collection")
        XCTAssertEqual(TombstoneEntity.foodCollectionItem.rawValue, "food_collection_item")
        XCTAssertEqual(FoodSource.recipe.rawValue, "recipe")
        XCTAssertEqual(SyncErrorClassifier.classify(PostgrestError(code: "PGRST205", message: "x"), opType: .upsertFoodCollection), .dependency)
        XCTAssertEqual(SyncErrorClassifier.classify(PostgrestError(code: "42501", message: "rls"), opType: .upsertFoodCollectionItem), .dependency)
        XCTAssertEqual(SyncErrorClassifier.classify(PostgrestError(code: "23514", message: "check"), opType: .insertTombstone), .dependency)
        XCTAssertEqual(SyncErrorClassifier.classify(PostgrestError(code: "23514", message: "check"), opType: .upsertFoodCollection), .permanent)
    }

    // MARK: - Sync

    func testFlushUploadsCollectionsItemsAndDerivedFoodInOrder() async throws {
        let remote = FakeRemote()
        let d = makeDevice(remote: remote)
        let egg = addFood(d, "Egg", nutrients(70, 6, 0, 5))
        let meal = try XCTUnwrap(d.repo.saveMeal(userId: user, name: "M", items: [PlateItem(food: egg, servings: 2)]))
        let recipe = try XCTUnwrap(d.repo.saveRecipe(userId: user, name: "R", ingredients: [PlateItem(food: egg, servings: 2)], servingsYield: 2))
        let types = await d.queuedTypes()
        XCTAssertTrue(types.contains(.upsertFoodCollection) && types.contains(.upsertFoodCollectionItem))
        await d.stack.flushAll()
        XCTAssertEqual(remote.foodCollections.count, 2)
        XCTAssertEqual(remote.foodCollectionItems.count, 2)
        XCTAssertEqual(remote.foodCollections[meal.id]?.kind, .meal)
        XCTAssertEqual(remote.foods[recipe.collection.derivedFoodId]?.source, .recipe)
        let order = remote.calls
        let foodIndex = order.firstIndex { $0.hasPrefix("upsertFood:") } ?? -1
        let collectionIndex = order.firstIndex { $0.hasPrefix("upsertFoodCollection:") } ?? -1
        let itemIndex = order.firstIndex { $0.hasPrefix("upsertFoodCollectionItem:") } ?? -1
        XCTAssertTrue(foodIndex >= 0 && foodIndex < collectionIndex && collectionIndex < itemIndex, "foods, then collections, then items")
        let failed = await d.stack.queue.failedOperations()
        XCTAssertTrue(failed.isEmpty)
    }

    func testMissingTablesKeepTheWritesQueued() async throws {
        let remote = FakeRemote()
        remote.script = { type, _ in
            (type == .upsertFoodCollection || type == .upsertFoodCollectionItem)
                ? PostgrestError(code: "PGRST205", message: "Could not find the table 'public.food_collections'") : nil
        }
        let d = makeDevice(remote: remote)
        let egg = addFood(d, "Egg", nutrients(70, 6, 0, 5))
        _ = d.repo.saveMeal(userId: user, name: "M", items: [PlateItem(food: egg)])
        await d.stack.flushAll()
        let failed = await d.stack.queue.failedOperations()
        XCTAssertTrue(failed.isEmpty)
        let queued = await d.stack.queue.queuedOperations().map(\.type)
        XCTAssertTrue(queued.contains(.upsertFoodCollection))
    }

    func testDeleteMealQueuesDeleteAndTombstone() async throws {
        let remote = FakeRemote()
        let d = makeDevice(remote: remote)
        let egg = addFood(d, "Egg", nutrients(70, 6, 0, 5))
        let meal = try XCTUnwrap(d.repo.saveMeal(userId: user, name: "M", items: [PlateItem(food: egg)]))
        d.repo.deleteMeal(id: meal.id, userId: user)
        await d.stack.flushAll()
        XCTAssertNil(remote.foodCollections[meal.id])
        XCTAssertTrue(remote.foodCollectionItems.isEmpty)
        XCTAssertTrue(remote.tombstones.contains("food_collection:\(meal.id.uuidString)"))
    }

    // MARK: - Restore

    func testFreshInstallRestoresFoodsMealsRecipesAndItems() async throws {
        let remote = FakeRemote()
        let a = makeDevice(remote: remote)
        let egg = addFood(a, "Egg", nutrients(70, 6, 0, 5))
        let oats = addFood(a, "Oats", nutrients(150, 5, 27, 3))
        let meal = try XCTUnwrap(a.repo.saveMeal(userId: user, name: "Usual breakfast", items: [PlateItem(food: egg, servings: 3), PlateItem(food: oats)]))
        let recipe = try XCTUnwrap(a.repo.saveRecipe(userId: user, name: "Bowl", ingredients: [PlateItem(food: egg), PlateItem(food: oats)],
                                                     servingsYield: 2, cookedWeightGrams: 400))
        await a.stack.flushAll()

        let b = makeDevice(remote: remote)
        _ = try await b.service.restoreAll(userId: user, assumeFreshInstall: true)
        let restoredMeal = try XCTUnwrap(b.repo.kitchenCollection(id: meal.id))
        XCTAssertEqual(restoredMeal.lines.map(\.servings), [3, 1])
        XCTAssertEqual(restoredMeal.name, "Usual breakfast")
        let restoredRecipe = try XCTUnwrap(b.repo.kitchenCollection(id: recipe.id))
        XCTAssertEqual(restoredRecipe.collection.cookedWeightGrams, 400)
        XCTAssertEqual(restoredRecipe.items.count, 2)
        XCTAssertEqual(b.repo.recipeFood(recipeId: recipe.id)?.servingGrams, 200)
        XCTAssertEqual(b.repo.recipeFood(recipeId: recipe.id)?.nutrients.kcal ?? 0, 110, accuracy: 0.0001)
        XCTAssertTrue(remote.readLog.contains("fetchFoodCollections") && remote.readLog.contains("fetchFoodCollectionItems"))
    }

    func testRestoreAppliesTombstonesForCollectionsItemsAndDeletedFoods() async throws {
        let remote = FakeRemote()
        let d = makeDevice(remote: remote)
        let egg = addFood(d, "Egg", nutrients(70, 6, 0, 5))
        let oats = addFood(d, "Oats", nutrients(150, 5, 27, 3))
        let gone = try XCTUnwrap(d.repo.saveMeal(userId: user, name: "Gone", items: [PlateItem(food: egg)]))
        let kept = try XCTUnwrap(d.repo.saveMeal(userId: user, name: "Kept", items: [PlateItem(food: egg), PlateItem(food: oats)]))
        remote.seedTombstone(.foodCollection, gone.id)
        remote.seedTombstone(.food, oats.id)
        _ = try await d.service.restoreAll(userId: user, assumeFreshInstall: true)
        XCTAssertNil(d.storage.fetchFoodCollection(id: gone.id))
        XCTAssertNil(d.storage.fetchFood(id: oats.id))
        XCTAssertEqual(d.repo.kitchenCollection(id: kept.id)?.items.map(\.foodId), [egg.id], "the deleted food left the meal")
    }

    func testRepairUploadsCollectionsMissingFromTheCloud() async throws {
        let remote = FakeRemote()
        let d = makeDevice(remote: remote)
        let egg = addFood(d, "Egg", nutrients(70, 6, 0, 5))
        await d.stack.flushAll()
        let stamp = Date()
        let collection = FoodCollection.make(userId: user, kind: .meal, name: "Lost write", now: stamp)
        d.storage.saveFoodCollection(collection)           // no queue: like a lost write
        d.storage.saveFoodCollectionItems([FoodCollectionItem(id: UUID(), userId: user, collectionId: collection.id, foodId: egg.id,
                                                              servings: 1, sortOrder: 0, createdAt: stamp, updatedAt: stamp)])
        let summary = try await d.service.restoreAll(userId: user, assumeFreshInstall: true)
        XCTAssertGreaterThanOrEqual(summary.repairedNutrition, 2)
        await d.stack.flushAll()
        XCTAssertNotNil(remote.foodCollections[collection.id])
        XCTAssertEqual(remote.foodCollectionItems.count, 1)
    }
}
