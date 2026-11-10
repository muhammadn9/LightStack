import Foundation
import CoreData

// MARK: - Body weight unit preference

extension BodyWeightUnit {
    /// The app-wide weight preference (Settings > Weight Unit, `@AppStorage("weightUnit")`, "lbs" or "kg").
    /// The gym side already stores that preference; nutrition reads the same one.
    static let preferenceKey = "weightUnit"

    static func current(defaults: UserDefaults = .standard) -> BodyWeightUnit {
        defaults.string(forKey: preferenceKey) == "kg" ? .kg : .lb
    }

    var label: String { rawValue }
}

// MARK: - Weigh-in

/// One body-weight log per user per local day. `weightLbs` is canonical; kg/lb is a display preference only.
/// Ids are random (not derived from the day): a deterministic id would collide with the tombstone left by an
/// earlier delete of the same day. Same-day uniqueness is enforced locally (logging again updates the day's
/// row) and in the cloud by UNIQUE (user_id, date) with an upsert on that pair.
struct WeighIn: NutritionRow, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    /// Start of the local calendar day.
    var date: Date
    var weightLbs: Double
    var createdAt: Date
    var updatedAt: Date

    static func make(userId: UUID, date: Date, weightLbs: Double, now: Date = Date()) -> WeighIn {
        WeighIn(id: UUID(), userId: userId, date: date.startOfDay, weightLbs: weightLbs, createdAt: now, updatedAt: now)
    }

    init(id: UUID, userId: UUID, date: Date, weightLbs: Double, createdAt: Date, updatedAt: Date) {
        self.id = id; self.userId = userId; self.date = date; self.weightLbs = weightLbs
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    init(from entity: CDWeighIn) {
        id = entity.id ?? UUID()
        userId = entity.userId ?? UUID()
        date = entity.date ?? Date().startOfDay
        weightLbs = entity.weightLbs
        createdAt = entity.createdAt ?? Date()
        updatedAt = entity.updatedAt ?? Date()
    }

    func apply(to entity: CDWeighIn) {
        entity.id = id; entity.userId = userId; entity.date = date.startOfDay; entity.weightLbs = weightLbs
        entity.createdAt = createdAt; entity.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: NutritionWireKey.self)
        id = try c.decode(UUID.self, forKey: NutritionWireKey("id"))
        userId = try c.decode(UUID.self, forKey: NutritionWireKey("user_id"))
        date = try RemoteDate.decodeDay(c, NutritionWireKey("date"))
        weightLbs = try c.decodeIfPresent(Double.self, forKey: NutritionWireKey("weight_lbs")) ?? 0
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
        try c.encode(weightLbs, forKey: NutritionWireKey("weight_lbs"))
        try c.encode(createdAt, forKey: NutritionWireKey("created_at"))
        try c.encode(updatedAt, forKey: NutritionWireKey("updated_at"))
    }
}

// MARK: - Dashboard value types

/// One day of the week strip: what was eaten and the target in force that day (nil = no target set).
struct DashboardDay: Equatable, Identifiable {
    var date: Date
    var totals: NutrientValues
    var target: NutritionTarget?
    var entryCount: Int
    var id: Date { date }
    var hasLog: Bool { entryCount > 0 }
}

/// One cell of the 30-day food-log grid.
struct FoodLogDay: Equatable, Identifiable {
    var date: Date
    var hasLog: Bool
    var id: Date { date }
}

/// One cell of the 30-day weigh-in grid.
struct WeighInDay: Equatable, Identifiable {
    var date: Date
    var hasWeighIn: Bool
    var id: Date { date }
}

/// Daily averages over LOGGED days only (a day without any entry is "not tracked", not "zero calories").
struct RangeSummary: Equatable {
    /// Length of the window in days (28 or 90).
    var days: Int
    var loggedDays: Int
    var avgKcal: Double
    var avgProtein: Double
    var avgCarbs: Double
    var avgFat: Double
    /// Logged days whose calories were within `NutritionDashboardStats.onTargetTolerance` of that day's target.
    var daysOnTarget: Int
    /// Logged days that had a target to compare against (the denominator for `daysOnTarget`).
    var loggedDaysWithTarget: Int

