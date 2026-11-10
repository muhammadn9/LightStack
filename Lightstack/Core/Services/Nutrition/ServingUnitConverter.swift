import Foundation

/// Pure conversion between "amount + unit" and servings of a saved food, using the standard US factors in
/// `NutritionUnit` (1 oz = 28.3495 g, 1 fl oz = 29.5735 ml, 1 cup = 236.588 ml, 1 tbsp = 14.7868 ml,
/// 1 tsp = 4.92892 ml). Mass and volume are never converted into each other: a food can be logged in grams only
/// when its grams per serving are known, and in volume units only when its serving is a volume. A food with both
/// (say "1 cup" at 245 g) offers both families, and each converts through the serving.
enum ServingUnitConverter {

    /// Canonical order of the units the converter can offer.
    static let canonicalOrder: [NutritionUnit] = [.serving, .g, .oz, .ml, .flOz, .cup, .tbsp, .tsp]

    private static let volumeUnits: Set<NutritionUnit> = [.ml, .flOz, .cup, .tbsp, .tsp]
    private static let massUnits: Set<NutritionUnit> = [.g, .oz]

    // MARK: - What a food knows

    /// The unit a food's serving is given in (accepts "fl oz" as well as "flOz").
    static func servingUnit(of food: NutritionFood) -> NutritionUnit? {
        NutritionUnit(rawValue: food.servingUnit) ?? NutritionUnit.parse(food.servingUnit)
    }

    /// Grams in one serving, when known: the stored grams, or the serving itself when it is given in g / oz.
    static func gramsPerServing(of food: NutritionFood) -> Double? {
        if let grams = food.servingGrams, grams > 0 { return grams }
        if let unit = servingUnit(of: food), massUnits.contains(unit),
           let perUnit = unit.gramsPerUnit, food.servingAmount > 0 {
            return food.servingAmount * perUnit
        }
        return nil
    }

    /// Millilitres in one serving, when the serving is a volume (ml, fl oz, cup, tbsp, tsp).
    static func millilitresPerServing(of food: NutritionFood) -> Double? {
        guard let unit = servingUnit(of: food), volumeUnits.contains(unit),
              let perUnit = unit.millilitresPerUnit, food.servingAmount > 0 else { return nil }
        return food.servingAmount * perUnit
    }

    /// The units the user can log this food in: "serving" always, g and oz when grams are known,
    /// ml / fl oz / cup / tbsp / tsp when the serving is a volume.
    static func availableUnits(for food: NutritionFood) -> [NutritionUnit] {
        var units: [NutritionUnit] = [.serving]
        if gramsPerServing(of: food) != nil { units += [.g, .oz] }
        if millilitresPerServing(of: food) != nil { units += [.ml, .flOz, .cup, .tbsp, .tsp] }
        return units
    }

    /// `units` with the favourites first (in the user's order, only those present), then the rest in canonical order.
    static func ordered(_ units: [NutritionUnit], favorites: [NutritionUnit]) -> [NutritionUnit] {
        var result: [NutritionUnit] = []
        for unit in favorites where units.contains(unit) && !result.contains(unit) { result.append(unit) }
        for unit in canonicalOrder where units.contains(unit) && !result.contains(unit) { result.append(unit) }
        for unit in units where !result.contains(unit) { result.append(unit) }
        return result
    }

    // MARK: - Conversion

    /// How many servings `amount` of `unit` is. nil when the food cannot be measured in that unit.
    static func servings(amount: Double, unit: NutritionUnit, for food: NutritionFood) -> Double? {
        guard amount.isFinite, amount >= 0 else { return nil }
        if unit == .serving { return amount }
        if massUnits.contains(unit) {
            guard let perUnit = unit.gramsPerUnit, let perServing = gramsPerServing(of: food), perServing > 0 else { return nil }
            return amount * perUnit / perServing
        }
        if volumeUnits.contains(unit) {
            guard let perUnit = unit.millilitresPerUnit, let perServing = millilitresPerServing(of: food), perServing > 0 else { return nil }
            return amount * perUnit / perServing
        }
        return nil
    }

    /// The amount of `unit` that `servings` servings come to. nil when the food cannot be measured in that unit.
    static func amount(forServings servings: Double, in unit: NutritionUnit, for food: NutritionFood) -> Double? {
        guard servings.isFinite, servings >= 0 else { return nil }
        if unit == .serving { return servings }
        if massUnits.contains(unit) {
            guard let perUnit = unit.gramsPerUnit, perUnit > 0, let perServing = gramsPerServing(of: food) else { return nil }
            return servings * perServing / perUnit
        }
        if volumeUnits.contains(unit) {
            guard let perUnit = unit.millilitresPerUnit, perUnit > 0, let perServing = millilitresPerServing(of: food) else { return nil }
            return servings * perServing / perUnit
        }
        return nil
    }

    /// Converts an amount between two units of the same food (through servings). nil for unsupported pairs,
    /// for example grams to cups of a food with no volume.
    static func convert(_ amount: Double, from: NutritionUnit, to: NutritionUnit, for food: NutritionFood) -> Double? {
        guard let servings = servings(amount: amount, unit: from, for: food) else { return nil }
        return Self.amount(forServings: servings, in: to, for: food)
    }

    // MARK: - Labels

    /// "150 g", "1 serving", "2 servings", "1.5 cup".
    static func label(amount: Double, unit: NutritionUnit) -> String {
        let text = format(amount)
        if unit == .serving { return "\(text) \(amount == 1 ? "serving" : "servings")" }
        return "\(text) \(unit.displayName)"
    }

    /// The label for `servings` servings of a food shown in `unit` ("150 g"); falls back to servings when the
    /// food cannot be measured in that unit.
    static func label(servings: Double, in unit: NutritionUnit, for food: NutritionFood) -> String {
        if let amount = amount(forServings: servings, in: unit, for: food) { return label(amount: amount, unit: unit) }
        return label(amount: servings, unit: .serving)
    }

    /// Up to two decimals, trailing zeros removed ("150", "1.5", "0.33").
    static func format(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

/// The user's favourite serving units, an ordered list the UI shows first. Stored in UserDefaults like the
/// other display preferences (`WaterUnit`); not synced.
enum ServingUnitPreferences {
    /// UserDefaults / @AppStorage key (comma-separated unit raw values).
    static let storageKey = "nutritionFavoriteServingUnits"

    static func favorites(defaults: UserDefaults = .standard) -> [NutritionUnit] {
        let raw = defaults.string(forKey: storageKey) ?? ""
        var seen = Set<NutritionUnit>()
        return raw.split(separator: ",").compactMap { NutritionUnit(rawValue: String($0)) }.filter { seen.insert($0).inserted }
    }

    static func setFavorites(_ units: [NutritionUnit], defaults: UserDefaults = .standard) {
        var seen = Set<NutritionUnit>()
        let unique = units.filter { seen.insert($0).inserted }
        defaults.set(unique.map(\.rawValue).joined(separator: ","), forKey: storageKey)
    }
}
