import Foundation
import CoreData

// MARK: - Micronutrients

/// Micronutrients tracked as first-class values. nil means "unknown", which is not 0.
/// Units are fixed: grams for fiber, sugar, added sugar and fats; milligrams for cholesterol, sodium,
/// potassium, calcium and iron; micrograms for vitamin D. Anything else lives in `Micronutrients.other`.
enum MicroKey: String, CaseIterable {
    case fiber, sugar, addedSugar, satFat, transFat, cholesterol, sodium, potassium, calcium, iron, vitaminD

    /// Supabase column name.
    var column: String {
        switch self {
        case .fiber: return "fiber_g"
        case .sugar: return "sugar_g"
        case .addedSugar: return "added_sugar_g"
        case .satFat: return "sat_fat_g"
        case .transFat: return "trans_fat_g"
        case .cholesterol: return "cholesterol_mg"
        case .sodium: return "sodium_mg"
        case .potassium: return "potassium_mg"
        case .calcium: return "calcium_mg"
        case .iron: return "iron_mg"
        case .vitaminD: return "vitamin_d_mcg"
        }
    }

    var unit: String {
        switch self {
        case .fiber, .sugar, .addedSugar, .satFat, .transFat: return "g"
        case .cholesterol, .sodium, .potassium, .calcium, .iron: return "mg"
        case .vitaminD: return "mcg"
        }
    }
}

struct Micronutrients: Equatable {
    var values: [MicroKey: Double] = [:]
    /// Micros without a dedicated column (name -> amount in the label's own unit).
    var other: [String: Double] = [:]

    init(values: [MicroKey: Double] = [:], other: [String: Double] = [:]) {
        self.values = values
        self.other = other
    }

    subscript(key: MicroKey) -> Double? {
        get { values[key] }
        set { values[key] = newValue }
    }

    var isEmpty: Bool { values.isEmpty && other.isEmpty }

    func scaled(by factor: Double) -> Micronutrients {
        Micronutrients(values: values.mapValues { $0 * factor }, other: other.mapValues { $0 * factor })
    }
}

// MARK: - Nutrient values and maths

/// Calories, macros and micros for one portion (a serving, an entry, or a day).
struct NutrientValues: Equatable {
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var micros = Micronutrients()

    func scaled(by factor: Double) -> NutrientValues {
        NutrientValues(kcal: kcal * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor,
                       micros: micros.scaled(by: factor))
    }

    /// Sum of parts. A micro is nil when no part knows it (unknown stays unknown, never 0);
    /// otherwise it is the sum of the parts that do.
    static func total(_ parts: [NutrientValues]) -> NutrientValues {
        var result = NutrientValues()
        for part in parts {
            result.kcal += part.kcal
            result.protein += part.protein
            result.carbs += part.carbs
            result.fat += part.fat
            for (key, value) in part.micros.values { result.micros.values[key, default: 0] += value }
            for (name, value) in part.micros.other { result.micros.other[name, default: 0] += value }
        }
        return result
    }
}

/// Target minus consumed. Negative means over the target.
struct MacroRemaining: Equatable {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
}

/// One local day: what was eaten, the target that applied, and what is left.
struct DailyNutrition: Equatable {
    var date: Date
    var entries: [FoodEntry]
    var totals: NutrientValues
    var target: NutritionTarget?
    /// nil when no target applies to that day.
    var remaining: MacroRemaining?
}

enum NutritionMath {
    static let kcalPerGramProtein = 4.0
    static let kcalPerGramCarbs = 4.0
    static let kcalPerGramFat = 9.0

    static func derivedKcal(protein: Double, carbs: Double, fat: Double) -> Double {
        protein * kcalPerGramProtein + carbs * kcalPerGramCarbs + fat * kcalPerGramFat
    }

    static func totals(of entries: [FoodEntry]) -> NutrientValues {
        NutrientValues.total(entries.map(\.total))
    }

    static func remaining(target: NutritionTarget, totals: NutrientValues) -> MacroRemaining {
        MacroRemaining(kcal: target.kcal - totals.kcal, protein: target.protein - totals.protein,
                       carbs: target.carbs - totals.carbs, fat: target.fat - totals.fat)
    }

