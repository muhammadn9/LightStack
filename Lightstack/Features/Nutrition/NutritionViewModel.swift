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
    /// True once the setup wizard has been finished (on any device).
    @Published private(set) var isSetupComplete = false
    @Published private(set) var plans: [NutritionPlan] = []

    /// Branded (Open Food Facts) search state for the UI.
    @Published private(set) var brandedState: BrandedSearchState = .idle

    private let repository: NutritionRepository
    private let userIdProvider: () -> UUID?
    private let foodDatabase: OpenFoodFactsServicing?
    private let brandedDebounce: TimeInterval
    private var brandedTask: Task<Void, Never>?

    /// `foodDatabase` nil = no branded lookups (searches report an error state).
    init(repository: NutritionRepository, userIdProvider: @escaping () -> UUID?,
         foodDatabase: OpenFoodFactsServicing? = nil, brandedDebounce: TimeInterval = 0.4) {
        self.repository = repository
        self.userIdProvider = userIdProvider
        self.foodDatabase = foodDatabase
        self.brandedDebounce = brandedDebounce
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
        isSetupComplete = repository.isSetupComplete(userId: userId)
        plans = repository.plans(userId: userId)
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

    // MARK: - Setup and weekday plans

    /// Saved settings, or a draft prefilled from the profile (age, height, weight).
    func goalSettingsOrDraft() -> NutritionGoalSettings? {
        guard let userId else { return nil }
        return repository.goalSettingsOrDraft(userId: userId)
    }

    /// Live preview for the wizard. Pure; nothing is saved.
    func calculate(_ settings: NutritionGoalSettings) -> GoalCalculation {
        NutritionCalculator.calculate(settings)
    }

    /// Saves the settings without finishing setup (also updates the profile).
    func saveGoalSettings(_ settings: NutritionGoalSettings) {
        repository.saveGoalSettings(settings)
        reload()
    }

    /// Finishes the wizard: saves the settings as complete and creates one plan covering all seven days.
    @discardableResult
    func completeSetup(_ settings: NutritionGoalSettings) -> NutritionPlan? {
        let result = repository.completeSetup(settings: settings, calculation: NutritionCalculator.calculate(settings))
        reload()
        return result.plan
    }

    /// The plan that applies on a day (nil = that day uses the older target history).
    func plan(for day: Date) -> NutritionPlan? {
        guard let userId else { return nil }
        return repository.plan(userId: userId, on: day)
    }

    func allPlans(includeArchived: Bool = false) -> [NutritionPlan] {
        guard let userId else { return [] }
        return repository.plans(userId: userId, includeArchived: includeArchived)
    }

    /// Weekdays (Calendar 1...7) no plan covers.
    func uncoveredWeekdays() -> [Int] {
        guard let userId else { return [] }
        return repository.uncoveredWeekdays(userId: userId)
    }

    /// Creates (`id == nil`) or edits a plan. It takes its weekdays from other plans; see the repository.
    @discardableResult
    func savePlan(id: UUID?, name: String, weekdayMask: Int, protein: Double, carbs: Double, fat: Double,
                  kcalOverride: Double?) -> NutritionPlan? {
        guard let userId else { return nil }
        let plan = repository.savePlan(userId: userId, id: id, name: name, weekdayMask: weekdayMask,
                                       protein: protein, carbs: carbs, fat: fat, kcalOverride: kcalOverride)
        reload()
        return plan
    }

    func deletePlan(_ plan: NutritionPlan) {
        guard let userId else { return }
        repository.archivePlan(id: plan.id, userId: userId)
        reload()
    }

    func reorderPlans(ids: [UUID]) {
        guard let userId else { return }
        repository.reorderPlans(userId: userId, orderedIds: ids)
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

// MARK: - Branded foods (Open Food Facts)

/// What the branded search screen shows.
enum BrandedSearchState: Equatable {
    case idle
    case loading
    case results([OpenFoodFactsProduct])
    case empty
    case error(String)
}

/// Outcome of a barcode scan.
enum BarcodeLookupResult: Equatable {
    /// Already in the user's saved foods (found without any network request).
    case local(NutritionFood)
    /// Found in Open Food Facts; not saved yet.
    case remote(OpenFoodFactsProduct)
    case notFound
    /// Offline, rate limited or the database is down.
    case failed(String)
}

extension NutritionViewModel {

    /// Debounced search. Call on every keystroke: a newer call cancels the one in flight, and a blank or
    /// one-letter query resets to idle.
    func searchBranded(_ query: String) {
        brandedTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { brandedTask = nil; brandedState = .idle; return }
        guard let foodDatabase else { brandedState = .error(OpenFoodFactsError.unavailable.message); return }
        brandedState = .loading
        let delay = brandedDebounce
        brandedTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            let outcome: BrandedSearchState
            do {
                let found = try await foodDatabase.search(query: trimmed)
                outcome = found.isEmpty ? .empty : .results(found)
            } catch is CancellationError {
                return
            } catch let error as OpenFoodFactsError {
                outcome = .error(error.message)
            } catch {
                outcome = .error(OpenFoodFactsError.unavailable.message)
            }
            guard !Task.isCancelled else { return }
            self?.brandedState = outcome
        }
    }

    func cancelBrandedSearch() {
        brandedTask?.cancel()
        brandedTask = nil
        brandedState = .idle
    }

    /// Local food first (by barcode), then Open Food Facts.
    func lookupBarcode(_ code: String) async -> BarcodeLookupResult {
        guard let normalized = Barcode.normalized(code) else { return .notFound }
        if let userId, let local = repository.food(barcode: normalized, userId: userId) { return .local(local) }
        guard let foodDatabase else { return .failed(OpenFoodFactsError.unavailable.message) }
        do {
            return .remote(try await foodDatabase.product(barcode: normalized))
        } catch OpenFoodFactsError.notFound {
            return .notFound
        } catch OpenFoodFactsError.badData {
            // Listed but unusable (no nutrition): the user can still enter it by hand.
            return .notFound
        } catch let error as OpenFoodFactsError {
            return .failed(error.message)
        } catch {
            return .failed(OpenFoodFactsError.unavailable.message)
        }
    }

    /// Saves a branded product as a saved food (source Open Food Facts, barcode kept), reusing the food
    /// already saved for that barcode. With `servings` it also logs that many servings on the selected day.
    @discardableResult
    func saveBrandedFood(_ product: OpenFoodFactsProduct, logServings servings: Double? = nil,
                         mealSlotId: UUID? = nil) -> NutritionFood? {
        guard let userId else { return nil }
        let saved = repository.saveBrandedFood(product, userId: userId)
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
