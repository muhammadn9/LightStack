import Foundation
import CoreData
import CryptoKit

// MARK: - Deterministic ids

enum DeterministicID {
    /// A stable UUID derived from a user id and a label (SHA-256, version/variant bits set), so two devices
    /// that create "the same" record offline end up with the same row instead of duplicates.
    static func make(userId: UUID, label: String) -> UUID {
        let digest = SHA256.hash(data: Data((userId.uuidString + "|" + label).utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let tuple: uuid_t = (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                             bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: tuple)
    }
}

// MARK: - Meal slot

/// A configurable daily meal (Breakfast, Lunch, ...). Never hard-deleted: archiving keeps old entries attached.
struct MealSlot: NutritionRow, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    var name: String
    var sortOrder: Int
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    static let defaultNames = ["Breakfast", "Lunch", "Dinner", "Snack"]
    /// Seeded defaults carry this timestamp, so any real edit (on any device) is newer than an untouched default.
    static let seedStamp = Date(timeIntervalSince1970: 0)

    /// True for a default that nobody has edited yet.
    var isUntouchedSeed: Bool { updatedAt <= Self.seedStamp }

    /// The default slots with ids derived from the user id: every device seeds the same rows.
    static func defaults(userId: UUID) -> [MealSlot] {
        defaultNames.enumerated().map { index, name in
            MealSlot(id: DeterministicID.make(userId: userId, label: "meal-slot-default-\(index)"), userId: userId,
                     name: name, sortOrder: index, isArchived: false, createdAt: seedStamp, updatedAt: seedStamp)
        }
    }

    init(id: UUID, userId: UUID, name: String, sortOrder: Int, isArchived: Bool, createdAt: Date, updatedAt: Date) {
        self.id = id; self.userId = userId; self.name = name; self.sortOrder = sortOrder
        self.isArchived = isArchived; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    init(from entity: CDMealSlot) {
        id = entity.id ?? UUID()
        userId = entity.userId ?? UUID()
        name = entity.name ?? ""
        sortOrder = Int(entity.sortOrder)
        isArchived = entity.isArchived
        createdAt = entity.createdAt ?? Date()
        updatedAt = entity.updatedAt ?? Date()
    }

    func apply(to entity: CDMealSlot) {
        entity.id = id; entity.userId = userId; entity.name = name; entity.sortOrder = Int64(sortOrder)
        entity.isArchived = isArchived; entity.createdAt = createdAt; entity.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: NutritionWireKey.self)
        id = try c.decode(UUID.self, forKey: NutritionWireKey("id"))
        userId = try c.decode(UUID.self, forKey: NutritionWireKey("user_id"))
        name = try c.decodeIfPresent(String.self, forKey: NutritionWireKey("name")) ?? ""
        sortOrder = try c.decodeIfPresent(Int.self, forKey: NutritionWireKey("sort_order")) ?? 0
        isArchived = try c.decodeIfPresent(Bool.self, forKey: NutritionWireKey("is_archived")) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: NutritionWireKey("created_at")) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: NutritionWireKey("updated_at")) ?? createdAt
    }

    func encode(to encoder: Encoder) throws { try encodeRow(to: encoder, forCloud: false) }

    func encodeRow(to encoder: Encoder, forCloud: Bool) throws {
        var c = encoder.container(keyedBy: NutritionWireKey.self)
        try c.encode(id, forKey: NutritionWireKey("id"))
        try c.encode(userId, forKey: NutritionWireKey("user_id"))
        try c.encode(name, forKey: NutritionWireKey("name"))
        try c.encode(sortOrder, forKey: NutritionWireKey("sort_order"))
        try c.encode(isArchived, forKey: NutritionWireKey("is_archived"))
        try c.encode(createdAt, forKey: NutritionWireKey("created_at"))
        try c.encode(updatedAt, forKey: NutritionWireKey("updated_at"))
    }
}

// MARK: - Water