    /// The target in force on `day`: the latest one whose effective date is on or before it
    /// (ties broken by the most recent edit, then id, so every device picks the same one).
    static func target(in targets: [NutritionTarget], on day: Date) -> NutritionTarget? {
        let start = day.startOfDay
        return targets
            .filter { $0.effectiveDate.startOfDay <= start }
            .max { a, b in
                if a.effectiveDate != b.effectiveDate { return a.effectiveDate < b.effectiveDate }
                if a.updatedAt != b.updatedAt { return a.updatedAt < b.updatedAt }
                return a.id.uuidString < b.id.uuidString
            }
    }
}

// MARK: - Wire format

/// Dynamic coding key for the snake_case columns shared by the queue and the cloud.
struct NutritionWireKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

/// A nutrition record that can write itself for the cloud (DATE columns as `yyyy-MM-dd`) or for the queue
/// (plain dates). Every column is ALWAYS written, nil as an explicit null: an omitted NOT NULL column makes
/// PostgREST bulk upserts fail or reset it to the default, and an omitted nullable one keeps a stale value.
protocol NutritionRow: Codable {
    func encodeRow(to encoder: Encoder, forCloud: Bool) throws
}

/// What the Supabase client encodes for a write.
struct CloudRow<Row: NutritionRow>: Encodable {
    let row: Row
    func encode(to encoder: Encoder) throws { try row.encodeRow(to: encoder, forCloud: true) }
}

extension NutritionRow {
    func cloudRow() -> CloudRow<Self> { CloudRow(row: self) }
}

private extension Micronutrients {
    func encode(into c: inout KeyedEncodingContainer<NutritionWireKey>) throws {
        for key in MicroKey.allCases {
            let wireKey = NutritionWireKey(key.column)
            if let value = values[key] { try c.encode(value, forKey: wireKey) } else { try c.encodeNil(forKey: wireKey) }
        }
        try c.encode(other, forKey: NutritionWireKey("other_micros"))
    }

    init(from c: KeyedDecodingContainer<NutritionWireKey>) throws {
        self.init()
        for key in MicroKey.allCases {
            values[key] = try c.decodeIfPresent(Double.self, forKey: NutritionWireKey(key.column))
        }
        other = try c.decodeIfPresent([String: Double].self, forKey: NutritionWireKey("other_micros")) ?? [:]
    }
}

private func decodeDay(_ c: KeyedDecodingContainer<NutritionWireKey>, _ name: String) throws -> Date {
    try RemoteDate.decodeDay(c, NutritionWireKey(name))
}

private func encodeDay(_ date: Date, _ name: String, forCloud: Bool, into c: inout KeyedEncodingContainer<NutritionWireKey>) throws {
    if forCloud { try c.encode(RemoteDate.dayString(date), forKey: NutritionWireKey(name)) }
    else { try c.encode(date, forKey: NutritionWireKey(name)) }
}

// MARK: - Source enums

/// How a saved food was created.
enum FoodSource: String, Codable {
    case quick, scan
}

/// How a diary entry was created.
enum EntrySource: String, Codable {
    case quick, saved, scan
}

// MARK: - Target

