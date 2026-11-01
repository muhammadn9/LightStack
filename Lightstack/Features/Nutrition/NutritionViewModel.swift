import Foundation
import SwiftUI

/// Drives the whole nutrition side: the selected day, its summary (totals per meal), meal slots,
/// water, trackers, notes and every diary action. One instance is shared by all four tabs.
@MainActor
final class NutritionViewModel: ObservableObject {

    @Published private(set) var date: Date = Date().startOfDay
    @Published private(set) var summary: JournalDaySummary?
    @Published private(set) var waterEntries: [WaterEntry] = []
    @Published private(set) var trackers: [NutrientTracker] = []
    @Published private(set) var waterUnit: WaterUnit = WaterUnit.current()
    /// Bumped whenever the saved-food list changes, so Kitchen and the add-food flow refresh.
    @Published private(set) var foodsVersion = 0

    private let repository: NutritionRepository
    private let userIdProvider: () -> UUID?

    init(repository: NutritionRepository, userIdProvider: @escaping () -> UUID?) {
        self.repository = repository
        self.userIdProvider = userIdProvider
    }

    var userId: UUID? { userIdProvider() }
    var isToday: Bool { Calendar.current.isDateInToday(date) }

    private var trackerStore: NutrientTrackerStore? {
        userId.map { NutrientTrackerStore(userId: $0) }
    }

    /// Active meals in order.
    var slots: [MealSlot] { summary?.meals.compactMap(\.slot).filter { !$0.isArchived } ?? [] }

    /// The meal a quick "Food Search" or camera action goes to: by time of day (breakfast, lunch, dinner, snack).
    var defaultSlotId: UUID? {
        let all = slots
        guard !all.isEmpty else { return nil }
        let hour = Calendar.current.component(.hour, from: Date())
        let index = hour < 11 ? 0 : hour < 15 ? 1 : hour < 21 ? 2 : 3
        return all[min(index, all.count - 1)].id
    }

    func slot(id: UUID?) -> MealSlot? {
        guard let id else { return nil }
        return slots.first { $0.id == id }
    }

    // MARK: - Day

    func reload() {
        guard let userId else { summary = nil; return }
        repository.ensureDefaultMealSlots(userId: userId)
        summary = repository.daySummary(userId: userId, on: date)
        waterEntries = repository.waterEntries(userId: userId, on: date).sorted { $0.createdAt > $1.createdAt }
        trackers = trackerStore?.trackers ?? []
        waterUnit = WaterUnit.current()
    }

    func setDate(_ day: Date) {
        date = day.startOfDay
        reload()
    }

