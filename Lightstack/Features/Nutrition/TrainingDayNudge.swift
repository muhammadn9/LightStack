import Foundation

/// What the Journal knows about today's training. nil from the provider means no workout today.
struct TrainingDayInfo: Equatable {
    /// "Legs", "Push"... nil when unknown.
    var workoutType: String?
    /// A workout with logged sets exists today.
    var workoutDone: Bool
}

/// Reads today's planned or logged workout (injected into the view model, like the coach's `fuel` closure).
typealias TrainingDayProvider = (_ userId: UUID, _ day: Date) -> TrainingDayInfo?

/// The rule-based "Training day" card in the Journal. Pure: no I/O, no clock.
struct TrainingDayNudge: Equatable {
    var title: String
    /// "Protein 45/180 g so far".
    var proteinLine: String
    /// One tip, or nil when no rule applies.
    var tip: String?

    static let loseTip = "Put more of today's carbs around your workout."
    static let carbsTip = "Hit your carbs today to fuel the session."
    static let heavyMealTip = "Heavy meal just now: give it a bit before lifting."
    static let doneTip = "Workout done: a protein-rich meal helps recovery."

    /// Carbs so far under this share of the target count as behind.
    static let lowCarbShare = 0.25
    /// Before this hour a low carb total is still expected to catch up ("before 3pm").
    static let afternoonHour = 15
    static let heavyMealWindowHours = 2.0

    /// nil without a workout today or without nutrition targets. `entries` are today's entries.
    static func make(info: TrainingDayInfo?, target: NutritionTarget?, entries: [FoodEntry], goal: NutritionGoal?,
                     now: Date, calendar: Calendar = .current) -> TrainingDayNudge? {
        guard let info, let target, target.protein > 0 || target.carbs > 0 || target.kcal > 0 else { return nil }
        let totals = NutritionMath.totals(of: entries)
        let type = info.workoutType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = type.isEmpty ? "Training day" : "Training day · \(type)"
        let line = "Protein \(whole(totals.protein))/\(whole(target.protein)) g so far"
        return TrainingDayNudge(title: title, proteinLine: line,
                                tip: tip(info: info, target: target, entries: entries, carbs: totals.carbs, goal: goal,
                                         now: now, calendar: calendar))
    }

    private static func tip(info: TrainingDayInfo, target: NutritionTarget, entries: [FoodEntry], carbs: Double,
                            goal: NutritionGoal?, now: Date, calendar: Calendar) -> String? {
        if goal == .lose { return loseTip }
        let hour = calendar.component(.hour, from: now)
        if target.carbs > 0, carbs < target.carbs * lowCarbShare, !info.workoutDone || hour < afternoonHour {
            return carbsTip
        }
        if !info.workoutDone, hasHeavyMeal(entries, now: now, calendar: calendar) { return heavyMealTip }
        if info.workoutDone { return doneTip }
        return nil
    }

    /// Entries logged in the last 2 hours add up to 800 kcal and 35 g fat or more (the coach's heavy-meal rule).
    static func hasHeavyMeal(_ entries: [FoodEntry], now: Date, calendar: Calendar = .current) -> Bool {
        let from = now.addingTimeInterval(-heavyMealWindowHours * 3600)
        let recent = entries.filter {
            $0.createdAt > from && $0.createdAt <= now && calendar.isDate($0.createdAt, inSameDayAs: $0.date)
        }
        let totals = NutritionMath.totals(of: recent)
        return totals.kcal >= FuelRules.heavyMealKcal && totals.fat >= FuelRules.heavyMealFatG
    }

    private static func whole(_ value: Double) -> String { String(format: "%.0f", value) }
}

/// Settings and the per-day dismissal of the card. One source of truth in UserDefaults.
enum TrainingDayPreferences {
    static let tipsKey = "nutrition.trainingDayTips"
    static let dismissedDayKey = "nutrition.trainingDayDismissedDay"

    /// Default on.
    static func tipsEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: tipsKey) as? Bool ?? true
    }

    static func dayId(_ day: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func isDismissed(on day: Date, in defaults: UserDefaults = .standard, calendar: Calendar = .current) -> Bool {
        defaults.string(forKey: dismissedDayKey) == dayId(day, calendar: calendar)
    }

    static func dismiss(on day: Date, in defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        defaults.set(dayId(day, calendar: calendar), forKey: dismissedDayKey)
    }
}
