import Foundation
import CoreData

// MARK: - Collection kind

/// What a `FoodCollection` is: a saved meal (a group logged as separate entries) or a recipe (one derived food).
enum FoodCollectionKind: String, Codable, CaseIterable {
    case meal, recipe
}

// MARK: - Collection

/// A named group of saved foods. `kind == .meal`: logging it creates one entry per item.
/// `kind == .recipe`: it owns a derived `NutritionFood` (source `.recipe`) holding the per-serving values.
struct FoodCollection: NutritionRow, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    var kind: FoodCollectionKind
    var name: String
    /// How many servings a recipe makes (> 0). Always 1 for meals.
    var servingsYield: Double
    /// Total cooked weight of a recipe in grams, when the user weighed it.
    var cookedWeightGrams: Double?
    var lastUsedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    /// The id of the food a recipe owns. Derived from the recipe id, so every device agrees on it.
    var derivedFoodId: UUID { Self.derivedFoodId(userId: userId, collectionId: id) }

    static func derivedFoodId(userId: UUID, collectionId: UUID) -> UUID {
        DeterministicID.make(userId: userId, label: "recipe-food-\(collectionId.uuidString)")
    }

    static func make(userId: UUID, kind: FoodCollectionKind, name: String, servingsYield: Double = 1,
                     cookedWeightGrams: Double? = nil, now: Date = Date()) -> FoodCollection {
        FoodCollection(id: UUID(), userId: userId, kind: kind, name: name, servingsYield: servingsYield,
                       cookedWeightGrams: cookedWeightGrams, lastUsedAt: nil, createdAt: now, updatedAt: now)
    }

    init(id: UUID, userId: UUID, kind: FoodCollectionKind, name: String, servingsYield: Double,
         cookedWeightGrams: Double?, lastUsedAt: Date?, createdAt: Date, updatedAt: Date) {
        self.id = id; self.userId = userId; self.kind = kind; self.name = name; self.servingsYield = servingsYield
        self.cookedWeightGrams = cookedWeightGrams; self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    init(from entity: CDFoodCollection) {
        id = entity.id ?? UUID()
        userId = entity.userId ?? UUID()
        kind = FoodCollectionKind(rawValue: entity.kind ?? "") ?? .meal
        name = entity.name ?? ""
        servingsYield = entity.servingsYield
        cookedWeightGrams = entity.cookedWeightGrams?.doubleValue
        lastUsedAt = entity.lastUsedAt
        createdAt = entity.createdAt ?? Date()
        updatedAt = entity.updatedAt ?? Date()
    }

    func apply(to entity: CDFoodCollection) {
        entity.id = id; entity.userId = userId; entity.kind = kind.rawValue; entity.name = name
        entity.servingsYield = servingsYield
        entity.cookedWeightGrams = cookedWeightGrams.map { NSNumber(value: $0) }
        entity.lastUsedAt = lastUsedAt
        entity.createdAt = createdAt; entity.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: NutritionWireKey.self)
        id = try c.decode(UUID.self, forKey: NutritionWireKey("id"))
        userId = try c.decode(UUID.self, forKey: NutritionWireKey("user_id"))
        kind = FoodCollectionKind(rawValue: try c.decodeIfPresent(String.self, forKey: NutritionWireKey("kind")) ?? "") ?? .meal
        name = try c.decodeIfPresent(String.self, forKey: NutritionWireKey("name")) ?? ""
        servingsYield = try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("servings_yield")) ?? 1
        cookedWeightGrams = try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("cooked_weight_g"))
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: NutritionWireKey("last_used_at"))
        createdAt = try c.decodeIfPresent(Date.self, forKey: NutritionWireKey("created_at")) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: NutritionWireKey("updated_at")) ?? createdAt
    }

    func encode(to encoder: Encoder) throws { try encodeRow(to: encoder, forCloud: false) }

    func encodeRow(to encoder: Encoder, forCloud: Bool) throws {
        var c = encoder.container(keyedBy: NutritionWireKey.self)
        try c.encode(id, forKey: NutritionWireKey("id"))
        try c.encode(userId, forKey: NutritionWireKey("user_id"))
        try c.encode(kind.rawValue, forKey: NutritionWireKey("kind"))
        try c.encode(name, forKey: NutritionWireKey("name"))
        try c.encode(servingsYield, forKey: NutritionWireKey("servings_yield"))
        if let cookedWeightGrams { try c.encode(cookedWeightGrams, forKey: NutritionWireKey("cooked_weight_g")) }
        else { try c.encodeNil(forKey: NutritionWireKey("cooked_weight_g")) }
        if let lastUsedAt { try c.encode(lastUsedAt, forKey: NutritionWireKey("last_used_at")) }
        else { try c.encodeNil(forKey: NutritionWireKey("last_used_at")) }
        try c.encode(createdAt, forKey: NutritionWireKey("created_at"))
        try c.encode(updatedAt, forKey: NutritionWireKey("updated_at"))
    }
}

// MARK: - Item

