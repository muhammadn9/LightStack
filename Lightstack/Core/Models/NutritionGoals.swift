import Foundation
import CoreData

// MARK: - Setup enums

/// What the user wants their weight to do.
enum NutritionGoal: String, Codable, CaseIterable {
    case lose, maintain, gain
}

/// Biological sex as used by the Mifflin-St Jeor equation.
enum NutritionSex: String, Codable, CaseIterable {
    case male, female
}

/// Four standard activity levels with the usual Mifflin-St Jeor multipliers.
enum NutritionActivityLevel: String, Codable, CaseIterable {
    case sedentary, lightlyActive, active, veryActive

    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .lightlyActive: return 1.375
        case .active: return 1.55
        case .veryActive: return 1.725
        }
    }
}

/// Body-weight display unit. Stored weights are always pounds; this is only a preference.
enum BodyWeightUnit: String, Codable, CaseIterable {
    case lb, kg

    static let lbPerKg = 2.2046226218

    func fromLbs(_ lbs: Double) -> Double { self == .kg ? lbs / Self.lbPerKg : lbs }
    func toLbs(_ value: Double) -> Double { self == .kg ? value * Self.lbPerKg : value }
}

// MARK: - Goal settings

/// The answers from the setup wizard. One row per user (deterministic id), synced.
/// Weights are pounds and height is inches; `unit` is only the display preference.
struct NutritionGoalSettings: NutritionRow, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    var goal: NutritionGoal
    var sex: NutritionSex
    var age: Int
    var heightInches: Double
    var currentWeightLbs: Double
    var targetWeightLbs: Double
    /// Magnitude in lb per week (always >= 0; the goal gives the direction). Maintain = 0.
    var weeklyRateLbs: Double
    var activityLevel: NutritionActivityLevel
    var liftsWeights: Bool
    var unit: BodyWeightUnit
    /// nil until the wizard has been finished.
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var isComplete: Bool { completedAt != nil }

    static func id(userId: UUID) -> UUID {
        DeterministicID.make(userId: userId, label: "nutrition-goal-settings")
    }

    /// A fresh, incomplete draft, prefilled from the profile where it has values.
    static func draft(userId: UUID, profile: UserProfile?, now: Date = Date()) -> NutritionGoalSettings {
        NutritionGoalSettings(
            id: id(userId: userId), userId: userId, goal: .maintain, sex: .male,
            age: profile?.age ?? 30, heightInches: profile?.heightInches ?? 70,
            currentWeightLbs: profile?.weightLbs ?? 170, targetWeightLbs: profile?.weightLbs ?? 170,
            weeklyRateLbs: 0, activityLevel: .lightlyActive, liftsWeights: true, unit: .lb,
            completedAt: nil, createdAt: now, updatedAt: now
        )
    }

    init(id: UUID, userId: UUID, goal: NutritionGoal, sex: NutritionSex, age: Int, heightInches: Double,
         currentWeightLbs: Double, targetWeightLbs: Double, weeklyRateLbs: Double,
         activityLevel: NutritionActivityLevel, liftsWeights: Bool, unit: BodyWeightUnit,
         completedAt: Date?, createdAt: Date, updatedAt: Date) {
        self.id = id; self.userId = userId; self.goal = goal; self.sex = sex; self.age = age
        self.heightInches = heightInches; self.currentWeightLbs = currentWeightLbs
        self.targetWeightLbs = targetWeightLbs; self.weeklyRateLbs = weeklyRateLbs
        self.activityLevel = activityLevel; self.liftsWeights = liftsWeights; self.unit = unit
        self.completedAt = completedAt; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    init(from entity: CDNutritionGoalSettings) {
        id = entity.id ?? UUID()
        userId = entity.userId ?? UUID()
        goal = NutritionGoal(rawValue: entity.goal ?? "") ?? .maintain
        sex = NutritionSex(rawValue: entity.sex ?? "") ?? .male
        age = Int(entity.age)
        heightInches = entity.heightInches
        currentWeightLbs = entity.currentWeightLbs
        targetWeightLbs = entity.targetWeightLbs
        weeklyRateLbs = entity.weeklyRateLbs
        activityLevel = NutritionActivityLevel(rawValue: entity.activityLevel ?? "") ?? .lightlyActive
        liftsWeights = entity.liftsWeights
        unit = BodyWeightUnit(rawValue: entity.unit ?? "") ?? .lb
        completedAt = entity.completedAt
        createdAt = entity.createdAt ?? Date()
        updatedAt = entity.updatedAt ?? Date()
    }

    func apply(to entity: CDNutritionGoalSettings) {
        entity.id = id; entity.userId = userId; entity.goal = goal.rawValue; entity.sex = sex.rawValue
        entity.age = Int64(age); entity.heightInches = heightInches
        entity.currentWeightLbs = currentWeightLbs; entity.targetWeightLbs = targetWeightLbs
        entity.weeklyRateLbs = weeklyRateLbs; entity.activityLevel = activityLevel.rawValue
        entity.liftsWeights = liftsWeights; entity.unit = unit.rawValue; entity.completedAt = completedAt
        entity.createdAt = createdAt; entity.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: NutritionWireKey.self)
        id = try c.decode(UUID.self, forKey: NutritionWireKey("id"))
        userId = try c.decode(UUID.self, forKey: NutritionWireKey("user_id"))
        goal = NutritionGoal(rawValue: try c.decodeIfPresent(String.self, forKey: NutritionWireKey("goal")) ?? "") ?? .maintain
        sex = NutritionSex(rawValue: try c.decodeIfPresent(String.self, forKey: NutritionWireKey("sex")) ?? "") ?? .male
        age = try c.decodeIfPresent(Int.self, forKey: NutritionWireKey("age")) ?? 30
        heightInches = try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("height_inches")) ?? 0
        currentWeightLbs = try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("current_weight_lbs")) ?? 0
        targetWeightLbs = try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("target_weight_lbs")) ?? 0
        weeklyRateLbs = try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("weekly_rate_lbs")) ?? 0
        activityLevel = NutritionActivityLevel(
            rawValue: try c.decodeIfPresent(String.self, forKey: NutritionWireKey("activity_level")) ?? "") ?? .lightlyActive
        liftsWeights = try c.decodeIfPresent(Bool.self, forKey: NutritionWireKey("lifts_weights")) ?? false
        unit = BodyWeightUnit(rawValue: try c.decodeIfPresent(String.self, forKey: NutritionWireKey("unit")) ?? "") ?? .lb
        completedAt = try c.decodeIfPresent(Date.self, forKey: NutritionWireKey("completed_at"))
        createdAt = try c.decodeIfPresent(Date.self, forKey: NutritionWireKey("created_at")) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: NutritionWireKey("updated_at")) ?? createdAt
    }

    func encode(to encoder: Encoder) throws { try encodeRow(to: encoder, forCloud: false) }

    func encodeRow(to encoder: Encoder, forCloud: Bool) throws {
        var c = encoder.container(keyedBy: NutritionWireKey.self)
        try c.encode(id, forKey: NutritionWireKey("id"))
        try c.encode(userId, forKey: NutritionWireKey("user_id"))
        try c.encode(goal.rawValue, forKey: NutritionWireKey("goal"))
        try c.encode(sex.rawValue, forKey: NutritionWireKey("sex"))
        try c.encode(age, forKey: NutritionWireKey("age"))
        try c.encode(heightInches, forKey: NutritionWireKey("height_inches"))
        try c.encode(currentWeightLbs, forKey: NutritionWireKey("current_weight_lbs"))
        try c.encode(targetWeightLbs, forKey: NutritionWireKey("target_weight_lbs"))
        try c.encode(weeklyRateLbs, forKey: NutritionWireKey("weekly_rate_lbs"))
        try c.encode(activityLevel.rawValue, forKey: NutritionWireKey("activity_level"))
        try c.encode(liftsWeights, forKey: NutritionWireKey("lifts_weights"))
        try c.encode(unit.rawValue, forKey: NutritionWireKey("unit"))
        if let completedAt { try c.encode(completedAt, forKey: NutritionWireKey("completed_at")) }
        else { try c.encodeNil(forKey: NutritionWireKey("completed_at")) }
        try c.encode(createdAt, forKey: NutritionWireKey("created_at"))
        try c.encode(updatedAt, forKey: NutritionWireKey("updated_at"))
    }
}

