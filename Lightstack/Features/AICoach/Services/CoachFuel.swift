import Foundation

// MARK: - Summary types

/// How far the logged intake can be trusted. Counts logged days of the last 7 completed days.
enum FuelDataQuality: String, Equatable {
    /// 5 or more logged days of 7.
    case good
    /// 2 to 4 logged days.
    case partial
    /// 0 or 1 logged day: the coach must ignore the intake numbers.
    case unreliable

    static func forLoggedDays(_ days: Int) -> FuelDataQuality {
        if days >= 5 { return .good }
        if days >= 2 { return .partial }
        return .unreliable
    }
}

/// Intake so far today, with the local time it was read (a morning total is not under-eating).
struct FuelToday: Equatable {
    var kcalSoFar: Double
    var proteinSoFar: Double
    var targetKcal: Double?
    var targetProteinG: Double?
    /// Local time of day, e.g. "8:10am".
    var timeLabel: String
    var hasEntries: Bool
}

/// The last 7 completed days (yesterday back), averaged over LOGGED days only.
struct FuelWeek: Equatable {
    /// Logged days of the 7 (0...7).
    var loggedDays: Int
    var avgKcal: Double
    var avgProtein: Double
    var avgCarbs: Double
    var avgFat: Double
    /// Mean target over the logged days that had one.
    var avgTargetKcal: Double?
    var avgTargetProtein: Double?
    /// Logged days within +-10% of that day's calorie target (the dashboard's rule).
    var daysOnTarget: Int
    /// Logged days that had a target to compare against.
    var daysWithTarget: Int
}

/// Yesterday's intake, the 7-day picture, today so far, the weight trend and the nutrition goal.
struct CoachFuelSummary: Equatable {
    var yesterdayKcal: Double? = nil
    var targetKcal: Double? = nil
    var proteinG: Double? = nil
    var targetProteinG: Double? = nil
    /// "lose", "maintain" or "gain".
    var goal: String? = nil
    /// Pounds per week (magnitude).
    var weeklyRate: Double? = nil
    var today: FuelToday? = nil
    var last7: FuelWeek? = nil
    /// Weight change in lb per week over the last 14 and 30 days (negative = losing); nil without enough weigh-ins.
    var weightTrend14: Double? = nil
    var weightTrend30: Double? = nil
    /// Carbs of everything logged in the 24 hours up to now (so the "very low carbs" rule works without meals).
    var carbsLast24h: Double? = nil
    var dataQuality: FuelDataQuality = .good
}

// MARK: - Builder

/// Builds `CoachFuelSummary` from nutrition rows. Pure: no I/O, no clock; every input is a parameter.
enum CoachFuelBuilder {

    /// Weight trends need at least this many days between the first and last weigh-in of the window.
    static let minWeightSpanDays = 5

    static func build(
        entries: [FoodEntry], plans: [NutritionPlan] = [], targets: [NutritionTarget] = [], weighIns: [WeighIn] = [],
        goals: NutritionGoalSettings?, now: Date, calendar: Calendar = .current
    ) -> CoachFuelSummary? {
        let today = calendar.startOfDay(for: now)
        func shift(_ date: Date, _ days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: date) ?? date }
        let yesterday = shift(today, -1)

        // Nothing logged after `now` counts for today (a later review reads the day as it was).
        let usable = entries.filter { entry in
            let day = calendar.startOfDay(for: entry.date)
            return day < today || (day == today && entry.createdAt <= now)
        }
        let stats = NutritionDashboardStats(entries: usable, plans: plans, history: targets, weighIns: weighIns, calendar: calendar)

        // Last 7 completed days.
        let days = stats.dailyDays(endingOn: yesterday, days: 7)
        let logged = days.filter(\.hasLog)
        var week: FuelWeek?
        if !logged.isEmpty {
            let n = Double(logged.count)
            let kcalTargets = logged.compactMap { $0.target?.kcal }.filter { $0 > 0 }
            let proteinTargets = logged.compactMap { $0.target?.protein }.filter { $0 > 0 }
            let range = stats.rangeSummary(days: 7, endingOn: yesterday)
            week = FuelWeek(
                loggedDays: logged.count,
                avgKcal: logged.reduce(0) { $0 + $1.totals.kcal } / n,
                avgProtein: logged.reduce(0) { $0 + $1.totals.protein } / n,
                avgCarbs: logged.reduce(0) { $0 + $1.totals.carbs } / n,
                avgFat: logged.reduce(0) { $0 + $1.totals.fat } / n,
                avgTargetKcal: kcalTargets.isEmpty ? nil : kcalTargets.reduce(0, +) / Double(kcalTargets.count),
                avgTargetProtein: proteinTargets.isEmpty ? nil : proteinTargets.reduce(0, +) / Double(proteinTargets.count),
                daysOnTarget: range.daysOnTarget, daysWithTarget: range.loggedDaysWithTarget)
        }

