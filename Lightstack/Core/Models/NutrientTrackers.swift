import Foundation

/// A nutrient that can show as a tracker card on the Journal: water or one of the stored micros.
enum TrackedNutrient: Hashable, Codable, Identifiable {
    case water
    case micro(MicroKey)

    var id: String { storageKey }

    /// Stable text used for persistence ("water", "fiber", ...).
    var storageKey: String {
        switch self {
        case .water: return "water"
        case .micro(let key): return key.rawValue
        }
    }

    init?(storageKey: String) {
        if storageKey == "water" { self = .water; return }
        guard let key = MicroKey(rawValue: storageKey) else { return nil }
        self = .micro(key)
    }

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let value = TrackedNutrient(storageKey: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown nutrient \(text)"))
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageKey)
    }

    var displayName: String {
        switch self {
        case .water: return "Water"
        case .micro(let key):
            switch key {
            case .fiber: return "Fiber"
            case .sugar: return "Sugar"
            case .addedSugar: return "Added Sugar"
            case .satFat: return "Saturated Fat"
            case .transFat: return "Trans Fat"
            case .cholesterol: return "Cholesterol"
            case .sodium: return "Sodium"
            case .potassium: return "Potassium"
            case .calcium: return "Calcium"
            case .iron: return "Iron"
            case .vitaminD: return "Vitamin D"
            }
        }
    }

    /// Unit of the stored/target value (water targets are millilitres; show them with `WaterUnit`).
    var unit: String {
        switch self {
        case .water: return "ml"
        case .micro(let key): return key.unit
        }
    }

    /// Every nutrient a user can add: water first, then each micro.
    static var allCases: [TrackedNutrient] { [.water] + MicroKey.allCases.map { .micro($0) } }

    /// Today's amount from a day summary (nil when no logged food knows that micro).
    func amount(in summary: JournalDaySummary) -> Double? {
        switch self {
        case .water: return summary.waterMl
        case .micro(let key): return summary.totals.micros[key]
        }
    }
}

/// One tracker card: the nutrient and an optional daily target (ml for water, the micro's own unit otherwise).
struct NutrientTracker: Codable, Equatable, Identifiable {
    var nutrient: TrackedNutrient
    var dailyTarget: Double?
    var id: String { nutrient.storageKey }
}

/// Which extra nutrients the Journal shows as tracker cards. Local only (UserDefaults JSON, per user);
/// it does not sync in this phase. Defaults: water, fiber, sodium.
final class NutrientTrackerStore {
    static let defaultTrackers: [NutrientTracker] = [
        NutrientTracker(nutrient: .water, dailyTarget: nil),
        NutrientTracker(nutrient: .micro(.fiber), dailyTarget: nil),
        NutrientTracker(nutrient: .micro(.sodium), dailyTarget: nil)
    ]

    private let defaults: UserDefaults
    private let userId: UUID

    init(userId: UUID, defaults: UserDefaults = .standard) {
        self.userId = userId
        self.defaults = defaults
    }

    private var key: String { "nutrition.trackers.\(userId.uuidString)" }

    /// Ordered trackers (the defaults until the user changes them).
    var trackers: [NutrientTracker] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([NutrientTracker].self, from: data) else { return Self.defaultTrackers }
        return decoded
    }

    /// Nutrients not currently tracked.
    var available: [TrackedNutrient] {
        let used = Set(trackers.map(\.nutrient))
        return TrackedNutrient.allCases.filter { !used.contains($0) }
    }

    func save(_ trackers: [NutrientTracker]) {
        guard let data = try? JSONEncoder().encode(trackers) else { return }
        defaults.set(data, forKey: key)
    }

    func add(_ nutrient: TrackedNutrient, dailyTarget: Double? = nil) {
        var list = trackers
        guard !list.contains(where: { $0.nutrient == nutrient }) else { return }
        list.append(NutrientTracker(nutrient: nutrient, dailyTarget: dailyTarget))
        save(list)
    }

    func remove(_ nutrient: TrackedNutrient) {
        save(trackers.filter { $0.nutrient != nutrient })
    }

    /// nil or a non-positive value clears the target.
    func setTarget(_ target: Double?, for nutrient: TrackedNutrient) {
        var list = trackers
        guard let index = list.firstIndex(where: { $0.nutrient == nutrient }) else { return }
        list[index].dailyTarget = (target ?? 0) > 0 ? target : nil
        save(list)
    }

    func move(from source: Int, to destination: Int) {
        var list = trackers
        guard list.indices.contains(source), destination >= 0, destination < list.count else { return }
        list.insert(list.remove(at: source), at: destination)
        save(list)
    }
}