/// Daily goal that applies from `effectiveDate` until a later one replaces it.
struct NutritionTarget: NutritionRow, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    /// Start of the local day this target takes effect.
    var effectiveDate: Date
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    /// true when the user typed their own calories instead of the 4/4/9 figure.
    var kcalOverridden: Bool
    var createdAt: Date
    var updatedAt: Date

    var derivedKcal: Double { NutritionMath.derivedKcal(protein: protein, carbs: carbs, fat: fat) }
    /// Typed calories minus the macro-derived figure (0 when they agree).
    var kcalMismatch: Double { kcal - derivedKcal }

    /// kcal is derived from the macros (4/4/9) unless `kcalOverride` is given.
    static func make(userId: UUID, effectiveDate: Date, protein: Double, carbs: Double, fat: Double,
                     kcalOverride: Double? = nil, now: Date = Date()) -> NutritionTarget {
        NutritionTarget(
            id: UUID(), userId: userId, effectiveDate: effectiveDate.startOfDay,
            kcal: kcalOverride ?? NutritionMath.derivedKcal(protein: protein, carbs: carbs, fat: fat),
            protein: protein, carbs: carbs, fat: fat, kcalOverridden: kcalOverride != nil,
            createdAt: now, updatedAt: now
        )
    }

    init(id: UUID, userId: UUID, effectiveDate: Date, kcal: Double, protein: Double, carbs: Double, fat: Double,
         kcalOverridden: Bool, createdAt: Date, updatedAt: Date) {
        self.id = id; self.userId = userId; self.effectiveDate = effectiveDate
        self.kcal = kcal; self.protein = protein; self.carbs = carbs; self.fat = fat
        self.kcalOverridden = kcalOverridden; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    init(from entity: CDNutritionTarget) {
        id = entity.id ?? UUID()
        userId = entity.userId ?? UUID()
        effectiveDate = entity.effectiveDate ?? Date().startOfDay
        kcal = entity.kcal; protein = entity.protein; carbs = entity.carbs; fat = entity.fat
        kcalOverridden = entity.kcalOverridden
        createdAt = entity.createdAt ?? Date()
        updatedAt = entity.updatedAt ?? Date()
    }

    func apply(to entity: CDNutritionTarget) {
        entity.id = id; entity.userId = userId; entity.effectiveDate = effectiveDate.startOfDay
        entity.kcal = kcal; entity.protein = protein; entity.carbs = carbs; entity.fat = fat
        entity.kcalOverridden = kcalOverridden
        entity.createdAt = createdAt; entity.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: NutritionWireKey.self)
        id = try c.decode(UUID.self, forKey: NutritionWireKey("id"))
        userId = try c.decode(UUID.self, forKey: NutritionWireKey("user_id"))
        effectiveDate = try decodeDay(c, "effective_date")
        kcal = try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("kcal")) ?? 0
        protein = try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("protein_g")) ?? 0
        carbs = try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("carbs_g")) ?? 0
        fat = try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("fat_g")) ?? 0
        kcalOverridden = try c.decodeIfPresent(Bool.self, forKey: NutritionWireKey("kcal_overridden")) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: NutritionWireKey("created_at")) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: NutritionWireKey("updated_at")) ?? createdAt
    }

    /// Queue encoding (plain dates).
    func encode(to encoder: Encoder) throws { try encodeRow(to: encoder, forCloud: false) }

    func encodeRow(to encoder: Encoder, forCloud: Bool) throws {
        var c = encoder.container(keyedBy: NutritionWireKey.self)
        try c.encode(id, forKey: NutritionWireKey("id"))
        try c.encode(userId, forKey: NutritionWireKey("user_id"))
        try encodeDay(effectiveDate, "effective_date", forCloud: forCloud, into: &c)
        try c.encode(kcal, forKey: NutritionWireKey("kcal"))
        try c.encode(protein, forKey: NutritionWireKey("protein_g"))
        try c.encode(carbs, forKey: NutritionWireKey("carbs_g"))
        try c.encode(fat, forKey: NutritionWireKey("fat_g"))
        try c.encode(kcalOverridden, forKey: NutritionWireKey("kcal_overridden"))
        try c.encode(createdAt, forKey: NutritionWireKey("created_at"))
        try c.encode(updatedAt, forKey: NutritionWireKey("updated_at"))
    }
}

// MARK: - Food

