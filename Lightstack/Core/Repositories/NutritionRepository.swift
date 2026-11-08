import Foundation

/// Nutrition targets, foods and the daily diary: local save first, then the cloud write goes through
/// the offline queue. Daily totals are always computed from entries, never stored.
final class NutritionRepository {

    let localStorage: LocalStorageService
    let offlineQueueManager: OfflineQueueManager
    let now: () -> Date

    init(localStorage: LocalStorageService, offlineQueueManager: OfflineQueueManager, now: @escaping () -> Date = { Date() }) {
        self.localStorage = localStorage
        self.offlineQueueManager = offlineQueueManager
        self.now = now
    }

    // MARK: - Queue helpers

    private func queue(_ target: NutritionTarget) {
        offlineQueueManager.submit(.upsertNutritionTarget, payload: target, recordKey: target.id.uuidString)
    }

    private func queue(_ food: NutritionFood) {
        offlineQueueManager.submit(.upsertFood, payload: food, recordKey: food.id.uuidString)
    }

    private func queue(_ entry: FoodEntry) {
        offlineQueueManager.submit(.upsertFoodEntry, payload: entry, recordKey: entry.id.uuidString)
    }

    // MARK: - Targets

    /// Sets the target that applies from `effectiveDate`. Calories derive from the macros (4/4/9) unless
    /// `kcalOverride` is given. A second save for the same effective day updates that target in place.
    @discardableResult
    func setTarget(userId: UUID, effectiveDate: Date, protein: Double, carbs: Double, fat: Double,
                   kcalOverride: Double? = nil) -> NutritionTarget {
        let day = effectiveDate.startOfDay
        let stamp = now()
        var target: NutritionTarget
        if var existing = localStorage.fetchNutritionTargets(userId: userId).first(where: { $0.effectiveDate.startOfDay == day }) {
            existing.protein = max(0, protein)
            existing.carbs = max(0, carbs)
            existing.fat = max(0, fat)
            existing.kcalOverridden = kcalOverride != nil
            existing.kcal = max(0, kcalOverride ?? NutritionMath.derivedKcal(protein: existing.protein, carbs: existing.carbs, fat: existing.fat))
            existing.updatedAt = stamp
            target = existing
        } else {
            target = NutritionTarget.make(userId: userId, effectiveDate: day, protein: max(0, protein), carbs: max(0, carbs),
                                          fat: max(0, fat), kcalOverride: kcalOverride.map { max(0, $0) }, now: stamp)
        }
        localStorage.saveNutritionTarget(target)
        queue(target)
        return target
    }

    func targets(userId: UUID) -> [NutritionTarget] {
        localStorage.fetchNutritionTargets(userId: userId)
    }

    /// The target in force on that day: the weekday plan if one covers it, else the latest effective-date
    /// target on or before it.
    func target(userId: UUID, on date: Date) -> NutritionTarget? {
        resolvedTarget(userId: userId, on: date)
    }

    func deleteTarget(id: UUID, userId: UUID) {
        guard localStorage.fetchNutritionTargets(userId: userId).contains(where: { $0.id == id }) else { return }
        localStorage.deleteNutritionTargets(ids: [id])
        offlineQueueManager.submit(.deleteNutritionTarget, payload: DeleteNutritionRecordPayload(id: id))
        offlineQueueManager.submitTombstones(.nutritionTarget, ids: [id])
    }

    // MARK: - Foods

    /// Creates or updates a saved food (upsert by id). Logged entries keep their own snapshot.
    @discardableResult
    func saveFood(_ food: NutritionFood) -> NutritionFood {
        var saved = food
        saved.updatedAt = now()
        localStorage.saveFood(saved)
        queue(saved)
        return saved
    }

    func food(id: UUID) -> NutritionFood? {
        localStorage.fetchFood(id: id)
    }