    static func empty(days: Int) -> RangeSummary {
        RangeSummary(days: days, loggedDays: 0, avgKcal: 0, avgProtein: 0, avgCarbs: 0, avgFat: 0,
                     daysOnTarget: 0, loggedDaysWithTarget: 0)
    }
}

// MARK: - Dashboard stats (pure)

/// Dashboard numbers computed from food entries, targets/plans and weigh-ins. No I/O, no clock: every function
/// takes its reference date, so tests are deterministic.
struct NutritionDashboardStats {
    /// A day counts as "on target" when its calories are within this fraction of the day's target (10%).
    static let onTargetTolerance = 0.10
    static let gridDays = 30

    let entries: [FoodEntry]
    let plans: [NutritionPlan]
    let history: [NutritionTarget]
    let weighIns: [WeighIn]
    let calendar: Calendar
    /// Every day with at least one entry. Defaults to the days of `entries`; pass a wider set (all history)
    /// when `entries` only covers a window, so streaks can look further back.
    let loggedDays: Set<Date>
    private let entriesByDay: [Date: [FoodEntry]]
    private let weighInByDay: [Date: WeighIn]

    init(entries: [FoodEntry], plans: [NutritionPlan], history: [NutritionTarget], weighIns: [WeighIn],
         loggedDays: Set<Date>? = nil, calendar: Calendar = .current) {
        self.entries = entries
        self.plans = plans
        self.history = history
        self.weighIns = weighIns
        self.calendar = calendar
        var grouped: [Date: [FoodEntry]] = [:]
        for entry in entries { grouped[calendar.startOfDay(for: entry.date), default: []].append(entry) }
        entriesByDay = grouped
        self.loggedDays = (loggedDays ?? Set(grouped.keys)).union(grouped.keys)
        var byDay: [Date: WeighIn] = [:]
        for weighIn in weighIns {
            let day = calendar.startOfDay(for: weighIn.date)
            if let existing = byDay[day], existing.updatedAt >= weighIn.updatedAt { continue }
            byDay[day] = weighIn
        }
        weighInByDay = byDay
    }

