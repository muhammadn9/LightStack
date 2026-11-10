import Foundation

/// Kitchen: saved meals, recipes and serving-unit helpers for the UI.
extension NutritionViewModel {

    // MARK: - Listing and search

    /// Saved meals and/or recipes (all when `kind` is nil), by name. A query matches the name or an item/ingredient name.
    func kitchenItems(kind: FoodCollectionKind? = nil, query: String = "") -> [KitchenCollection] {
        guard let userId else { return [] }
        return repository.kitchenCollections(userId: userId, kind: kind, query: query)
    }

    func savedMeals(query: String = "") -> [KitchenCollection] { kitchenItems(kind: .meal, query: query) }

    func recipes(query: String = "") -> [KitchenCollection] { kitchenItems(kind: .recipe, query: query) }

    func kitchenItem(id: UUID) -> KitchenCollection? { repository.kitchenCollection(id: id) }

    // MARK: - Saved meals

    /// Creates a saved meal, or replaces an existing one's name and items when `id` is given.
    @discardableResult
    func saveMeal(id: UUID? = nil, name: String, items: [PlateItem]) -> KitchenCollection? {
        guard let userId else { return nil }
        let saved = repository.saveMeal(userId: userId, id: id, name: name, items: items)
        kitchenVersion += 1
        foodsVersion += 1
        return saved
    }

    /// "Save this journal meal as a meal": one item per entry with that entry's servings.
    @discardableResult
    func saveMeal(name: String, from entries: [FoodEntry]) -> KitchenCollection? {
        guard let userId else { return nil }
        let saved = repository.saveMeal(userId: userId, name: name, from: entries)
        kitchenVersion += 1
        foodsVersion += 1
        return saved
    }

    /// Saves a plate (multi-select list of foods and servings) as a meal.
    @discardableResult
    func saveMeal(name: String, from plate: [PlateItem]) -> KitchenCollection? {
        guard let userId else { return nil }
        let saved = repository.saveMeal(userId: userId, name: name, from: plate)
        kitchenVersion += 1
        return saved
    }

    /// Saves one of the selected day's journal meals (its entries) as a saved meal.
    @discardableResult
    func saveMeal(name: String, fromJournalMeal slotId: UUID) -> KitchenCollection? {
        guard let meal = summary?.meal(for: slotId) else { return nil }
        return saveMeal(name: name, from: meal.entries)
    }

    func deleteMeal(_ meal: KitchenCollection) {
        guard let userId else { return }
        repository.deleteMeal(id: meal.id, userId: userId)
        kitchenVersion += 1
    }

    /// Logs a saved meal into `mealSlotId` on the selected day: one entry per item, each with its servings.
    @discardableResult
    func logMeal(_ meal: KitchenCollection, mealSlotId: UUID?, servingsMultiplier: Double = 1) -> [FoodEntry] {
        guard let userId else { return [] }
        let entries = repository.logMeal(id: meal.id, userId: userId, mealSlotId: mealSlotId, on: date,
                                         servingsMultiplier: servingsMultiplier)
        foodsVersion += 1
        kitchenVersion += 1
        reload()
        return entries
    }

    // MARK: - Recipes

    /// Creates a recipe, or replaces an existing one when `id` is given. `servingsYield` must be > 0.
    /// Returns nil for a blank name, a bad yield or no usable ingredient.
    @discardableResult
    func saveRecipe(id: UUID? = nil, name: String, ingredients: [PlateItem], servingsYield: Double,
                    cookedWeightGrams: Double? = nil) -> KitchenCollection? {
        guard let userId else { return nil }
        let saved = repository.saveRecipe(userId: userId, id: id, name: name, ingredients: ingredients,
                                          servingsYield: servingsYield, cookedWeightGrams: cookedWeightGrams)
        foodsVersion += 1
        kitchenVersion += 1
        return saved
    }

    func deleteRecipe(_ recipe: KitchenCollection) {
        guard let userId else { return }
        repository.deleteRecipe(id: recipe.id, userId: userId)
        foodsVersion += 1
        kitchenVersion += 1
        reload()
    }

    /// Logs `servings` of a recipe on the selected day, like any saved food.
    @discardableResult
    func logRecipe(_ recipe: KitchenCollection, servings: Double, mealSlotId: UUID? = nil) -> FoodEntry? {
        guard let userId else { return nil }
        let entry = repository.logRecipe(id: recipe.id, userId: userId, servings: servings, on: date, mealSlotId: mealSlotId)
        foodsVersion += 1
        kitchenVersion += 1
        reload()
        return entry
    }

    /// False when the food would make the recipe contain itself (its own derived food, or a recipe that uses it).
    /// `recipe` nil = a recipe that is not saved yet (always allowed).
    func canUseAsIngredient(_ food: NutritionFood, in recipe: KitchenCollection?) -> Bool {
        guard let userId else { return false }
        return repository.canUseAsIngredient(foodId: food.id, inRecipe: recipe?.id, userId: userId)
    }

    /// Live preview while editing: per-serving values and serving weight. Pure; nothing is saved.
    static func recipePreview(ingredients: [PlateItem], servingsYield: Double, cookedWeightGrams: Double?)
        -> (perServing: NutrientValues, servingGrams: Double?) {
        (RecipeMath.perServing(lines: ingredients, servingsYield: servingsYield),
         RecipeMath.servingGrams(cookedWeightGrams: cookedWeightGrams, servingsYield: servingsYield))
    }

    // MARK: - Serving units

    /// The user's favourite serving units, in their order.
    var favoriteServingUnits: [NutritionUnit] { ServingUnitPreferences.favorites() }

    func setFavoriteServingUnits(_ units: [NutritionUnit]) {
        ServingUnitPreferences.setFavorites(units)
        objectWillChange.send()
    }

    /// The units this food can be logged in, favourites first.
    func servingUnits(for food: NutritionFood) -> [NutritionUnit] {
        ServingUnitConverter.ordered(ServingUnitConverter.availableUnits(for: food), favorites: favoriteServingUnits)
    }

    /// Servings that `amount` of `unit` comes to (nil when the food cannot be measured in that unit).
    func servings(amount: Double, unit: NutritionUnit, for food: NutritionFood) -> Double? {
        ServingUnitConverter.servings(amount: amount, unit: unit, for: food)
    }

    /// "150 g" for `servings` servings of the food shown in `unit`.
    func unitLabel(servings: Double, in unit: NutritionUnit, for food: NutritionFood) -> String {
        ServingUnitConverter.label(servings: servings, in: unit, for: food)
    }

    /// Logs "amount + unit" of a saved food. Returns false when the unit does not apply to the food.
    @discardableResult
    func log(_ food: NutritionFood, amount: Double, unit: NutritionUnit, mealSlotId: UUID? = nil) -> Bool {
        logMeasured(food, amount: amount, unit: unit, mealSlotId: mealSlotId)
    }
}