    /// Deletes a saved food. Entries already logged from it stay (snapshot) and lose the link.
    func deleteFood(id: UUID, userId: UUID) {
        guard let existing = localStorage.fetchFood(id: id), existing.userId == userId else { return }
        let detached = localStorage.detachFoodEntries(foodIds: [id], userId: userId)
        localStorage.deleteFoods(ids: [id])
        detached.forEach { queue($0) }
        offlineQueueManager.submit(.deleteFood, payload: DeleteNutritionRecordPayload(id: id))
        offlineQueueManager.submitTombstones(.food, ids: [id])
    }

    @discardableResult
    func setFavorite(foodId: UUID, isFavorite: Bool) -> NutritionFood? {
        guard var food = localStorage.fetchFood(id: foodId) else { return nil }
        food.isFavorite = isFavorite
        return saveFood(food)
    }

    func favoriteFoods(userId: UUID) -> [NutritionFood] {
        localStorage.fetchFoods(userId: userId).filter(\.isFavorite)
    }

    /// Most recently used foods first (foods never logged are not "recent").
    func recentFoods(userId: UUID, limit: Int = 20) -> [NutritionFood] {
        Array(
            localStorage.fetchFoods(userId: userId)
                .filter { $0.lastUsedAt != nil }
                .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
                .prefix(max(0, limit))
        )
    }

    /// Local search on name and brand (case and diacritic insensitive); blank query returns everything by name.
    func searchFoods(userId: UUID, query: String, limit: Int = 50) -> [NutritionFood] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = localStorage.fetchFoods(userId: userId)
        guard !needle.isEmpty else { return Array(all.prefix(max(0, limit))) }
        let matches = all.filter {
            $0.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || ($0.brand?.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
        }
        return Array(matches.prefix(max(0, limit)))
    }

    // MARK: - Branded foods (Open Food Facts)

    /// The user's own saved food with this barcode, if any. Checked before any network lookup.
    func food(barcode: String, userId: UUID) -> NutritionFood? {
        guard let code = Barcode.normalized(barcode) else { return nil }
        return localStorage.fetchFood(barcode: code, userId: userId)
    }

    /// Turns an Open Food Facts product into a saved food (source Open Food Facts, with its barcode).
    /// Saving the same barcode again returns the food already saved instead of creating a duplicate.
    @discardableResult
    func saveBrandedFood(_ product: OpenFoodFactsProduct, userId: UUID) -> NutritionFood {
        if let existing = food(barcode: product.barcode, userId: userId) { return existing }
        let food = NutritionFood.make(
            userId: userId, name: product.name, brand: product.brand, servingLabel: product.servingLabel,
            servingUnit: product.servingUnit, servingAmount: product.servingAmount, servingGrams: product.servingGrams,
            nutrients: product.nutrients, source: .openFoodFacts, barcode: product.barcode, now: now()
        )
        return saveFood(food)
    }

    // MARK: - AI estimates

    /// Saves an AI-estimated item as a food (source AI, with its sources and confidence) so it shows in
    /// Recent/Saved and can be reused. The saved food holds the FULL item; the diary entry carries `servings`.
    /// A food already saved with the same name, venue and values is reused instead of duplicated.
    @discardableResult
    func saveAIFood(_ item: AIMealItem, userId: UUID) -> NutritionFood {
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let brand = item.venue?.trimmingCharacters(in: .whitespacesAndNewlines)
        func same(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.05 }
        let n = item.fullItem
        if let existing = localStorage.fetchFoods(userId: userId).first(where: {
            $0.source == .ai
                && $0.name.caseInsensitiveCompare(name) == .orderedSame
                && ($0.brand ?? "").caseInsensitiveCompare(brand ?? "") == .orderedSame
                && same($0.nutrients.kcal, n.kcal) && same($0.nutrients.protein, n.protein)
                && same($0.nutrients.carbs, n.carbs) && same($0.nutrients.fat, n.fat)
        }) {
            return existing
        }
        let food = NutritionFood.make(
            userId: userId, name: name.isEmpty ? "AI estimate" : name, brand: (brand?.isEmpty ?? true) ? nil : brand,
            servingLabel: item.servingLabel, servingUnit: "serving", servingAmount: 1, servingGrams: nil,
            nutrients: n, source: .ai, aiSources: item.sources, aiConfidence: item.confidence, now: now()
        )
        return saveFood(food)
    }

