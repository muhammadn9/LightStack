import Foundation

/// Kitchen data: saved meals (a named group of foods) and recipes (ingredients that make one derived food).
/// Same rules as the rest of the repository: local save first, then the cloud write goes through the queue.
///
/// A recipe owns a derived `NutritionFood` (source `.recipe`, id derived from the recipe id) whose per-serving
/// values are recomputed whenever the recipe or one of its ingredients changes. Logging a recipe is therefore
/// ordinary food logging, and food search finds recipes. Logged entries keep their own snapshot.
extension NutritionRepository {

    // MARK: - Loading

    private func load(_ collection: FoodCollection) -> KitchenCollection {
        let items = localStorage.fetchFoodCollectionItems(collectionId: collection.id)
        var foods: [UUID: NutritionFood] = [:]
        for item in items where foods[item.foodId] == nil {
            if let food = localStorage.fetchFood(id: item.foodId) { foods[item.foodId] = food }
        }
        return KitchenCollection(collection: collection, items: items, foods: foods)
    }

    func kitchenCollection(id: UUID) -> KitchenCollection? {
        localStorage.fetchFoodCollection(id: id).map(load)
    }

    /// Saved meals and/or recipes by name. A query matches the name or any ingredient/item name.
    func kitchenCollections(userId: UUID, kind: FoodCollectionKind? = nil, query: String = "") -> [KitchenCollection] {
        let all = localStorage.fetchFoodCollections(userId: userId, kind: kind).map(load)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return all }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return all.filter { loaded in
            loaded.name.range(of: needle, options: options) != nil
                || loaded.foods.values.contains { $0.name.range(of: needle, options: options) != nil }
        }
    }

    func savedMeals(userId: UUID, query: String = "") -> [KitchenCollection] {
        kitchenCollections(userId: userId, kind: .meal, query: query)
    }

    func recipes(userId: UUID, query: String = "") -> [KitchenCollection] {
        kitchenCollections(userId: userId, kind: .recipe, query: query)
    }

    /// The food a recipe owns (what gets logged).
    func recipeFood(recipeId: UUID) -> NutritionFood? {
        guard let collection = localStorage.fetchFoodCollection(id: recipeId), collection.kind == .recipe else { return nil }
        return localStorage.fetchFood(id: collection.derivedFoodId)
    }

    // MARK: - Queue helpers

    private func queue(_ collection: FoodCollection) {
        offlineQueueManager.submit(.upsertFoodCollection, payload: collection, recordKey: collection.id.uuidString)
    }

    private func queue(_ item: FoodCollectionItem) {
        offlineQueueManager.submit(.upsertFoodCollectionItem, payload: item, recordKey: item.id.uuidString)
    }

    private func queueDeleted(items: [FoodCollectionItem]) {
        for item in items {
            offlineQueueManager.submit(.deleteFoodCollectionItem, payload: DeleteNutritionRecordPayload(id: item.id))
        }
        offlineQueueManager.submitTombstones(.foodCollectionItem, ids: items.map(\.id))
    }

    // MARK: - Items

    /// Makes the collection hold exactly `lines`, in order. Existing item rows are reused (matched by food) so a
    /// small edit uploads only what changed; rows no longer wanted are deleted with tombstones.
    private func replaceItems(of collection: FoodCollection, with lines: [PlateItem], stamp: Date) {
        var pool = localStorage.fetchFoodCollectionItems(collectionId: collection.id)
        var upserts: [FoodCollectionItem] = []
        for (index, line) in lines.enumerated() {
            if let match = pool.firstIndex(where: { $0.foodId == line.food.id }) {
                var item = pool.remove(at: match)
                if item.servings != line.servings || item.sortOrder != index {
                    item.servings = line.servings
                    item.sortOrder = index
                    item.updatedAt = stamp
                    upserts.append(item)
                }
            } else {
                upserts.append(FoodCollectionItem(id: UUID(), userId: collection.userId, collectionId: collection.id,
                                                  foodId: line.food.id, servings: line.servings, sortOrder: index,
                                                  createdAt: stamp, updatedAt: stamp))
            }
        }
        localStorage.saveFoodCollectionItems(upserts)
        localStorage.deleteFoodCollectionItems(ids: Set(pool.map(\.id)))
        upserts.forEach { queue($0) }
        queueDeleted(items: pool)
    }

    /// Lines worth keeping: a positive amount of a food that exists on this device and belongs to the user.
    private func usableLines(_ lines: [PlateItem], userId: UUID) -> [PlateItem] {
        lines.compactMap { line in
            guard line.servings > 0, line.servings.isFinite,
                  let stored = localStorage.fetchFood(id: line.food.id), stored.userId == userId else { return nil }
            return PlateItem(food: stored, servings: line.servings)
        }
    }

    // MARK: - Saved meals

    /// Creates a saved meal, or (with `id`) replaces the name and items of an existing one.
    /// Returns nil for a blank name or when no item is usable.
    @discardableResult
    func saveMeal(userId: UUID, id: UUID? = nil, name: String, items: [PlateItem]) -> KitchenCollection? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = usableLines(items, userId: userId)
        guard !trimmed.isEmpty, !lines.isEmpty else { return nil }
        let stamp = now()
        var collection: FoodCollection
        if let id {
            guard let existing = localStorage.fetchFoodCollection(id: id), existing.userId == userId, existing.kind == .meal else { return nil }
            collection = existing
            collection.name = trimmed
            collection.updatedAt = stamp
        } else {
            collection = FoodCollection.make(userId: userId, kind: .meal, name: trimmed, now: stamp)
        }
        localStorage.saveFoodCollection(collection)
        queue(collection)
        replaceItems(of: collection, with: lines, stamp: stamp)
        return kitchenCollection(id: collection.id)
    }

    /// "Save this journal meal as a meal": one item per entry with that entry's servings. An entry whose food is
    /// still saved points at that food; a quick add (or one whose food was deleted) first becomes a saved food
    /// from the entry's own snapshot.
    @discardableResult
    func saveMeal(userId: UUID, name: String, from entries: [FoodEntry]) -> KitchenCollection? {
        var lines: [PlateItem] = []
        for entry in entries where entry.userId == userId && entry.servings > 0 {
            if let foodId = entry.foodId, let food = localStorage.fetchFood(id: foodId) {
                lines.append(PlateItem(food: food, servings: entry.servings))
            } else {
                let snapshot = NutritionFood.make(userId: userId, name: entry.name, servingLabel: entry.servingLabel,
                                                  nutrients: entry.perServing, source: .quick, now: now())
                lines.append(PlateItem(food: saveFood(snapshot), servings: entry.servings))
            }
        }
        return saveMeal(userId: userId, name: name, items: lines)
    }

    /// "Save this plate as a meal".
    @discardableResult
    func saveMeal(userId: UUID, name: String, from plate: [PlateItem]) -> KitchenCollection? {
        saveMeal(userId: userId, name: name, items: plate)
    }

    func deleteMeal(id: UUID, userId: UUID) {
        guard let collection = localStorage.fetchFoodCollection(id: id), collection.userId == userId, collection.kind == .meal else { return }
        removeCollection(collection)
    }

    /// Logs a saved meal: ONE entry per item (that item's servings times `servingsMultiplier`), linked to its food,
    /// in the chosen meal and day. Returns the new entries in item order.
    @discardableResult
    func logMeal(id: UUID, userId: UUID, mealSlotId: UUID?, on date: Date, servingsMultiplier: Double = 1) -> [FoodEntry] {
        guard var collection = localStorage.fetchFoodCollection(id: id), collection.userId == userId, collection.kind == .meal else { return [] }
        let multiplier = max(0, servingsMultiplier)
        let plate = load(collection).lines
            .map { PlateItem(food: $0.food, servings: $0.servings * multiplier) }
            .filter { $0.servings > 0 }
        let entries = logFoods(plate, mealSlotId: mealSlotId, on: date)
        collection.lastUsedAt = now()
        localStorage.saveFoodCollection(collection)
        queue(collection)
        return entries
    }

    // MARK: - Recipes

    /// Creates a recipe, or (with `id`) replaces an existing one's name, ingredients, yield and cooked weight.
    /// `servingsYield` must be > 0; a non-positive cooked weight is treated as "not weighed". An ingredient that
    /// would make the recipe contain itself (its own derived food, or a recipe that already uses it) is left out.
    /// Returns nil for a blank name, a bad yield or when no ingredient is usable.
    @discardableResult
    func saveRecipe(userId: UUID, id: UUID? = nil, name: String, ingredients: [PlateItem], servingsYield: Double,
                    cookedWeightGrams: Double? = nil) -> KitchenCollection? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, servingsYield > 0, servingsYield.isFinite else { return nil }
        let stamp = now()
        let cooked = cookedWeightGrams.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        var collection: FoodCollection
        if let id {
            guard let existing = localStorage.fetchFoodCollection(id: id), existing.userId == userId, existing.kind == .recipe else { return nil }
            collection = existing
        } else {
            collection = FoodCollection.make(userId: userId, kind: .recipe, name: trimmed, servingsYield: servingsYield, now: stamp)
        }
        let lines = usableLines(ingredients, userId: userId)
            .filter { canUseAsIngredient(foodId: $0.food.id, inRecipe: collection.id, userId: userId) }
        guard !lines.isEmpty else { return nil }
        collection.name = trimmed
        collection.servingsYield = servingsYield
        collection.cookedWeightGrams = cooked
        collection.updatedAt = stamp
        localStorage.saveFoodCollection(collection)
        queue(collection)
        replaceItems(of: collection, with: lines, stamp: stamp)
        var visited = Set<UUID>()
        recompute(recipeId: collection.id, visited: &visited)
        return kitchenCollection(id: collection.id)
    }

    /// Deletes the recipe, its ingredients and its derived food. Entries already logged keep their snapshot.
    func deleteRecipe(id: UUID, userId: UUID) {
        guard let collection = localStorage.fetchFoodCollection(id: id), collection.userId == userId, collection.kind == .recipe else { return }
        removeCollection(collection)
        deleteFood(id: collection.derivedFoodId, userId: userId)
    }

    /// Logs `servings` of a recipe like any food (one entry, snapshot of the derived food).
    @discardableResult
    func logRecipe(id: UUID, userId: UUID, servings: Double, on date: Date, mealSlotId: UUID? = nil) -> FoodEntry? {
        guard let collection = localStorage.fetchFoodCollection(id: id), collection.userId == userId, collection.kind == .recipe else { return nil }
        var visited = Set<UUID>()
        let food = localStorage.fetchFood(id: collection.derivedFoodId) ?? recompute(recipeId: id, visited: &visited)
        guard let food else { return nil }
        return logFood(food, servings: servings, on: date, mealSlotId: mealSlotId)
    }

    /// Whether a food may be an ingredient of the recipe: never the recipe's own derived food, and never a recipe
    /// that (directly or through other recipes) already uses this one. `recipeId` nil = a recipe not saved yet.
    func canUseAsIngredient(foodId: UUID, inRecipe recipeId: UUID?, userId: UUID) -> Bool {
        guard let recipeId else { return true }
        let own = FoodCollection.derivedFoodId(userId: userId, collectionId: recipeId)
        if foodId == own { return false }
        let byDerivedId = Dictionary(
            localStorage.fetchFoodCollections(userId: userId, kind: .recipe).map { ($0.derivedFoodId, $0.id) },
            uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        var stack = [foodId]
        while let current = stack.popLast() {
            guard seen.insert(current).inserted else { continue }
            if current == own { return false }
            if let nested = byDerivedId[current] {
                stack.append(contentsOf: localStorage.fetchFoodCollectionItems(collectionId: nested).map(\.foodId))
            }
        }
        return true
    }

    // MARK: - Recompute

    /// Rebuilds a recipe's derived food from its ingredients (dropping ingredients whose food is gone) and saves it
    /// when anything changed, then does the same for recipes that use this one. `visited` stops cycles.
    @discardableResult
    func recompute(recipeId: UUID, visited: inout Set<UUID>) -> NutritionFood? {
        guard visited.insert(recipeId).inserted,
              let collection = localStorage.fetchFoodCollection(id: recipeId), collection.kind == .recipe else { return nil }
        let stamp = now()
        let items = localStorage.fetchFoodCollectionItems(collectionId: recipeId)
        let ownId = collection.derivedFoodId
        var kept: [FoodCollectionItem] = []
        var dropped: [FoodCollectionItem] = []
        var foods: [UUID: NutritionFood] = [:]
        for item in items {
            if item.foodId != ownId, let food = localStorage.fetchFood(id: item.foodId) {
                foods[item.foodId] = food
                kept.append(item)
            } else {
                dropped.append(item)
            }
        }
        if !dropped.isEmpty {
            localStorage.deleteFoodCollectionItems(ids: Set(dropped.map(\.id)))
            queueDeleted(items: dropped)
        }
        let lines = kept.sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { item in foods[item.foodId].map { PlateItem(food: $0, servings: item.servings) } }
        let existing = localStorage.fetchFood(id: ownId)
        var derived = RecipeMath.derivedFood(for: collection, lines: lines, existing: existing, now: stamp)
        var result = derived
        if let existing {
            derived.updatedAt = existing.updatedAt
            if derived == existing { result = existing } else { derived.updatedAt = stamp; result = derived }
        }
        if existing == nil || result != existing {
            localStorage.saveFood(result)
            offlineQueueManager.submit(.upsertFood, payload: result, recordKey: result.id.uuidString)
            // Recipes that use this recipe as an ingredient.
            let parents = Set(localStorage.fetchFoodCollectionItems(foodIds: [ownId], userId: collection.userId).map(\.collectionId))
            for parent in parents { recompute(recipeId: parent, visited: &visited) }
        }
        return result
    }

    /// Recomputes every recipe that has one of these foods as an ingredient.
    func recomputeRecipes(usingFoodIds foodIds: Set<UUID>, userId: UUID) {
        let collectionIds = Set(localStorage.fetchFoodCollectionItems(foodIds: foodIds, userId: userId).map(\.collectionId))
        var visited = Set<UUID>()
        for id in collectionIds { recompute(recipeId: id, visited: &visited) }
    }

    // MARK: - Removal

    /// Deletes a collection and its items locally and in the cloud (the server cascades the items).
    func removeCollection(_ collection: FoodCollection) {
        localStorage.deleteFoodCollections(ids: [collection.id])
        offlineQueueManager.submit(.deleteFoodCollection, payload: DeleteNutritionRecordPayload(id: collection.id))
        offlineQueueManager.submitTombstones(.foodCollection, ids: [collection.id])
    }

    /// Called when a saved food is deleted: if it was a recipe's derived food, the recipe goes too; every item that
    /// pointed at it is dropped and the recipes that used it are recomputed.
    func foodWillBeDeleted(_ food: NutritionFood, userId: UUID) -> Set<UUID> {
        if food.source == .recipe,
           let recipe = localStorage.fetchFoodCollections(userId: userId, kind: .recipe).first(where: { $0.derivedFoodId == food.id }) {
            removeCollection(recipe)
        }
        let removed = localStorage.deleteFoodCollectionItems(foodIds: [food.id], userId: userId)
        queueDeleted(items: removed)
        return Set(removed.map(\.collectionId))
    }

    /// Second half of a food delete: recompute the recipes that lost an ingredient.
    func recomputeAfterFoodDelete(affectedCollectionIds: Set<UUID>) {
        var visited = Set<UUID>()
        for id in affectedCollectionIds { recompute(recipeId: id, visited: &visited) }
    }
}
