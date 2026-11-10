import Foundation

/// Dashboard and weight logging. Weights cross this boundary in the user's unit (kg or lb) and are stored in pounds.
extension NutritionViewModel {

    /// The weight unit to show and accept: the app-wide Settings preference.
    var bodyWeightUnit: BodyWeightUnit { BodyWeightUnit.current() }

    // MARK: - Weight

    /// Logs a weight (in `unit`, default the user's preference) for a day (default today). Logging twice on one
    /// day updates that day's weigh-in. Also updates the profile weight when this is the newest weigh-in.
    @discardableResult
    func logWeight(_ value: Double, unit: BodyWeightUnit? = nil, on date: Date = Date()) -> WeighIn? {
        guard let userId else { return nil }
        let saved = repository.logWeight(userId: userId, value, unit: unit ?? bodyWeightUnit, on: date)
        reload()
        return saved
    }

    /// Edits an existing weigh-in's weight (in `unit`, default the user's preference).
    @discardableResult
    func updateWeighIn(_ weighIn: WeighIn, value: Double, unit: BodyWeightUnit? = nil) -> WeighIn? {
        guard let userId else { return nil }
        let saved = repository.updateWeighIn(id: weighIn.id, userId: userId, value: value, unit: unit ?? bodyWeightUnit)
        reload()
        return saved
    }

    func deleteWeighIn(_ weighIn: WeighIn) {
        guard let userId else { return }
        repository.deleteWeighIn(id: weighIn.id, userId: userId)
        reload()
    }

    /// Weigh-ins from `range.lowerBound`'s day through `range.upperBound`'s day, oldest first (weights in pounds;
    /// convert with `bodyWeightUnit.fromLbs`).
    func weighIns(in range: ClosedRange<Date>) -> [WeighIn] {
        guard let userId else { return [] }
        return repository.weighIns(userId: userId, in: range)
    }

    func latestWeighIn() -> WeighIn? {
        guard let userId else { return nil }
        return repository.latestWeighIn(userId: userId)
    }

    // MARK: - Dashboard

    /// Everything the Dashboard renders for `date` (default: the selected day). The week strip is the Sunday-start
    /// week containing `date`; the grids and averages end on `date`; the streak is measured from today.
    func dashboard(for date: Date? = nil) -> NutritionDashboard? {
        guard let userId else { return nil }
        let day = (date ?? self.date).startOfDay
        let unit = bodyWeightUnit
        let stats = repository.dashboardStats(userId: userId, endingOn: day)
        let series = stats.weighIns(overDays: 90, endingOn: day).map { WeightPoint(date: $0.date, value: unit.fromLbs($0.weightLbs)) }
        func point(_ w: WeighIn?) -> WeightPoint? { w.map { WeightPoint(date: $0.date, value: unit.fromLbs($0.weightLbs)) } }
        return NutritionDashboard(
            date: day,
            unit: unit,
            week: stats.weekDays(containing: day, weekStartsOn: 1),
            foodLogGrid: stats.foodLogGrid(endingOn: day, days: NutritionDashboardStats.gridDays),
            weighInGrid: stats.weighInGrid(endingOn: day, days: NutritionDashboardStats.gridDays),
            currentStreak: stats.currentLogStreak(asOf: repository.now()),
            bestStreak: stats.bestLogStreak,
            weightSeries: series,
            latestWeight: point(repository.latestWeighIn(userId: userId)),
            weightOnDate: point(repository.weighIn(userId: userId, on: day)),
            weightChange30Days: stats.weightChange(overDays: 30, endingOn: day).map { unit.fromLbs($0) },
            range28: stats.rangeSummary(days: 28, endingOn: day),
            range90: stats.rangeSummary(days: 90, endingOn: day))
    }
}
