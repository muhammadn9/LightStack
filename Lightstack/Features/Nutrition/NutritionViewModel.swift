import Foundation
import SwiftUI

/// Drives the Nutrition tab: the selected day, its totals against the target, and all diary actions.
@MainActor
final class NutritionViewModel: ObservableObject {

    @Published private(set) var date: Date = Date().startOfDay
    @Published private(set) var daily: DailyNutrition?

    private let repository: NutritionRepository
    private let userIdProvider: () -> UUID?

    init(repository: NutritionRepository, userIdProvider: @escaping () -> UUID?) {
        self.repository = repository
        self.userIdProvider = userIdProvider
    }

    var userId: UUID? { userIdProvider() }

    var isToday: Bool { Calendar.current.isDateInToday(date) }

    // MARK: - Day

    func reload() {
        guard let userId else { daily = nil; return }
        daily = repository.dailyNutrition(userId: userId, on: date)
    }

    func shiftDay(by days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: date) else { return }
        date = next.startOfDay
        reload()
    }

    func goToToday() {
        date = Date().startOfDay
        reload()
    }

    // MARK: - Targets

    func currentTarget() -> NutritionTarget? {
        guard let userId else { return nil }
        return repository.target(userId: userId, on: date)
    }

    func saveTarget(protein: Double, carbs: Double, fat: Double, kcalOverride: Double?) {
        guard let userId else { return }
        repository.setTarget(userId: userId, effectiveDate: date, protein: protein, carbs: carbs, fat: fat,
                             kcalOverride: kcalOverride)
        reload()
    }

    // MARK: - Entries

    func quickAdd(name: String?, nutrients: NutrientValues) {
        guard let userId else { return }
        repository.quickAdd(userId: userId, on: date, name: name, nutrients: nutrients)
        reload()
    }

    func log(_ food: NutritionFood, servings: Double) {
        repository.logFood(food, servings: servings, on: date)
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

    // MARK: - Foods

    func recentFoods() -> [NutritionFood] {
        guard let userId else { return [] }
        return repository.recentFoods(userId: userId)
    }

    func favoriteFoods() -> [NutritionFood] {
        guard let userId else { return [] }
        return repository.favoriteFoods(userId: userId)
    }

    func searchFoods(_ query: String) -> [NutritionFood] {
        guard let userId else { return [] }
        return repository.searchFoods(userId: userId, query: query)
    }

    func setFavorite(_ food: NutritionFood, _ isFavorite: Bool) {
        repository.setFavorite(foodId: food.id, isFavorite: isFavorite)
    }

    /// Saves a new food and, when `servings` is given, logs that many servings on the selected day.
    @discardableResult
    func saveFood(_ food: NutritionFood, logServings servings: Double?) -> NutritionFood {
        let saved = repository.saveFood(food)
        if let servings, servings > 0 { repository.logFood(saved, servings: servings, on: date) }
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