// MARK: - Calculator

/// Result of `NutritionCalculator.calculate`.
struct GoalCalculation: Equatable {
    var bmr: Double
    var tdee: Double
    /// Rate (lb/week, magnitude) actually applied after clamping and the calorie floor.
    var weeklyRateLbs: Double
    /// Rate the calculator suggests for this person and goal.
    var recommendedRateLbs: Double
    var minRateLbs: Double
    var maxRateLbs: Double
    /// True when the calorie floor raised the target (the applied rate is then gentler than asked).
    var flooredByMinimum: Bool
    var kcal: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var proteinPercent: Int
    var carbsPercent: Int
    var fatPercent: Int
    /// Date the target weight is reached at the applied rate; nil for maintain, a wrong-way goal or a zero rate.
    var projectedGoalDate: Date?
}

/// Pure calorie and macro maths for the setup wizard. No I/O.
///
/// Rules:
/// - BMR: Mifflin-St Jeor (10 kg + 6.25 cm - 5 age + 5 male / -161 female). TDEE = BMR x activity multiplier.
/// - Rate: 3500 kcal per lb, so rate x 500 kcal/day. Magnitude is clamped per goal:
///   lose 0.25 ... min(2.0, 1% of bodyweight) lb/week (at least 0.25); gain 0.1 ... min(1.0, 0.5% of bodyweight).
///   Recommended: lose 0.75% of bodyweight, gain 0.25% (gain capped 0.25-0.5 lb), rounded to 0.25 lb. Maintain = 0.
/// - Calorie floor: 1200 (female) / 1500 (male). The rate is recomputed when the floor kicks in.
/// - Protein: 0.8 g/lb, or 1.0 g/lb when lifting weights. The reference weight is the target weight when losing
///   (and lighter than now), otherwise current weight. Capped at 35% of calories.
/// - Fat: 27% of calories. Carbs: the remainder (never negative). Grams are whole numbers; kcal is derived
///   from the rounded macros (4/4/9) so a plan built from the result is self-consistent.
enum NutritionCalculator {
    static let kcalPerLb = 3500.0
    static let fatShare = 0.27
    static let maxProteinShare = 0.35
    static let maxLossRate = 2.0
    static let maxGainRate = 1.0
    static let minLossRate = 0.25
    static let minGainRate = 0.1
    static let projectionCapWeeks = 520.0