/// One saved food and how many servings of it, inside a collection.
struct FoodCollectionItem: NutritionRow, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    var collectionId: UUID
    var foodId: UUID
    var servings: Double
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID, userId: UUID, collectionId: UUID, foodId: UUID, servings: Double, sortOrder: Int,
         createdAt: Date, updatedAt: Date) {
        self.id = id; self.userId = userId; self.collectionId = collectionId; self.foodId = foodId
        self.servings = servings; self.sortOrder = sortOrder; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    init(from entity: CDFoodCollectionItem) {
        id = entity.id ?? UUID()
        userId = entity.userId ?? UUID()
        collectionId = entity.collectionId ?? UUID()
        foodId = entity.foodId ?? UUID()
        servings = entity.servings
        sortOrder = Int(entity.sortOrder)
        createdAt = entity.createdAt ?? Date()
        updatedAt = entity.updatedAt ?? Date()
    }

    func apply(to entity: CDFoodCollectionItem) {
        entity.id = id; entity.userId = userId; entity.collectionId = collectionId; entity.foodId = foodId
        entity.servings = servings; entity.sortOrder = Int64(sortOrder)
        entity.createdAt = createdAt; entity.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: NutritionWireKey.self)
        id = try c.decode(UUID.self, forKey: NutritionWireKey("id"))
        userId = try c.decode(UUID.self, forKey: NutritionWireKey("user_id"))
        collectionId = try c.decode(UUID.self, forKey: NutritionWireKey("collection_id"))
        foodId = try c.decode(UUID.self, forKey: NutritionWireKey("food_id"))
        servings = try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("servings")) ?? 1
        sortOrder = try c.decodeIfPresent(Int.self, forKey: NutritionWireKey("sort_order")) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: NutritionWireKey("created_at")) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: NutritionWireKey("updated_at")) ?? createdAt
    }

    func encode(to encoder: Encoder) throws { try encodeRow(to: encoder, forCloud: false) }

    func encodeRow(to encoder: Encoder, forCloud: Bool) throws {
        var c = encoder.container(keyedBy: NutritionWireKey.self)
        try c.encode(id, forKey: NutritionWireKey("id"))
        try c.encode(userId, forKey: NutritionWireKey("user_id"))
        try c.encode(collectionId, forKey: NutritionWireKey("collection_id"))
        try c.encode(foodId, forKey: NutritionWireKey("food_id"))
        try c.encode(servings, forKey: NutritionWireKey("servings"))
        try c.encode(sortOrder, forKey: NutritionWireKey("sort_order"))
        try c.encode(createdAt, forKey: NutritionWireKey("created_at"))
        try c.encode(updatedAt, forKey: NutritionWireKey("updated_at"))
    }
}

// MARK: - Loaded collection

/// A saved meal or recipe with its items and the foods they point at (what the Kitchen UI shows).
struct KitchenCollection: Identifiable, Equatable {
    var collection: FoodCollection
    var items: [FoodCollectionItem]
    /// Foods by id for the items whose food still exists.
    var foods: [UUID: NutritionFood]

    var id: UUID { collection.id }
    var kind: FoodCollectionKind { collection.kind }
    var name: String { collection.name }

    /// Items with their food, in order. Items whose food is missing are left out.
    var lines: [PlateItem] {
        items.sorted { $0.sortOrder != $1.sortOrder ? $0.sortOrder < $1.sortOrder : $0.createdAt < $1.createdAt }
            .compactMap { item in foods[item.foodId].map { PlateItem(food: $0, servings: item.servings) } }
    }

    /// Everything in the collection added up (all ingredients of a recipe, all items of a meal).
    var total: NutrientValues { RecipeMath.total(of: lines) }

    /// A recipe's values for one serving; for a meal the same as `total`.
    var perServing: NutrientValues {
        collection.kind == .recipe ? RecipeMath.perServing(lines: lines, servingsYield: collection.servingsYield) : total
    }

    /// The id of the food a recipe owns.
    var derivedFoodId: UUID? { collection.kind == .recipe ? collection.derivedFoodId : nil }
}

// MARK: - Recipe maths

enum RecipeMath {
    /// Sum of each ingredient's per-serving values times its servings (micros included; unknown stays unknown).
    static func total(of lines: [PlateItem]) -> NutrientValues {
        NutrientValues.total(lines.map { $0.food.nutrients.scaled(by: max(0, $0.servings)) })
    }

    /// Total divided by the number of servings the recipe makes (a yield <= 0 is treated as 1).
    static func perServing(lines: [PlateItem], servingsYield: Double) -> NutrientValues {
        total(of: lines).scaled(by: 1 / (servingsYield > 0 ? servingsYield : 1))
    }

    /// Weight of one serving: cooked weight divided by the yield. nil when no weight was given.
    static func servingGrams(cookedWeightGrams: Double?, servingsYield: Double) -> Double? {
        guard let cookedWeightGrams, cookedWeightGrams > 0, servingsYield > 0 else { return nil }
        return cookedWeightGrams / servingsYield
    }

    /// The food a recipe owns, with values recomputed. `existing` keeps id, favourite flag, last use and creation date.
    static func derivedFood(for collection: FoodCollection, lines: [PlateItem], existing: NutritionFood?,
                            now: Date) -> NutritionFood {
        let grams = servingGrams(cookedWeightGrams: collection.cookedWeightGrams, servingsYield: collection.servingsYield)
        return NutritionFood(
            id: collection.derivedFoodId, userId: collection.userId, name: collection.name, brand: nil,
            servingLabel: "1 serving", servingUnit: "serving", servingAmount: 1, servingGrams: grams,
            nutrients: perServing(lines: lines, servingsYield: collection.servingsYield), source: .recipe,
            isFavorite: existing?.isFavorite ?? false, lastUsedAt: existing?.lastUsedAt,
            createdAt: existing?.createdAt ?? now, updatedAt: now
        )
    }
}