/// A saved food, with values per serving. Editing it never rewrites logged entries (they snapshot).
struct NutritionFood: NutritionRow, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    var name: String
    var brand: String?
    /// The label's household text, e.g. "1 cup (240 ml)".
    var servingLabel: String
    /// g, oz, cup, ml, fl oz, tbsp, tsp, piece or serving (stored as text; the parser owns the unit list).
    var servingUnit: String
    /// How many `servingUnit`s one serving is (e.g. 30 for "30 g").
    var servingAmount: Double
    /// Weight of one serving in grams, when known.
    var servingGrams: Double?
    var nutrients: NutrientValues
    var source: FoodSource
    var isFavorite: Bool
    var lastUsedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    static func make(userId: UUID, name: String, brand: String? = nil, servingLabel: String = "1 serving",
                     servingUnit: String = "serving", servingAmount: Double = 1, servingGrams: Double? = nil,
                     nutrients: NutrientValues, source: FoodSource = .quick, now: Date = Date()) -> NutritionFood {
        NutritionFood(id: UUID(), userId: userId, name: name, brand: brand, servingLabel: servingLabel,
                      servingUnit: servingUnit, servingAmount: servingAmount, servingGrams: servingGrams,
                      nutrients: nutrients, source: source, isFavorite: false, lastUsedAt: nil,
                      createdAt: now, updatedAt: now)
    }

    init(id: UUID, userId: UUID, name: String, brand: String?, servingLabel: String, servingUnit: String,
         servingAmount: Double, servingGrams: Double?, nutrients: NutrientValues, source: FoodSource,
         isFavorite: Bool, lastUsedAt: Date?, createdAt: Date, updatedAt: Date) {
        self.id = id; self.userId = userId; self.name = name; self.brand = brand
        self.servingLabel = servingLabel; self.servingUnit = servingUnit; self.servingAmount = servingAmount
        self.servingGrams = servingGrams; self.nutrients = nutrients; self.source = source
        self.isFavorite = isFavorite; self.lastUsedAt = lastUsedAt; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    init(from entity: CDFood) {
        id = entity.id ?? UUID()
        userId = entity.userId ?? UUID()
        name = entity.name ?? ""
        brand = entity.brand
        servingLabel = entity.servingLabel ?? "serving"
        servingUnit = entity.servingUnit ?? "serving"
        servingAmount = entity.servingAmount
        servingGrams = entity.servingGrams?.doubleValue
        nutrients = NutrientValues(kcal: entity.kcal, protein: entity.protein, carbs: entity.carbs, fat: entity.fat,
                                   micros: entity.readMicros())
        source = FoodSource(rawValue: entity.source ?? "") ?? .quick
        isFavorite = entity.isFavorite
        lastUsedAt = entity.lastUsedAt
        createdAt = entity.createdAt ?? Date()
        updatedAt = entity.updatedAt ?? Date()
    }

    func apply(to entity: CDFood) {
        entity.id = id; entity.userId = userId; entity.name = name; entity.brand = brand
        entity.servingLabel = servingLabel; entity.servingUnit = servingUnit; entity.servingAmount = servingAmount
        entity.servingGrams = servingGrams.map { NSNumber(value: $0) }
        entity.kcal = nutrients.kcal; entity.protein = nutrients.protein
        entity.carbs = nutrients.carbs; entity.fat = nutrients.fat
        entity.writeMicros(nutrients.micros)
        entity.source = source.rawValue; entity.isFavorite = isFavorite; entity.lastUsedAt = lastUsedAt
        entity.createdAt = createdAt; entity.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: NutritionWireKey.self)
        id = try c.decode(UUID.self, forKey: NutritionWireKey("id"))
        userId = try c.decode(UUID.self, forKey: NutritionWireKey("user_id"))
        name = try c.decodeIfPresent(String.self, forKey: NutritionWireKey("name")) ?? ""
        brand = try c.decodeIfPresent(String.self, forKey: NutritionWireKey("brand"))
        servingLabel = try c.decodeIfPresent(String.self, forKey: NutritionWireKey("serving_label")) ?? "serving"
        servingUnit = try c.decodeIfPresent(String.self, forKey: NutritionWireKey("serving_unit")) ?? "serving"
        servingAmount = try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("serving_amount")) ?? 1
        servingGrams = try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("serving_grams"))
        nutrients = NutrientValues(
            kcal: try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("kcal")) ?? 0,
            protein: try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("protein_g")) ?? 0,
            carbs: try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("carbs_g")) ?? 0,
            fat: try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("fat_g")) ?? 0,
            micros: try Micronutrients(from: c)
        )
        source = FoodSource(rawValue: try c.decodeIfPresent(String.self, forKey: NutritionWireKey("source")) ?? "") ?? .quick
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: NutritionWireKey("is_favorite")) ?? false
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: NutritionWireKey("last_used_at"))
        createdAt = try c.decodeIfPresent(Date.self, forKey: NutritionWireKey("created_at")) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: NutritionWireKey("updated_at")) ?? createdAt
    }

    /// Queue encoding (plain dates).
    func encode(to encoder: Encoder) throws { try encodeRow(to: encoder, forCloud: false) }

    func encodeRow(to encoder: Encoder, forCloud: Bool) throws {
        var c = encoder.container(keyedBy: NutritionWireKey.self)
        try c.encode(id, forKey: NutritionWireKey("id"))
        try c.encode(userId, forKey: NutritionWireKey("user_id"))
        try c.encode(name, forKey: NutritionWireKey("name"))
        if let brand { try c.encode(brand, forKey: NutritionWireKey("brand")) } else { try c.encodeNil(forKey: NutritionWireKey("brand")) }
        try c.encode(servingLabel, forKey: NutritionWireKey("serving_label"))
        try c.encode(servingUnit, forKey: NutritionWireKey("serving_unit"))
        try c.encode(servingAmount, forKey: NutritionWireKey("serving_amount"))
        if let servingGrams { try c.encode(servingGrams, forKey: NutritionWireKey("serving_grams")) }
        else { try c.encodeNil(forKey: NutritionWireKey("serving_grams")) }
        try c.encode(nutrients.kcal, forKey: NutritionWireKey("kcal"))
        try c.encode(nutrients.protein, forKey: NutritionWireKey("protein_g"))
        try c.encode(nutrients.carbs, forKey: NutritionWireKey("carbs_g"))
        try c.encode(nutrients.fat, forKey: NutritionWireKey("fat_g"))
        try nutrients.micros.encode(into: &c)
        try c.encode(source.rawValue, forKey: NutritionWireKey("source"))
        try c.encode(isFavorite, forKey: NutritionWireKey("is_favorite"))
        if let lastUsedAt { try c.encode(lastUsedAt, forKey: NutritionWireKey("last_used_at")) }
        else { try c.encodeNil(forKey: NutritionWireKey("last_used_at")) }
        try c.encode(createdAt, forKey: NutritionWireKey("created_at"))
        try c.encode(updatedAt, forKey: NutritionWireKey("updated_at"))
    }
}