        // Today so far.
        let todayEntries = usable.filter { calendar.startOfDay(for: $0.date) == today }
        let todayTotals = NutritionMath.totals(of: todayEntries)
        let todayTarget = NutritionPlanResolver.target(plans: plans, history: targets, on: today, calendar: calendar)
        let todaySoFar = FuelToday(
            kcalSoFar: todayTotals.kcal, proteinSoFar: todayTotals.protein,
            targetKcal: todayTarget?.kcal, targetProteinG: todayTarget?.protein,
            timeLabel: timeLabel(now, calendar: calendar), hasEntries: !todayEntries.isEmpty)

        let trend14 = weightTrend(weighIns, days: 14, now: now, calendar: calendar)
        let trend30 = weightTrend(weighIns, days: 30, now: now, calendar: calendar)
        let settings = goals.flatMap { $0.isComplete ? $0 : nil }
        guard week != nil || !todayEntries.isEmpty || settings != nil || trend14 != nil || trend30 != nil else { return nil }

        let yesterdayDay = days.last
        let yesterdayLogged = yesterdayDay?.hasLog == true
        return CoachFuelSummary(
            yesterdayKcal: yesterdayLogged ? yesterdayDay?.totals.kcal : nil,
            targetKcal: yesterdayDay?.target?.kcal,
            proteinG: yesterdayLogged ? yesterdayDay?.totals.protein : nil,
            targetProteinG: yesterdayDay?.target?.protein,
            goal: settings?.goal.rawValue,
            weeklyRate: settings?.weeklyRateLbs,
            today: todaySoFar, last7: week,
            weightTrend14: trend14, weightTrend30: trend30,
            carbsLast24h: PreWorkoutMealsBuilder.build(entries: usable, before: now, calendar: calendar)?.carbs24h ?? 0,
            dataQuality: FuelDataQuality.forLoggedDays(logged.count))
    }

    /// "8:10am" in the calendar's time zone.
    static func timeLabel(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "h:mma"
        return formatter.string(from: date).lowercased()
    }

    /// Least-squares slope of the weigh-ins of the last `days` days, in lb per week. nil with fewer than two
    /// weigh-ins or less than `minWeightSpanDays` between the first and the last.
    static func weightTrend(_ weighIns: [WeighIn], days: Int, now: Date, calendar: Calendar = .current) -> Double? {
        let end = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) else { return nil }
        let window = weighIns
            .map { (day: calendar.startOfDay(for: $0.date), lbs: $0.weightLbs) }
            .filter { $0.day >= start && $0.day <= end && $0.lbs > 0 }
            .sorted { $0.day < $1.day }
        guard window.count >= 2, let first = window.first, let last = window.last else { return nil }
        let span = calendar.dateComponents([.day], from: first.day, to: last.day).day ?? 0
        guard span >= minWeightSpanDays else { return nil }
        let xs = window.map { Double(calendar.dateComponents([.day], from: first.day, to: $0.day).day ?? 0) }
        let ys = window.map(\.lbs)
        let n = Double(window.count)
        let meanX = xs.reduce(0, +) / n, meanY = ys.reduce(0, +) / n
        let denominator = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard denominator > 0 else { return nil }
        let numerator = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        return numerator / denominator * 7
    }
}

// MARK: - Pre-workout meals

/// One meal in the 24 hours before a workout.
struct PreWorkoutMeal: Equatable {
    /// Hours between the meal (its last entry) and the workout start, rounded to 0.1.
    var hoursBefore: Double
    /// The top three foods by calories.
    var foods: [String]
    /// Foods beyond the three named.
    var moreCount: Int
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
}

/// Up to four recent meals before a workout (newest first) and the carbs eaten in that window.
struct PreWorkoutMeals: Equatable {
    var meals: [PreWorkoutMeal]
    /// Carbs of every entry in the 24 hours, not only of the listed meals.
    var carbs24h: Double
}

enum PreWorkoutMealsBuilder {
    static let windowHours = 24.0
    static let maxMeals = 4
    /// Entries without a meal slot join a meal when logged within this many minutes of the previous one.
    static let clusterGapMinutes = 45.0
    static let namedFoods = 3