    private func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }
    private func shift(_ date: Date, by days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(Double(days) * 86_400)
    }

    private func target(on day: Date) -> NutritionTarget? {
        NutritionPlanResolver.target(plans: plans, history: history, on: day, calendar: calendar)
    }

    private func dashboardDay(_ date: Date) -> DashboardDay {
        let start = day(date)
        let items = entriesByDay[start] ?? []
        return DashboardDay(date: start, totals: NutritionMath.totals(of: items), target: target(on: start),
                            entryCount: items.count)
    }

    // MARK: Week

    /// The 7 days of the week containing `date`, first day first. `weekStartsOn` is Calendar's weekday number
    /// (1 = Sunday, the default). Each day carries its totals and the target of THAT weekday's plan.
    func weekDays(containing date: Date, weekStartsOn: Int = 1) -> [DashboardDay] {
        let anchor = day(date)
        let weekday = calendar.component(.weekday, from: anchor)
        let back = ((weekday - weekStartsOn) % 7 + 7) % 7
        let start = shift(anchor, by: -back)
        return (0..<7).map { dashboardDay(shift(start, by: $0)) }
    }

    // MARK: Grids

    /// `days` cells ending on `date` (inclusive), oldest first.
    func foodLogGrid(endingOn date: Date, days: Int = NutritionDashboardStats.gridDays) -> [FoodLogDay] {
        let end = day(date)
        return (0..<max(0, days)).map { index in
            let d = shift(end, by: -(days - 1 - index))
            return FoodLogDay(date: d, hasLog: loggedDays.contains(d))
        }
    }

    func weighInGrid(endingOn date: Date, days: Int = NutritionDashboardStats.gridDays) -> [WeighInDay] {
        let end = day(date)
        return (0..<max(0, days)).map { index in
            let d = shift(end, by: -(days - 1 - index))
            return WeighInDay(date: d, hasWeighIn: weighInByDay[d] != nil)
        }
    }

    // MARK: Streaks

    /// Consecutive logged days ending today, or ending yesterday when today has no entry yet (the day is not
    /// over, so it does not break the streak). 0 when neither day is logged.
    func currentLogStreak(asOf today: Date) -> Int {
        let start = day(today)
        var cursor = loggedDays.contains(start) ? start : shift(start, by: -1)
        var count = 0
        while loggedDays.contains(cursor) {
            count += 1
            cursor = shift(cursor, by: -1)
        }
        return count
    }

    /// The longest run of consecutive logged days anywhere in the history.
    var bestLogStreak: Int {
        var best = 0
        var run = 0
        var previous: Date?
        for d in loggedDays.sorted() {
            if let previous, shift(previous, by: 1) == d { run += 1 } else { run = 1 }
            best = max(best, run)
            previous = d
        }
        return best
    }

    // MARK: Weight

    /// Weigh-ins from the last `days` days ending on `date`, oldest first (one per day).
    func weighIns(overDays days: Int, endingOn date: Date) -> [WeighIn] {
        let end = day(date)
        let start = shift(end, by: -(max(1, days) - 1))
        return weighInByDay.filter { $0.key >= start && $0.key <= end }.values.sorted { $0.date < $1.date }
    }

    /// Latest minus earliest weigh-in in the window, in pounds; nil with fewer than two weigh-ins.
    func weightChange(overDays days: Int, endingOn date: Date) -> Double? {
        let window = weighIns(overDays: days, endingOn: date)
        guard let first = window.first, let last = window.last, window.count >= 2 else { return nil }
        return last.weightLbs - first.weightLbs
    }

    // MARK: Range

    /// Daily averages over the logged days of the `days` days ending on `date`, plus how many of them hit the
    /// calorie target (within `onTargetTolerance`).
    func rangeSummary(days: Int, endingOn date: Date) -> RangeSummary {
        let end = day(date)
        var logged = 0, onTarget = 0, withTarget = 0
        var kcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0
        for offset in 0..<max(0, days) {
            let d = shift(end, by: -offset)
            guard let items = entriesByDay[d], !items.isEmpty else { continue }
            let totals = NutritionMath.totals(of: items)
            logged += 1
            kcal += totals.kcal; protein += totals.protein; carbs += totals.carbs; fat += totals.fat
            if let goal = target(on: d), goal.kcal > 0 {
                withTarget += 1
                if abs(totals.kcal - goal.kcal) <= goal.kcal * Self.onTargetTolerance { onTarget += 1 }
            }
        }
        guard logged > 0 else { return .empty(days: days) }
        let n = Double(logged)
        return RangeSummary(days: days, loggedDays: logged, avgKcal: kcal / n, avgProtein: protein / n,
                            avgCarbs: carbs / n, avgFat: fat / n, daysOnTarget: onTarget, loggedDaysWithTarget: withTarget)
    }
}

// MARK: - Dashboard (what the UI renders)

/// One weight point in the user's display unit.
struct WeightPoint: Equatable, Identifiable {
    var date: Date
    var value: Double
    var id: Date { date }
}

/// Everything the Dashboard shows for one selected day. Weights are in `unit`.
struct NutritionDashboard: Equatable {
    var date: Date
    var unit: BodyWeightUnit
    var week: [DashboardDay]
    var foodLogGrid: [FoodLogDay]
    var weighInGrid: [WeighInDay]
    var currentStreak: Int
    var bestStreak: Int
    /// Weigh-ins of the last 90 days (for the chart), oldest first.
    var weightSeries: [WeightPoint]
    /// Newest weigh-in overall.
    var latestWeight: WeightPoint?
    /// The selected day's weigh-in, if any (to prefill the log field).
    var weightOnDate: WeightPoint?
    /// Latest minus earliest weigh-in over the last 30 days; nil with fewer than two weigh-ins.
    var weightChange30Days: Double?
    var range28: RangeSummary
    var range90: RangeSummary
}
