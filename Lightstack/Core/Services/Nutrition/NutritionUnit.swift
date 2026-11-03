import Foundation

/// User-selectable serving units. Gram / millilitre conversions are provided only
/// where they are defined without needing a food density.
enum NutritionUnit: String, CaseIterable, Codable, Identifiable {
    case g, oz, cup, ml, flOz, tbsp, tsp, piece, serving

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .g: return "g"
        case .oz: return "oz"
        case .cup: return "cup"
        case .ml: return "ml"
        case .flOz: return "fl oz"
        case .tbsp: return "tbsp"
        case .tsp: return "tsp"
        case .piece: return "piece"
        case .serving: return "serving"
        }
    }

    /// Grams in one of this unit (mass units only).
    var gramsPerUnit: Double? {
        switch self {
        case .g: return 1
        case .oz: return 28.3495
        default: return nil
        }
    }

    /// Millilitres in one of this unit (volume units only).
    var millilitresPerUnit: Double? {
        switch self {
        case .ml: return 1
        case .cup: return 236.588
        case .flOz: return 29.5735
        case .tbsp: return 14.7868
        case .tsp: return 4.92892
        default: return nil
        }
    }

    func grams(forQuantity quantity: Double) -> Double? {
        gramsPerUnit.map { $0 * quantity }
    }

    func millilitres(forQuantity quantity: Double) -> Double? {
        millilitresPerUnit.map { $0 * quantity }
    }

    /// Recognises a unit word from label text ("cups", "fl oz", "tbsp", "slice" ...).
    static func parse(_ text: String) -> NutritionUnit? {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        switch t {
        case "g", "gram", "grams", "gm": return .g
        case "oz", "ounce", "ounces": return .oz
        case "cup", "cups", "c": return .cup
        case "ml", "milliliter", "milliliters", "millilitre", "millilitres": return .ml
        case "fl oz", "floz", "fl. oz", "fluid ounce", "fluid ounces": return .flOz
        case "tbsp", "tablespoon", "tablespoons": return .tbsp
        case "tsp", "teaspoon", "teaspoons": return .tsp
        case "piece", "pieces", "pc", "pcs", "slice", "slices", "bar", "bars", "cookie", "cookies",
             "biscuit", "biscuits", "item", "items", "each": return .piece
        case "serving", "servings", "portion", "portions": return .serving
        default: return nil
        }
    }
}