    /// Saves each item as a food (see `saveAIFood`) and returns them as plate items with the item's servings.
    func plateItems(for items: [AIMealItem], userId: UUID) -> [PlateItem] {
        items.map { PlateItem(food: saveAIFood($0, userId: userId), servings: max(0, $0.servings)) }
    }

    /// Saves and logs AI items into a meal on a day with their servings (half a bowl = 0.5 of the saved bowl).
    @discardableResult
    func logAIItems(_ items: [AIMealItem], userId: UUID, mealSlotId: UUID?, on date: Date) -> [FoodEntry] {
        logFoods(plateItems(for: items.filter { $0.servings > 0 }, userId: userId), mealSlotId: mealSlotId, on: date)
    }

    // MARK: - Entries

    /// Logs `servings` of a saved food on a local day. The entry snapshots the food's values.
    @discardableResult
    func logFood(_ food: NutritionFood, servings: Double, on date: Date, source: EntrySource? = nil,
                 mealSlotId: UUID? = nil) -> FoodEntry {
        let stamp = now()
        let entry = FoodEntry.make(from: food, servings: max(0, servings), on: date,
                                   source: source ?? (food.source == .scan ? .scan : .saved),
                                   mealSlotId: mealSlotId, now: stamp)
        queueMealSlotIfNeeded(mealSlotId)
        localStorage.saveFoodEntry(entry)
        queue(entry)
        if var stored = localStorage.fetchFood(id: food.id) {
            stored.lastUsedAt = stamp
            stored.updatedAt = stamp
            localStorage.saveFood(stored)
            queue(stored)
        }
        return entry
    }

    /// Quick add: no saved food. Name is optional.
    @discardableResult
    func quickAdd(userId: UUID, on date: Date, name: String? = nil, nutrients: NutrientValues, servings: Double = 1,
                  mealSlotId: UUID? = nil) -> FoodEntry {
        let stamp = now()
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let entry = FoodEntry(id: UUID(), userId: userId, date: date.startOfDay, foodId: nil,
                              name: trimmed.isEmpty ? "Quick add" : trimmed, servings: max(0, servings),
                              servingLabel: "serving", perServing: nutrients, source: .quick,
                              createdAt: stamp, updatedAt: stamp, mealSlotId: mealSlotId)
        queueMealSlotIfNeeded(mealSlotId)
        localStorage.saveFoodEntry(entry)
        queue(entry)
        return entry
    }

    /// Saves edits to an entry (servings, name, snapshot values, day).
    @discardableResult
    func updateEntry(_ entry: FoodEntry) -> FoodEntry {
        var saved = entry
        saved.date = entry.date.startOfDay
        saved.updatedAt = now()
        queueMealSlotIfNeeded(saved.mealSlotId)
        localStorage.saveFoodEntry(saved)
        queue(saved)
        return saved
    }

    func deleteEntry(id: UUID, userId: UUID) {
        guard let entry = localStorage.fetchFoodEntry(id: id), entry.userId == userId else { return }
        localStorage.deleteFoodEntries(ids: [id])
        offlineQueueManager.submit(.deleteFoodEntry, payload: DeleteNutritionRecordPayload(id: id))
        offlineQueueManager.submitTombstones(.foodEntry, ids: [id])
    }

    func entries(userId: UUID, on date: Date) -> [FoodEntry] {
        localStorage.fetchFoodEntries(userId: userId, on: date)
    }

    // MARK: - Daily totals

    /// Entries, totals (macros and micros; unknown micros stay nil), the target that applied that day,
    /// and what is left (negative means over).
    func dailyNutrition(userId: UUID, on date: Date) -> DailyNutrition {
        let day = date.startOfDay
        let entries = localStorage.fetchFoodEntries(userId: userId, on: day)
        let totals = NutritionMath.totals(of: entries)
        let target = resolvedTarget(userId: userId, on: day)
        return DailyNutrition(date: day, entries: entries, totals: totals, target: target,
                              remaining: target.map { NutritionMath.remaining(target: $0, totals: totals) })
    }
}