    static func calorieFloor(for sex: NutritionSex) -> Double { sex == .female ? 1200 : 1500 }

    static func bmr(sex: NutritionSex, age: Int, heightInches: Double, weightLbs: Double) -> Double {
        let kg = weightLbs / BodyWeightUnit.lbPerKg
        let cm = heightInches * 2.54
        return 10 * kg + 6.25 * cm - 5 * Double(age) + (sex == .male ? 5 : -161)
    }

    static func tdee(bmr: Double, activity: NutritionActivityLevel) -> Double { bmr * activity.multiplier }

    /// (min, max) weekly rate magnitude for the goal at this bodyweight.
    static func rateRange(goal: NutritionGoal, weightLbs: Double) -> (min: Double, max: Double) {
        switch goal {
        case .maintain: return (0, 0)
        case .lose: return (minLossRate, max(minLossRate, min(maxLossRate, weightLbs * 0.01)))
        case .gain: return (minGainRate, max(minGainRate, min(maxGainRate, weightLbs * 0.005)))
        }
    }

    static func recommendedRate(goal: NutritionGoal, weightLbs: Double) -> Double {
        let range = rateRange(goal: goal, weightLbs: weightLbs)
        switch goal {
        case .maintain: return 0
        case .lose:
            return min(max(roundToQuarter(weightLbs * 0.0075), range.min), range.max)
        case .gain:
            return min(max(roundToQuarter(weightLbs * 0.0025), 0.25), min(0.5, range.max))
        }
    }

    static func clampRate(_ rate: Double, goal: NutritionGoal, weightLbs: Double) -> Double {
        guard goal != .maintain else { return 0 }
        let range = rateRange(goal: goal, weightLbs: weightLbs)
        return min(max(rate, range.min), range.max)
    }