/// One water log. `amountMl` is the canonical unit; the display unit is a preference (`WaterUnit`).
struct WaterEntry: NutritionRow, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    /// Start of the local calendar day.
    var date: Date
    var amountMl: Double
    var createdAt: Date
    var updatedAt: Date

    static func make(userId: UUID, date: Date, amountMl: Double, now: Date = Date()) -> WaterEntry {
        WaterEntry(id: UUID(), userId: userId, date: date.startOfDay, amountMl: amountMl, createdAt: now, updatedAt: now)
    }

    init(id: UUID, userId: UUID, date: Date, amountMl: Double, createdAt: Date, updatedAt: Date) {
        self.id = id; self.userId = userId; self.date = date; self.amountMl = amountMl
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    init(from entity: CDWaterEntry) {
        id = entity.id ?? UUID()
        userId = entity.userId ?? UUID()
        date = entity.date ?? Date().startOfDay
        amountMl = entity.amountMl
        createdAt = entity.createdAt ?? Date()
        updatedAt = entity.updatedAt ?? Date()
    }

    func apply(to entity: CDWaterEntry) {
        entity.id = id; entity.userId = userId; entity.date = date.startOfDay; entity.amountMl = amountMl
        entity.createdAt = createdAt; entity.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: NutritionWireKey.self)
        id = try c.decode(UUID.self, forKey: NutritionWireKey("id"))
        userId = try c.decode(UUID.self, forKey: NutritionWireKey("user_id"))
        date = try RemoteDate.decodeDay(c, NutritionWireKey("date"))
        amountMl = try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("amount_ml")) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: NutritionWireKey("created_at")) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: NutritionWireKey("updated_at")) ?? createdAt
    }

    func encode(to encoder: Encoder) throws { try encodeRow(to: encoder, forCloud: false) }

    func encodeRow(to encoder: Encoder, forCloud: Bool) throws {
        var c = encoder.container(keyedBy: NutritionWireKey.self)
        try c.encode(id, forKey: NutritionWireKey("id"))
        try c.encode(userId, forKey: NutritionWireKey("user_id"))
        if forCloud { try c.encode(RemoteDate.dayString(date), forKey: NutritionWireKey("date")) }
        else { try c.encode(date, forKey: NutritionWireKey("date")) }
        try c.encode(amountMl, forKey: NutritionWireKey("amount_ml"))
        try c.encode(createdAt, forKey: NutritionWireKey("created_at"))
        try c.encode(updatedAt, forKey: NutritionWireKey("updated_at"))
    }
}

/// Display unit for water. Stored values are always millilitres; this is only a preference.
enum WaterUnit: String, CaseIterable {
    case flOz, ml

    /// UserDefaults / @AppStorage key.
    static let storageKey = "nutritionWaterUnit"
    static let mlPerFlOz = 29.5735

    static func current(defaults: UserDefaults = .standard) -> WaterUnit {
        WaterUnit(rawValue: defaults.string(forKey: storageKey) ?? "") ?? .flOz
    }

    static func setCurrent(_ unit: WaterUnit, defaults: UserDefaults = .standard) {
        defaults.set(unit.rawValue, forKey: storageKey)
    }

    var label: String { self == .flOz ? "fl oz" : "ml" }

    func fromMl(_ ml: Double) -> Double { self == .flOz ? ml / Self.mlPerFlOz : ml }
    func toMl(_ value: Double) -> Double { self == .flOz ? value * Self.mlPerFlOz : value }

    /// "64 fl oz" / "1893 ml" (whole numbers).
    func format(ml: Double) -> String { "\(Int(fromMl(ml).rounded())) \(label)" }
}

// MARK: - Day note