// MARK: - Diary entry

/// One logged item on a local day. Values are a snapshot per serving, so editing or deleting the
/// food never rewrites history; the entry's own total is `servings` times that snapshot.
struct FoodEntry: NutritionRow, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    /// Start of the local calendar day.
    var date: Date
    /// The saved food it came from; nil for quick adds and after that food was deleted.
    var foodId: UUID?
    var name: String
    var servings: Double
    var servingLabel: String
    var perServing: NutrientValues
    var source: EntrySource
    var createdAt: Date
    var updatedAt: Date

    var total: NutrientValues { perServing.scaled(by: servings) }

    init(id: UUID, userId: UUID, date: Date, foodId: UUID?, name: String, servings: Double, servingLabel: String,
         perServing: NutrientValues, source: EntrySource, createdAt: Date, updatedAt: Date) {
        self.id = id; self.userId = userId; self.date = date; self.foodId = foodId; self.name = name
        self.servings = servings; self.servingLabel = servingLabel; self.perServing = perServing
        self.source = source; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    /// Snapshot of a saved food.
    static func make(from food: NutritionFood, servings: Double, on day: Date, source: EntrySource = .saved,
                     now: Date = Date()) -> FoodEntry {
        FoodEntry(id: UUID(), userId: food.userId, date: day.startOfDay, foodId: food.id, name: food.name,
                  servings: servings, servingLabel: food.servingLabel, perServing: food.nutrients,
                  source: source, createdAt: now, updatedAt: now)
    }

    init(from entity: CDFoodEntry) {
        id = entity.id ?? UUID()
        userId = entity.userId ?? UUID()
        date = entity.date ?? Date().startOfDay
        foodId = entity.foodId
        name = entity.name ?? ""
        servings = entity.servings
        servingLabel = entity.servingLabel ?? "serving"
        perServing = NutrientValues(kcal: entity.kcal, protein: entity.protein, carbs: entity.carbs, fat: entity.fat,
                                    micros: entity.readMicros())
        source = EntrySource(rawValue: entity.source ?? "") ?? .quick
        createdAt = entity.createdAt ?? Date()
        updatedAt = entity.updatedAt ?? Date()
    }

    func apply(to entity: CDFoodEntry) {
        entity.id = id; entity.userId = userId; entity.date = date.startOfDay; entity.foodId = foodId
        entity.name = name; entity.servings = servings; entity.servingLabel = servingLabel
        entity.kcal = perServing.kcal; entity.protein = perServing.protein
        entity.carbs = perServing.carbs; entity.fat = perServing.fat
        entity.writeMicros(perServing.micros)
        entity.source = source.rawValue
        entity.createdAt = createdAt; entity.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: NutritionWireKey.self)
        id = try c.decode(UUID.self, forKey: NutritionWireKey("id"))
        userId = try c.decode(UUID.self, forKey: NutritionWireKey("user_id"))
        date = try decodeDay(c, "date")
        foodId = try c.decodeIfPresent(UUID.self, forKey: NutritionWireKey("food_id"))
        name = try c.decodeIfPresent(String.self, forKey: NutritionWireKey("name")) ?? ""
        servings = try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("servings")) ?? 1
        servingLabel = try c.decodeIfPresent(String.self, forKey: NutritionWireKey("serving_label")) ?? "serving"
        perServing = NutrientValues(
            kcal: try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("kcal")) ?? 0,
            protein: try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("protein_g")) ?? 0,
            carbs: try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("carbs_g")) ?? 0,
            fat: try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("fat_g")) ?? 0,
            micros: try Micronutrients(from: c)
        )
        source = EntrySource(rawValue: try c.decodeIfPresent(String.self, forKey: NutritionWireKey("source")) ?? "") ?? .quick
        createdAt = try c.decodeIfPresent(Date.self, forKey: NutritionWireKey("created_at")) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: NutritionWireKey("updated_at")) ?? createdAt
    }

    /// Queue encoding (plain dates).
    func encode(to encoder: Encoder) throws { try encodeRow(to: encoder, forCloud: false) }

    func encodeRow(to encoder: Encoder, forCloud: Bool) throws {
        var c = encoder.container(keyedBy: NutritionWireKey.self)
        try c.encode(id, forKey: NutritionWireKey("id"))
        try c.encode(userId, forKey: NutritionWireKey("user_id"))
        try encodeDay(date, "date", forCloud: forCloud, into: &c)
        if let foodId { try c.encode(foodId, forKey: NutritionWireKey("food_id")) }
        else { try c.encodeNil(forKey: NutritionWireKey("food_id")) }
        try c.encode(name, forKey: NutritionWireKey("name"))
        try c.encode(servings, forKey: NutritionWireKey("servings"))
        try c.encode(servingLabel, forKey: NutritionWireKey("serving_label"))
        try c.encode(perServing.kcal, forKey: NutritionWireKey("kcal"))
        try c.encode(perServing.protein, forKey: NutritionWireKey("protein_g"))
        try c.encode(perServing.carbs, forKey: NutritionWireKey("carbs_g"))
        try c.encode(perServing.fat, forKey: NutritionWireKey("fat_g"))
        try perServing.micros.encode(into: &c)
        try c.encode(source.rawValue, forKey: NutritionWireKey("source"))
        try c.encode(createdAt, forKey: NutritionWireKey("created_at"))
        try c.encode(updatedAt, forKey: NutritionWireKey("updated_at"))
    }
}

// MARK: - Core Data micros (shared by CDFood and CDFoodEntry)

extension NSManagedObject {
    /// Reads the optional micro attributes (nil stays nil) and the `otherMicros` JSON.
    func readMicros() -> Micronutrients {
        var micros = Micronutrients()
        for key in MicroKey.allCases {
            if let number = value(forKey: key.rawValue) as? NSNumber { micros[key] = number.doubleValue }
        }
        if let json = value(forKey: "otherMicros") as? String, let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            micros.other = decoded
        }
        return micros
    }

    func writeMicros(_ micros: Micronutrients) {
        for key in MicroKey.allCases {
            setValue(micros[key].map { NSNumber(value: $0) }, forKey: key.rawValue)
        }
        if micros.other.isEmpty {
            setValue(nil, forKey: "otherMicros")
        } else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let json = (try? encoder.encode(micros.other)).flatMap { String(data: $0, encoding: .utf8) }
            setValue(json, forKey: "otherMicros")
        }
    }
}
