import Foundation

// MARK: - Errors

/// Why an Open Food Facts call failed. Callers show `message` and decide whether to offer a retry.
enum OpenFoodFactsError: Error, Equatable, LocalizedError {
    /// No connection (or the request timed out).
    case offline
    /// The barcode is not in the database (or is not a valid barcode).
    case notFound
    /// Too many requests: our own client-side limit, or HTTP 429 from the server.
    case rateLimited
    /// The server answered with something we cannot read, or a product without usable nutrition.
    case badData
    /// Server trouble (5xx or an unexpected status).
    case unavailable

    var errorDescription: String? { message }

    var message: String {
        switch self {
        case .offline: return "You appear to be offline. Check your connection and try again."
        case .notFound: return "No product found for that barcode."
        case .rateLimited: return "Too many lookups. Wait a moment and try again."
        case .badData: return "The food database sent data we could not read."
        case .unavailable: return "The food database is unavailable right now. Try again later."
        }
    }
}

// MARK: - Domain product

/// Things worth telling the user about an imported product.
enum OpenFoodFactsWarning: String, Codable, Equatable {
    /// Calories were converted from kilojoules.
    case kcalFromKilojoules
    /// The product has no calories; they were computed from protein, carbs and fat (4/4/9).
    case kcalFromMacros
    /// Some of protein/carbs/fat were missing and are treated as 0.
    case missingMacros
    /// No serving size on record: values are per 100 g (or 100 ml).
    case per100Only
}

/// A product from Open Food Facts, with values for one serving (when the product lists a serving size
/// in g/ml) or per 100 g/ml otherwise.
struct OpenFoodFactsProduct: Equatable, Identifiable, Codable {
    var barcode: String
    var name: String
    var brand: String?
    /// Label text for the portion the values describe, e.g. "30 g" or "100 g".
    var servingLabel: String
    /// "g" or "ml".
    var servingUnit: String
    /// How many `servingUnit`s the values describe (the serving, or 100).
    var servingAmount: Double
    /// true when the values are per `servingAmount` of a real serving; false when they are per 100.
    var hasServingSize: Bool
    var nutrients: NutrientValues
    /// Package size text, e.g. "500 g".
    var quantityText: String?
    var imageURL: URL?
    var warnings: [OpenFoodFactsWarning]

    var id: String { barcode }
    var displayBrand: String? { brand }
    /// Weight of the portion in grams (nil for millilitre products).
    var servingGrams: Double? { servingUnit == "g" ? servingAmount : nil }

    // Codable (NutrientValues is not Codable itself).
    private struct Flat: Codable {
        var kcal: Double, protein: Double, carbs: Double, fat: Double
        var micros: [String: Double]
    }

    private enum CodingKeys: String, CodingKey {
        case barcode, name, brand, servingLabel, servingUnit, servingAmount, hasServingSize
        case nutrients, quantityText, imageURL, warnings
    }

    init(barcode: String, name: String, brand: String?, servingLabel: String, servingUnit: String,
         servingAmount: Double, hasServingSize: Bool, nutrients: NutrientValues, quantityText: String? = nil,
         imageURL: URL? = nil, warnings: [OpenFoodFactsWarning] = []) {
        self.barcode = barcode; self.name = name; self.brand = brand; self.servingLabel = servingLabel
        self.servingUnit = servingUnit; self.servingAmount = servingAmount; self.hasServingSize = hasServingSize
        self.nutrients = nutrients; self.quantityText = quantityText; self.imageURL = imageURL; self.warnings = warnings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        barcode = try c.decode(String.self, forKey: .barcode)
        name = try c.decode(String.self, forKey: .name)
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        servingLabel = try c.decode(String.self, forKey: .servingLabel)
        servingUnit = try c.decode(String.self, forKey: .servingUnit)
        servingAmount = try c.decode(Double.self, forKey: .servingAmount)
        hasServingSize = try c.decode(Bool.self, forKey: .hasServingSize)
        let flat = try c.decode(Flat.self, forKey: .nutrients)
        var micros = Micronutrients()
        for key in MicroKey.allCases { if let v = flat.micros[key.rawValue] { micros[key] = v } }
        nutrients = NutrientValues(kcal: flat.kcal, protein: flat.protein, carbs: flat.carbs, fat: flat.fat, micros: micros)
        quantityText = try c.decodeIfPresent(String.self, forKey: .quantityText)
        imageURL = try c.decodeIfPresent(URL.self, forKey: .imageURL)
        warnings = try c.decodeIfPresent([OpenFoodFactsWarning].self, forKey: .warnings) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(barcode, forKey: .barcode)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(brand, forKey: .brand)
        try c.encode(servingLabel, forKey: .servingLabel)
        try c.encode(servingUnit, forKey: .servingUnit)
        try c.encode(servingAmount, forKey: .servingAmount)
        try c.encode(hasServingSize, forKey: .hasServingSize)
        var micros: [String: Double] = [:]
        for (key, value) in nutrients.micros.values { micros[key.rawValue] = value }
        try c.encode(Flat(kcal: nutrients.kcal, protein: nutrients.protein, carbs: nutrients.carbs,
                          fat: nutrients.fat, micros: micros), forKey: .nutrients)
        try c.encodeIfPresent(quantityText, forKey: .quantityText)
        try c.encodeIfPresent(imageURL, forKey: .imageURL)
        try c.encode(warnings, forKey: .warnings)
    }
}