    func shiftDay(by days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: date) else { return }
        setDate(next)
    }

    func goToToday() { setDate(Date()) }

    // MARK: - Targets

    /// The target in force today (targets are edited from Goals and apply from today on).
    func currentTarget() -> NutritionTarget? {
        guard let userId else { return nil }
        return repository.target(userId: userId, on: Date())
    }

    func saveTarget(protein: Double, carbs: Double, fat: Double, kcalOverride: Double?) {
        guard let userId else { return }
        repository.setTarget(userId: userId, effectiveDate: Date(), protein: protein, carbs: carbs, fat: fat,
                             kcalOverride: kcalOverride)
        reload()
    }

    // MARK: - Entries

    func quickAdd(name: String?, nutrients: NutrientValues, mealSlotId: UUID? = nil) {
        guard let userId else { return }
        repository.quickAdd(userId: userId, on: date, name: name, nutrients: nutrients, mealSlotId: mealSlotId)
        reload()
    }

    func log(_ food: NutritionFood, servings: Double, mealSlotId: UUID? = nil) {
        repository.logFood(food, servings: servings, on: date, mealSlotId: mealSlotId)
        foodsVersion += 1
        reload()
    }

    func logPlate(_ items: [PlateItem], mealSlotId: UUID?) {
        repository.logFoods(items, mealSlotId: mealSlotId, on: date)
        foodsVersion += 1
        reload()
    }

    func update(_ entry: FoodEntry) {
        repository.updateEntry(entry)
        reload()
    }

    func delete(_ entry: FoodEntry) {
        guard let userId else { return }
        repository.deleteEntry(id: entry.id, userId: userId)
        reload()
    }

    func move(_ entry: FoodEntry, toMeal slotId: UUID?) {
        guard let userId else { return }
        repository.moveEntry(id: entry.id, toMealSlot: slotId, userId: userId)
        reload()
    }

    /// Deletes every entry of one meal on the selected day.
    func clearMeal(slotId: UUID) {
        guard let userId, let meal = summary?.meal(for: slotId) else { return }
        meal.entries.forEach { repository.deleteEntry(id: $0.id, userId: userId) }
        reload()
    }

    // MARK: - Meal slots

    func allSlots(includeArchived: Bool) -> [MealSlot] {
        guard let userId else { return [] }
        return repository.mealSlots(userId: userId, includeArchived: includeArchived)
    }

    @discardableResult
    func addMeal(name: String) -> MealSlot? {
        guard let userId else { return nil }
        let slot = repository.addMealSlot(userId: userId, name: name)
        reload()
        return slot
    }

    func renameMeal(id: UUID, name: String) {
        repository.renameMealSlot(id: id, name: name)
        reload()
    }

    func archiveMeal(id: UUID) {
        repository.archiveMealSlot(id: id)
        reload()
    }

    func unarchiveMeal(id: UUID) {
        repository.unarchiveMealSlot(id: id)
        reload()
    }

    func reorderMeals(ids: [UUID]) {
        guard let userId else { return }
        repository.reorderMealSlots(userId: userId, orderedIds: ids)
        reload()
    }

    // MARK: - Water

    func addWater(ml: Double) {
        guard let userId else { return }
        repository.addWater(userId: userId, amountMl: ml, on: date)
        reload()
    }

    func deleteWater(_ entry: WaterEntry) {
        guard let userId else { return }
        repository.deleteWater(id: entry.id, userId: userId)
        reload()
    }

    func setWaterUnit(_ unit: WaterUnit) {
        WaterUnit.setCurrent(unit)
        waterUnit = unit
    }

    // MARK: - Day note

    func setNote(_ text: String, on day: Date) {
        guard let userId else { return }
        repository.setDayNote(userId: userId, on: day, text: text)
        if let current = summary, current.date == day.startOfDay {
            summary?.note = repository.dayNote(userId: userId, on: day)
        }
    }

    // MARK: - Trackers

    var availableTrackers: [TrackedNutrient] { trackerStore?.available ?? [] }

    func addTracker(_ nutrient: TrackedNutrient, target: Double? = nil) {
        trackerStore?.add(nutrient, dailyTarget: target)
        reload()
    }

    func removeTracker(_ nutrient: TrackedNutrient) {
        trackerStore?.remove(nutrient)
        reload()
    }

    func setTrackerTarget(_ target: Double?, for nutrient: TrackedNutrient) {
        trackerStore?.setTarget(target, for: nutrient)
        reload()
    }

    func moveTracker(from source: Int, to destination: Int) {
        trackerStore?.move(from: source, to: destination)
        reload()
    }

    // MARK: - Foods

    func recentFoods(limit: Int = 20) -> [NutritionFood] {
        guard let userId else { return [] }
        return repository.recentFoods(userId: userId, limit: limit)
    }

    func favoriteFoods() -> [NutritionFood] {
        guard let userId else { return [] }
        return repository.favoriteFoods(userId: userId)
    }

    func searchFoods(_ query: String, limit: Int = 200) -> [NutritionFood] {
        guard let userId else { return [] }
        return repository.searchFoods(userId: userId, query: query, limit: limit)
    }

    func setFavorite(_ food: NutritionFood, _ isFavorite: Bool) {
        repository.setFavorite(foodId: food.id, isFavorite: isFavorite)
        foodsVersion += 1
    }

    func deleteFood(_ food: NutritionFood) {
        guard let userId else { return }
        repository.deleteFood(id: food.id, userId: userId)
        foodsVersion += 1
    }

    /// Saves edits to a saved food (name, serving, nutrients, favourite).
    func updateFood(_ food: NutritionFood) {
        repository.saveFood(food)
        foodsVersion += 1
    }

    /// Saves a new food and, when `servings` is given, logs that many servings on the selected day into `mealSlotId`.
    @discardableResult
    func saveFood(_ food: NutritionFood, logServings servings: Double?, mealSlotId: UUID? = nil) -> NutritionFood {
        let saved = repository.saveFood(food)
        if let servings, servings > 0 { repository.logFood(saved, servings: servings, on: date, mealSlotId: mealSlotId) }
        foodsVersion += 1
        reload()
        return saved
    }
}

// MARK: - Formatting helpers

enum NutritionFormat {
    /// Whole numbers for calories ("1,234").
    static func whole(_ v: Double) -> String {
        v.rounded().formatted(.number.precision(.fractionLength(0)))
    }

    /// Up to one decimal, no trailing ".0".
    static func amount(_ v: Double) -> String {
        let rounded = (v * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }

    /// Editable text for a number field ("" for nil).
    static func field(_ v: Double?) -> String {
        guard let v else { return "" }
        return amount(v)
    }

    static func parse(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, let v = Double(t), v.isFinite else { return nil }
        return v
    }

    static func microLabel(_ key: MicroKey) -> String {
        switch key {
        case .fiber: return "Fibre"
        case .sugar: return "Sugars"
        case .addedSugar: return "Added sugars"
        case .satFat: return "Saturated fat"
        case .transFat: return "Trans fat"
        case .cholesterol: return "Cholesterol"
        case .sodium: return "Sodium"
        case .potassium: return "Potassium"
        case .calcium: return "Calcium"
        case .iron: return "Iron"
        case .vitaminD: return "Vitamin D"
        }
    }
}