    /// Meals in the 24 hours before `start`. Timing comes from `createdAt`. Entries logged on another day than
    /// they are dated for (a back-fill) have no real time, so they are ignored. nil when there are no meals.
    static func build(entries: [FoodEntry], before start: Date, calendar: Calendar = .current) -> PreWorkoutMeals? {
        let from = start.addingTimeInterval(-windowHours * 3600)
        let inWindow = entries.filter { entry in
            entry.createdAt > from && entry.createdAt <= start
                && calendar.isDate(entry.createdAt, inSameDayAs: entry.date)
        }
        guard !inWindow.isEmpty else { return nil }

        // Slotted entries group by (slot, day); the rest cluster by time proximity.
        var groups: [[FoodEntry]] = []
        var bySlot: [String: [FoodEntry]] = [:]
        var order: [String] = []
        var loose: [FoodEntry] = []
        for entry in inWindow {
            if let slot = entry.mealSlotId {
                let key = slot.uuidString + "|" + String(calendar.startOfDay(for: entry.date).timeIntervalSince1970)
                if bySlot[key] == nil { order.append(key) }
                bySlot[key, default: []].append(entry)
            } else {
                loose.append(entry)
            }
        }
        for key in order { if let group = bySlot[key] { groups.append(group) } }
        var current: [FoodEntry] = []
        for entry in loose.sorted(by: { $0.createdAt < $1.createdAt }) {
            if let last = current.last, entry.createdAt.timeIntervalSince(last.createdAt) > clusterGapMinutes * 60 {
                groups.append(current)
                current = []
            }
            current.append(entry)
        }
        if !current.isEmpty { groups.append(current) }

        let meals = groups.compactMap { meal(from: $0, start: start) }
            .sorted { $0.hoursBefore < $1.hoursBefore }
            .prefix(maxMeals)
        let carbs = NutritionMath.totals(of: inWindow).carbs
        return PreWorkoutMeals(meals: Array(meals), carbs24h: carbs)
    }

    private static func meal(from group: [FoodEntry], start: Date) -> PreWorkoutMeal? {
        guard let latest = group.map(\.createdAt).max() else { return nil }
        let totals = NutritionMath.totals(of: group)
        let ranked = group.sorted { $0.total.kcal > $1.total.kcal }
        let named = ranked.prefix(namedFoods).map(\.name)
        let hours = max(0, start.timeIntervalSince(latest) / 3600)
        return PreWorkoutMeal(
            hoursBefore: (hours * 10).rounded() / 10, foods: Array(named), moreCount: max(0, group.count - namedFoods),
            kcal: totals.kcal, protein: totals.protein, carbs: totals.carbs, fat: totals.fat)
    }
}

// MARK: - Fuel rules

/// Whether the athlete looks under-fuelled, and why. Drives the deterministic backstop on the plan's weights
/// and the post-workout miss classification.
struct FuelAssessment: Equatable {
    /// Short phrases, most important first ("eating well under target this week").
    var reasons: [String] = []
    var isLow: Bool { !reasons.isEmpty }
    var primaryReason: String? { reasons.first }
}

enum FuelRules {
    /// Seven-day average calories more than this far under target is a deep deficit.
    static let deepDeficitShare = 0.20
    /// Average protein under this share of target is low.
    static let lowProteinShare = 0.80
    /// Weight falling faster than this multiple of the goal rate is a fast loss.
    static let fastLossFactor = 1.5
    /// Base rate (lb/week) for the fast-loss check when the goal is not "lose" or has no rate.
    static let fallbackRate = 0.5
    /// A meal this close to training (hours) counts as "just before".
    static let heavyMealHours = 2.0
    static let heavyMealKcal = 800.0
    static let heavyMealFatG = 35.0

    /// Low fuel needs data that can be trusted: with `unreliable` quality nothing is flagged. Without a
    /// nutrition summary there is nothing to judge, so nothing is flagged either.
    static func assess(fuel: CoachFuelSummary?, meals: PreWorkoutMeals?) -> FuelAssessment {
        guard let fuel, fuel.dataQuality != .unreliable else { return FuelAssessment() }
        var reasons: [String] = []
        if let week = fuel.last7, week.loggedDays > 0 {
            if let target = week.avgTargetKcal, target > 0, week.avgKcal < target * (1 - deepDeficitShare) {
                reasons.append("eating well under target this week")
            }
            if let target = week.avgTargetProtein, target > 0, week.avgProtein < target * lowProteinShare {
                reasons.append("protein is low this week")
            }
        }
        if let trend = fuel.weightTrend14 ?? fuel.weightTrend30, let goal = fuel.goal {
            let base = goal == "lose" && (fuel.weeklyRate ?? 0) > 0 ? (fuel.weeklyRate ?? 0) : fallbackRate
            if -trend > base * fastLossFactor { reasons.append("weight is dropping faster than planned") }
        }
        if let meals, meals.meals.contains(where: {
            $0.hoursBefore <= heavyMealHours && $0.kcal >= heavyMealKcal && $0.fat >= heavyMealFatG
        }) {
            reasons.append("a heavy meal just before training")
        }
        return FuelAssessment(reasons: reasons)
    }
}