// MARK: - Parser

/// Turns Open Food Facts JSON into `OpenFoodFactsProduct`. Pure (no I/O) and tolerant of the messy data in
/// the real database: numbers sent as strings, comma decimals, kJ-only energy, salt instead of sodium,
/// missing serving sizes.
enum OpenFoodFactsParser {

    /// The `fields` query value used for both endpoints.
    static let fields = "code,product_name,product_name_en,brands,serving_size,serving_quantity,serving_quantity_unit,nutriments,quantity,image_front_small_url"

    // MARK: Responses

    /// `/api/v2/product/{barcode}.json`
    static func parseProductResponse(_ data: Data) throws -> OpenFoodFactsProduct {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw OpenFoodFactsError.badData
        }
        // status 1 = found, 0 = "product not found" (v2 also uses HTTP 404).
        let status = number(root["status"])
        guard let productDict = root["product"] as? [String: Any], status != 0 else {
            if status == 0 { throw OpenFoodFactsError.notFound }
            throw OpenFoodFactsError.badData
        }
        var dict = productDict
        if dict["code"] == nil, let code = root["code"] { dict["code"] = code }
        guard let product = parseProduct(dict) else { throw OpenFoodFactsError.badData }
        return product
    }

    /// search-a-licious `GET /search?q=...` (`{"hits":[...]}`). Products without a name or usable nutrition
    /// are skipped. A body that is not JSON (e.g. an HTML bot-check page) means the service is unavailable.
    static func parseSearchResponse(_ data: Data) throws -> [OpenFoodFactsProduct] {
        guard let json = try? JSONSerialization.jsonObject(with: data), let root = json as? [String: Any] else {
            throw OpenFoodFactsError.unavailable
        }
        guard let products = (root["hits"] ?? root["products"]) as? [[String: Any]] else {
            throw OpenFoodFactsError.badData
        }
        var seen = Set<String>()
        var result: [OpenFoodFactsProduct] = []
        for dict in products {
            guard let product = parseProduct(dict), seen.insert(product.barcode).inserted else { continue }
            result.append(product)
        }
        return result
    }

    // MARK: Product

    /// nil when the product cannot be used: no barcode, no name, or no calories and no macros at all.
    static func parseProduct(_ p: [String: Any]) -> OpenFoodFactsProduct? {
        guard let code = barcode(p["code"]) ?? barcode(p["_id"]) else { return nil }
        let name = firstNonEmpty(p["product_name"], p["product_name_en"], p["generic_name"])
        guard let name else { return nil }
        let nutriments = (p["nutriments"] as? [String: Any]) ?? [:]

        // Serving: a real serving needs a positive gram/millilitre quantity.
        let servingText = clean(p["serving_size"])
        let quantityText = clean(p["quantity"])
        var servingQty = number(p["serving_quantity"]).flatMap { $0 > 0 ? $0 : nil }
        let unitHint = clean(p["serving_quantity_unit"])?.lowercased()
        let isMl = unitHint == "ml" || unitHint == "l" || isMillilitres(servingText) || (servingText == nil && isMillilitres(quantityText))
        if let q = servingQty, q > 5_000 { servingQty = nil }   // junk like "1" kg stored as grams

        // Per-100 values, falling back to serving values scaled up.
        func per100(_ key: String) -> Double? {
            if let v = number(nutriments["\(key)_100g"]) { return v }
            if let s = number(nutriments["\(key)_serving"]), let q = servingQty { return s / q * 100 }
            return nil
        }
        func perServing(_ key: String) -> Double? {
            if let v = number(nutriments["\(key)_serving"]), servingQty != nil { return v }
            return nil
        }

        // Each nutrient as per-100 and (optionally) per-serving, in canonical units.
        struct Pair { var per100: Double?; var serving: Double? }
        func pair(_ key: String, scale: Double = 1) -> Pair {
            Pair(per100: per100(key).map { $0 * scale }, serving: perServing(key).map { $0 * scale })
        }

        var warnings: [OpenFoodFactsWarning] = []

        // Energy: prefer kcal, else kilojoules / 4.184.
        var kcal = pair("energy-kcal")
        if kcal.per100 == nil && kcal.serving == nil {
            var kj = pair("energy-kj")
            if kj.per100 == nil && kj.serving == nil { kj = pair("energy") }   // `energy` is kJ
            if kj.per100 != nil || kj.serving != nil {
                kcal = Pair(per100: kj.per100.map { $0 / 4.184 }, serving: kj.serving.map { $0 / 4.184 })
                warnings.append(.kcalFromKilojoules)
            }
        }
        let protein = pair("proteins"), carbs = pair("carbohydrates"), fat = pair("fat")
        let fiber = pair("fiber"), sugar = pair("sugars"), satFat = pair("saturated-fat")
        // Sodium in g -> mg; salt g * 400 = sodium mg.
        var sodium = pair("sodium", scale: 1000)
        if sodium.per100 == nil && sodium.serving == nil { sodium = pair("salt", scale: 400) }

        let macros = [protein, carbs, fat]
        let anyMacro = macros.contains { $0.per100 != nil || $0.serving != nil }
        let anyKcal = kcal.per100 != nil || kcal.serving != nil
        guard anyKcal || anyMacro else { return nil }

        // Choose the basis.
        let useServing = servingQty != nil
        let amount = useServing ? (servingQty ?? 100) : 100
        func value(_ pair: Pair) -> Double? {
            if useServing {
                if let s = pair.serving { return s }
                if let h = pair.per100 { return h * amount / 100 }
                return nil
            }
            return pair.per100
        }

        if macros.contains(where: { value($0) == nil }) && anyMacro || (!anyMacro && anyKcal) {
            warnings.append(.missingMacros)
        }
        var kcalValue = value(kcal)
        if kcalValue == nil {
            kcalValue = NutritionMath.derivedKcal(protein: value(protein) ?? 0, carbs: value(carbs) ?? 0, fat: value(fat) ?? 0)
            warnings.append(.kcalFromMacros)
        }

        var micros = Micronutrients()
        if let v = value(fiber) { micros[.fiber] = round1(v) }
        if let v = value(sugar) { micros[.sugar] = round1(v) }
        if let v = value(satFat) { micros[.satFat] = round1(v) }
        if let v = value(sodium) { micros[.sodium] = v.rounded() }

        let unit = isMl ? "ml" : "g"
        let label: String
        if useServing {
            label = servingText.map { String($0.prefix(60)) } ?? "\(NutritionFormat.amount(amount)) \(unit)"
        } else {
            label = "100 \(unit)"
            warnings.append(.per100Only)
        }

        let brand = brand(p["brands"])
        let nutrients = NutrientValues(kcal: (kcalValue ?? 0).rounded(), protein: round1(value(protein) ?? 0),
                                       carbs: round1(value(carbs) ?? 0), fat: round1(value(fat) ?? 0), micros: micros)
        return OpenFoodFactsProduct(
            barcode: code, name: name, brand: brand, servingLabel: label, servingUnit: unit,
            servingAmount: round1(amount), hasServingSize: useServing, nutrients: nutrients,
            quantityText: quantityText, imageURL: (clean(p["image_front_small_url"])).flatMap(URL.init(string:)),
            warnings: warnings
        )
    }

    // MARK: Helpers

    /// Accepts numbers and numeric strings ("12", "12.5", "12,5", "12.5 g"). Negative, NaN and infinite give nil.
    static func number(_ any: Any?) -> Double? {
        let value: Double?
        switch any {
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            value = n.doubleValue
        case let s as String:
            var t = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
            // Keep the leading numeric part only ("12.5 g" -> "12.5").
            if let end = t.firstIndex(where: { !($0.isNumber || $0 == "." || $0 == "-" || $0 == "+" || $0 == "e" || $0 == "E") }) {
                t = String(t[..<end])
            }
            value = Double(t)
        default:
            value = nil
        }
        guard let v = value, v.isFinite, v >= 0 else { return nil }
        return v
    }

    private static func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }

    private static func clean(_ any: Any?) -> String? {
        guard let s = any as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func firstNonEmpty(_ values: Any?...) -> String? {
        for v in values { if let s = clean(v) { return s } }
        return nil
    }

    private static func barcode(_ any: Any?) -> String? {
        let raw: String?
        if let s = any as? String { raw = s } else if let n = any as? NSNumber { raw = n.stringValue } else { raw = nil }
        guard let digits = raw?.trimmingCharacters(in: .whitespaces), (6...14).contains(digits.count),
              digits.allSatisfy(\.isNumber) else { return nil }
        return digits
    }

    /// Brands arrive as an array (search-a-licious) or a comma-separated string (product endpoint).
    private static func brand(_ any: Any?) -> String? {
        if let list = any as? [Any] {
            return list.compactMap { clean($0) }.first
        }
        return clean(any).flatMap { first(of: $0) }
    }

    /// "Brand A, Brand B" -> "Brand A".
    private static func first(of brands: String) -> String? {
        let first = brands.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        return (first?.isEmpty ?? true) ? nil : first
    }

    private static func isMillilitres(_ text: String?) -> Bool {
        guard let t = text?.lowercased() else { return false }
        return t.range(of: #"\d\s*(ml|cl|dl)\b"#, options: .regularExpression) != nil
            || t.range(of: #"\d\s*l\b"#, options: .regularExpression) != nil
            || t.contains("fl oz")
    }
}