    static func calculate(_ s: NutritionGoalSettings, now: Date = Date(), calendar: Calendar = .current) -> GoalCalculation {
        let weight = max(s.currentWeightLbs, 1)
        let bmr = bmr(sex: s.sex, age: s.age, heightInches: s.heightInches, weightLbs: weight)
        let tdee = tdee(bmr: bmr, activity: s.activityLevel)
        let range = rateRange(goal: s.goal, weightLbs: weight)
        let recommended = recommendedRate(goal: s.goal, weightLbs: weight)
        var rate = clampRate(s.weeklyRateLbs, goal: s.goal, weightLbs: weight)

        let sign: Double = s.goal == .lose ? -1 : (s.goal == .gain ? 1 : 0)
        var kcal = tdee + sign * rate * kcalPerLb / 7
        let floor = calorieFloor(for: s.sex)
        var floored = false
        if kcal < floor {
            kcal = floor
            floored = true
            rate = s.goal == .lose ? max(0, (tdee - floor) * 7 / kcalPerLb) : rate
        }
        kcal = (kcal / 10).rounded() * 10

        let referenceWeight: Double
        if s.goal == .lose, s.targetWeightLbs > 0, s.targetWeightLbs < weight { referenceWeight = s.targetWeightLbs }
        else { referenceWeight = weight }
        var protein = referenceWeight * (s.liftsWeights ? 1.0 : 0.8)
        protein = min(protein, kcal * maxProteinShare / NutritionMath.kcalPerGramProtein)
        protein = protein.rounded()
        let fat = (kcal * fatShare / NutritionMath.kcalPerGramFat).rounded()
        let carbs = max(0, ((kcal - protein * NutritionMath.kcalPerGramProtein - fat * NutritionMath.kcalPerGramFat)
                            / NutritionMath.kcalPerGramCarbs).rounded())
        let derived = NutritionMath.derivedKcal(protein: protein, carbs: carbs, fat: fat)
        let pct: (Double) -> Int = { derived > 0 ? Int(($0 / derived * 100).rounded()) : 0 }

        return GoalCalculation(
            bmr: bmr, tdee: tdee, weeklyRateLbs: rate, recommendedRateLbs: recommended,
            minRateLbs: range.min, maxRateLbs: range.max, flooredByMinimum: floored, kcal: derived,
            proteinGrams: protein, carbsGrams: carbs, fatGrams: fat,
            proteinPercent: pct(protein * NutritionMath.kcalPerGramProtein),
            carbsPercent: pct(carbs * NutritionMath.kcalPerGramCarbs),
            fatPercent: pct(fat * NutritionMath.kcalPerGramFat),
            projectedGoalDate: projectedDate(settings: s, rate: rate, now: now, calendar: calendar)
        )
    }

    static func projectedDate(settings s: NutritionGoalSettings, rate: Double, now: Date, calendar: Calendar) -> Date? {
        guard rate > 0, s.goal != .maintain, s.targetWeightLbs > 0 else { return nil }
        let delta = s.goal == .lose ? s.currentWeightLbs - s.targetWeightLbs : s.targetWeightLbs - s.currentWeightLbs
        guard delta > 0 else { return nil }
        let weeks = min(delta / rate, projectionCapWeeks)
        return calendar.date(byAdding: .day, value: Int((weeks * 7).rounded(.up)), to: now.startOfDay)
    }

    private static func roundToQuarter(_ v: Double) -> Double { (v * 4).rounded() / 4 }
}

// MARK: - Weekday plans

/// Weekday bitmask helpers: bit 0 = Sunday ... bit 6 = Saturday (Calendar weekday 1...7 minus 1).
enum WeekdayMask {
    static let all = 0b111_1111
    static let weekdays = 0b011_1110   // Mon-Fri
    static let weekend = 0b100_0001    // Sun + Sat

    /// `weekday` is Calendar's 1 (Sunday) ... 7 (Saturday).
    static func bit(weekday: Int) -> Int { 1 << ((weekday - 1) % 7) }
    static func mask(weekdays: [Int]) -> Int { weekdays.reduce(0) { $0 | bit(weekday: $1) } }
    static func contains(_ mask: Int, weekday: Int) -> Bool { mask & bit(weekday: weekday) != 0 }
    static func weekdays(in mask: Int) -> [Int] { (1...7).filter { contains(mask, weekday: $0) } }
    static func weekday(of date: Date, calendar: Calendar = .current) -> Int { calendar.component(.weekday, from: date) }
}