/// One note per local day. The id is derived from (user, day), so two devices never create two notes for a day.
/// Clearing the text keeps the row (with empty text) rather than deleting it.
struct DayNote: NutritionRow, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    /// Start of the local calendar day.
    var date: Date
    var text: String
    var createdAt: Date
    var updatedAt: Date

    static func id(userId: UUID, date: Date) -> UUID {
        DeterministicID.make(userId: userId, label: "day-note-\(RemoteDate.dayString(date))")
    }

    init(id: UUID, userId: UUID, date: Date, text: String, createdAt: Date, updatedAt: Date) {
        self.id = id; self.userId = userId; self.date = date; self.text = text
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    init(from entity: CDDayNote) {
        id = entity.id ?? UUID()
        userId = entity.userId ?? UUID()
        date = entity.date ?? Date().startOfDay
        text = entity.text ?? ""
        createdAt = entity.createdAt ?? Date()
        updatedAt = entity.updatedAt ?? Date()
    }

    func apply(to entity: CDDayNote) {
        entity.id = id; entity.userId = userId; entity.date = date.startOfDay; entity.text = text
        entity.createdAt = createdAt; entity.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: NutritionWireKey.self)
        id = try c.decode(UUID.self, forKey: NutritionWireKey("id"))
        userId = try c.decode(UUID.self, forKey: NutritionWireKey("user_id"))
        date = try RemoteDate.decodeDay(c, NutritionWireKey("date"))
        text = try c.decodeIfPresent(String.self, forKey: NutritionWireKey("text")) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: NutritionWireKey("created_at")) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: NutritionWireKey("updated_at")) ?? createdAt
    }

    func encode(to encoder: Encoder) throws { try encodeRow(to: encoder, forCloud: false) }

    func encodeRow(to encoder: Encoder, forCloud: Bool) throws {
        var c = encoder.container(keyedBy: NutritionWireKey.self)
        try c.encode(id, forKey: NutritionWireKey("id"))
        try c.encode(userId, forKey: NutritionWireKey("user_id"))
        if forCloud { try c.encode(RemoteDate.dayString(date), forKey: NutritionWireKey("date")) }
        else { try c.encode(date, forKey: NutritionWireKey("date")) }
        try c.encode(text, forKey: NutritionWireKey("text"))
        try c.encode(createdAt, forKey: NutritionWireKey("created_at"))
        try c.encode(updatedAt, forKey: NutritionWireKey("updated_at"))
    }
}

// MARK: - Day summary

/// One meal on a day: its entries and their totals. `slot` is nil for entries with no (or an unknown) meal.
struct MealSummary: Equatable, Identifiable {
    var slot: MealSlot?
    var entries: [FoodEntry]
    var totals: NutrientValues
    var id: UUID { slot?.id ?? Self.unassignedId }
    static let unassignedId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

/// Everything the Journal shows for one day, computed from one pass over that day's rows.
struct JournalDaySummary: Equatable {
    var date: Date
    var entries: [FoodEntry]
    /// Calories, macros and every micro, overall.
    var totals: NutrientValues
    var waterMl: Double
    /// Active meal slots in order (each present even when empty), then archived slots that hold entries.
    var meals: [MealSummary]
    /// Entries with no meal slot (legacy) or whose slot no longer exists.
    var unassigned: MealSummary
    var target: NutritionTarget?
    var remaining: MacroRemaining?
    var note: DayNote?

    func meal(for slotId: UUID) -> MealSummary? { meals.first { $0.slot?.id == slotId } }
}

enum JournalDaySummaryBuilder {
    static func build(date: Date, entries: [FoodEntry], slots: [MealSlot], water: [WaterEntry],
                      target: NutritionTarget?, note: DayNote?) -> JournalDaySummary {
        let ordered = slots.sorted { $0.sortOrder != $1.sortOrder ? $0.sortOrder < $1.sortOrder : $0.createdAt < $1.createdAt }
        let slotIds = Set(ordered.map(\.id))
        var bySlot: [UUID: [FoodEntry]] = [:]
        var loose: [FoodEntry] = []
        for entry in entries {
            if let id = entry.mealSlotId, slotIds.contains(id) { bySlot[id, default: []].append(entry) } else { loose.append(entry) }
        }
        let active = ordered.filter { !$0.isArchived }
        let archivedWithEntries = ordered.filter { $0.isArchived && !(bySlot[$0.id] ?? []).isEmpty }
        let meals = (active + archivedWithEntries).map { slot -> MealSummary in
            let items = bySlot[slot.id] ?? []
            return MealSummary(slot: slot, entries: items, totals: NutritionMath.totals(of: items))
        }
        let totals = NutritionMath.totals(of: entries)
        return JournalDaySummary(
            date: date, entries: entries, totals: totals, waterMl: water.reduce(0) { $0 + $1.amountMl }, meals: meals,
            unassigned: MealSummary(slot: nil, entries: loose, totals: NutritionMath.totals(of: loose)),
            target: target, remaining: target.map { NutritionMath.remaining(target: $0, totals: totals) }, note: note
        )
    }
}

/// One item of a multi-select "plate": a saved food and how many servings.
struct PlateItem {
    var food: NutritionFood
    var servings: Double
    init(food: NutritionFood, servings: Double = 1) { self.food = food; self.servings = servings }
}
