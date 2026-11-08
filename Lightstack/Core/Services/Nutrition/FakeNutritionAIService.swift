#if DEBUG
import Foundation

/// Deterministic stand-in for the meal estimator: used under `-uiTesting` and by unit tests. Never touches
/// the network.
///
/// - text containing "fail" -> error (`.failed`)
/// - "half" + "chipotle" -> one item, Chicken Burrito Bowl from Chipotle, servings 0.5, full 1000 kcal /
///   P60 C100 F35, with two fake sources
/// - "greek yogurt" + "strawberr" -> two items
/// - a photo (no matching text) -> one item
/// - anything else -> one generic item
final class FakeNutritionAIService: NutritionAIServicing, @unchecked Sendable {

    private let lock = NSLock()
    private var _calls: [(text: String, hasImage: Bool)] = []
    private let delay: TimeInterval

    init(delay: TimeInterval = 0) { self.delay = delay }

    var calls: [(text: String, hasImage: Bool)] { lock.withLock { _calls } }

    static let chipotleSources = [
        AIFoodSource(title: "Chipotle Nutrition Calculator", url: "https://www.chipotle.com/nutrition-calculator"),
        AIFoodSource(title: "Chicken Burrito Bowl - Chipotle", url: "https://www.chipotle.com/order/build-your-own")
    ]

    func estimate(text: String, image: Data?, mealContext: AIMealContext?) async throws -> AIMealEstimate {
        lock.withLock { _calls.append((text, image != nil)) }
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        let lower = text.lowercased()
        if lower.contains("fail") { throw NutritionAIError.failed("The AI couldn't be reached. Please try again.") }

        func nutrients(_ kcal: Double, _ p: Double, _ c: Double, _ f: Double, fiber: Double? = nil, sugar: Double? = nil,
                       sodium: Double? = nil, satFat: Double? = nil) -> NutrientValues {
            var micros = Micronutrients()
            micros[.fiber] = fiber; micros[.sugar] = sugar; micros[.sodium] = sodium; micros[.satFat] = satFat
            return NutrientValues(kcal: kcal, protein: p, carbs: c, fat: f, micros: micros)
        }

        if lower.contains("chipotle") {
            let isHalf = lower.contains("half")
            let item = AIMealItem(
                name: "Chicken Burrito Bowl", restaurant: "Chipotle", brand: nil,
                portionText: isHalf ? "half" : "", servings: isHalf ? 0.5 : 1, servingLabel: "1 bowl",
                fullItem: nutrients(1000, 60, 100, 35, fiber: 14, sugar: 6, sodium: 2100, satFat: 11),
                confidence: .high, notes: "Chicken, white rice, black beans, fajita veggies, salsa and cheese.",
                sources: Self.chipotleSources)
            return AIMealEstimate(items: [item], clarifyingQuestion: nil, usedSearch: true, sources: Self.chipotleSources)
        }
        if lower.contains("yogurt") || lower.contains("strawberr") {
            let yogurt = AIMealItem(
                name: "Greek Yogurt", restaurant: nil, brand: nil, portionText: "1 cup", servings: 1,
                servingLabel: "1 cup (245 g)", fullItem: nutrients(150, 20, 9, 4, sugar: 8, sodium: 70),
                confidence: .high, notes: "Plain, low fat.")
            let strawberries = AIMealItem(
                name: "Strawberries", restaurant: nil, brand: nil, portionText: "2 strawberries", servings: 2,
                servingLabel: "1 medium strawberry (12 g)", fullItem: nutrients(4, 0.1, 1, 0, fiber: 0.2, sugar: 0.7),
                confidence: .medium, notes: "")
            return AIMealEstimate(items: [yogurt, strawberries], clarifyingQuestion: nil, usedSearch: false, sources: [])
        }
        if image != nil && lower.isEmpty {
            let item = AIMealItem(
                name: "Chicken Salad", restaurant: nil, brand: nil, portionText: "", servings: 1,
                servingLabel: "1 plate", fullItem: nutrients(420, 35, 18, 24, fiber: 5, sugar: 6, sodium: 650),
                confidence: .low, notes: "Estimated from the photo.")
            return AIMealEstimate(items: [item], clarifyingQuestion: nil, usedSearch: false, sources: [])
        }
        let item = AIMealItem(
            name: "Mixed Meal", restaurant: nil, brand: nil, portionText: "", servings: 1, servingLabel: "1 serving",
            fullItem: nutrients(500, 30, 50, 20), confidence: .medium, notes: "")
        return AIMealEstimate(items: [item], clarifyingQuestion: nil, usedSearch: false, sources: [])
    }
}
#endif