/// A macro plan that covers certain weekdays (for example training days and rest days).
/// Soft-deleted via `isArchived`; archived plans never apply and free their days.
struct NutritionPlan: NutritionRow, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    var name: String
    var weekdayMask: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var kcal: Double
    var kcalOverridden: Bool
    var sortOrder: Int
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    var derivedKcal: Double { NutritionMath.derivedKcal(protein: protein, carbs: carbs, fat: fat) }
    var kcalMismatch: Double { kcal - derivedKcal }
    var weekdays: [Int] { WeekdayMask.weekdays(in: weekdayMask) }
    func covers(weekday: Int) -> Bool { !isArchived && WeekdayMask.contains(weekdayMask, weekday: weekday) }

    /// The plan as a daily target for `day`, so existing target/remaining code keeps working.
    func asTarget(on day: Date) -> NutritionTarget {
        NutritionTarget(id: id, userId: userId, effectiveDate: day.startOfDay, kcal: kcal, protein: protein,
                        carbs: carbs, fat: fat, kcalOverridden: kcalOverridden, createdAt: createdAt, updatedAt: updatedAt)
    }

    init(id: UUID, userId: UUID, name: String, weekdayMask: Int, protein: Double, carbs: Double, fat: Double,
         kcal: Double, kcalOverridden: Bool, sortOrder: Int, isArchived: Bool, createdAt: Date, updatedAt: Date) {
        self.id = id; self.userId = userId; self.name = name; self.weekdayMask = weekdayMask
        self.protein = protein; self.carbs = carbs; self.fat = fat; self.kcal = kcal
        self.kcalOverridden = kcalOverridden; self.sortOrder = sortOrder; self.isArchived = isArchived
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    init(from entity: CDNutritionPlan) {
        id = entity.id ?? UUID()
        userId = entity.userId ?? UUID()
        name = entity.name ?? ""
        weekdayMask = Int(entity.weekdayMask)
        protein = entity.protein; carbs = entity.carbs; fat = entity.fat; kcal = entity.kcal
        kcalOverridden = entity.kcalOverridden
        sortOrder = Int(entity.sortOrder)
        isArchived = entity.isArchived
        createdAt = entity.createdAt ?? Date()
        updatedAt = entity.updatedAt ?? Date()
    }

    func apply(to entity: CDNutritionPlan) {
        entity.id = id; entity.userId = userId; entity.name = name; entity.weekdayMask = Int64(weekdayMask)
        entity.protein = protein; entity.carbs = carbs; entity.fat = fat; entity.kcal = kcal
        entity.kcalOverridden = kcalOverridden; entity.sortOrder = Int64(sortOrder)
        entity.isArchived = isArchived; entity.createdAt = createdAt; entity.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: NutritionWireKey.self)
        id = try c.decode(UUID.self, forKey: NutritionWireKey("id"))
        userId = try c.decode(UUID.self, forKey: NutritionWireKey("user_id"))
        name = try c.decodeIfPresent(String.self, forKey: NutritionWireKey("name")) ?? ""
        weekdayMask = try c.decodeIfPresent(Int.self, forKey: NutritionWireKey("weekday_mask")) ?? 0
        protein = try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("protein_g")) ?? 0
        carbs = try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("carbs_g")) ?? 0
        fat = try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("fat_g")) ?? 0
        kcal = try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("kcal")) ?? 0
        kcalOverridden = try c.decodeIfPresent(Bool.self, forKey: NutritionWireKey("kcal_overridden")) ?? false
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
        try c.encode(weekdayMask, forKey: NutritionWireKey("weekday_mask"))
        try c.encode(protein, forKey: NutritionWireKey("protein_g"))
        try c.encode(carbs, forKey: NutritionWireKey("carbs_g"))
        try c.encode(fat, forKey: NutritionWireKey("fat_g"))
        try c.encode(kcal, forKey: NutritionWireKey("kcal"))
        try c.encode(kcalOverridden, forKey: NutritionWireKey("kcal_overridden"))
        try c.encode(sortOrder, forKey: NutritionWireKey("sort_order"))
        try c.encode(isArchived, forKey: NutritionWireKey("is_archived"))
        try c.encode(createdAt, forKey: NutritionWireKey("created_at"))
        try c.encode(updatedAt, forKey: NutritionWireKey("updated_at"))
    }
}

/// Pure resolution of "what is the target on this day".
enum NutritionPlanResolver {

    /// The active plan covering `day`'s weekday. If two plans overlap (two devices edited at once), the most
    /// recently edited wins, then the larger id, so every device picks the same one.
    static func plan(in plans: [NutritionPlan], on day: Date, calendar: Calendar = .current) -> NutritionPlan? {
        let weekday = WeekdayMask.weekday(of: day, calendar: calendar)
        return plans.filter { $0.covers(weekday: weekday) }.max { a, b in
            a.updatedAt != b.updatedAt ? a.updatedAt < b.updatedAt : a.id.uuidString < b.id.uuidString
        }
    }

    /// Weekday plan first; a day with no plan falls back to the effective-date target history.
    static func target(plans: [NutritionPlan], history: [NutritionTarget], on day: Date,
                       calendar: Calendar = .current) -> NutritionTarget? {
        if let plan = plan(in: plans, on: day, calendar: calendar) { return plan.asTarget(on: day) }
        return NutritionMath.target(in: history, on: day)
    }

    /// Weekdays (1...7) not covered by any active plan.
    static func uncoveredWeekdays(in plans: [NutritionPlan]) -> [Int] {
        let covered = plans.filter { !$0.isArchived }.reduce(0) { $0 | $1.weekdayMask }
        return (1...7).filter { !WeekdayMask.contains(covered, weekday: $0) }
    }
}
