import Foundation

/// Weigh-ins and the Dashboard read model.
/// Same rules as the rest of the repository: local save first, then the cloud write goes through the queue.
///
/// Profile weight: the newest weigh-in (by date) is also the user's profile weight, which the coach and the
/// goals wizard read. Logging, editing or deleting the NEWEST weigh-in updates the profile (through the same
/// local save + queued profile upsert the wizard uses); touching an older one never does. Goal settings'
/// `currentWeightLbs` is deliberately left alone: calorie targets never change because of a scale reading.
extension NutritionRepository {

    // MARK: - Weigh-ins

    /// Logs a weight for a day (default today). One weigh-in per day: logging again that day updates it.
    /// `value` is in `unit`; it is stored in pounds. Returns nil for a non-positive/non-finite value or a future day.
    @discardableResult
    func logWeight(userId: UUID, _ value: Double, unit: BodyWeightUnit, on date: Date? = nil) -> WeighIn? {
        let stamp = now()
        let day = (date ?? stamp).startOfDay
        let lbs = unit.toLbs(value)
        guard value.isFinite, lbs > 0, lbs.isFinite, day <= stamp.startOfDay else { return nil }
        var weighIn: WeighIn
        if var existing = localStorage.fetchWeighIn(userId: userId, on: day) {
            existing.weightLbs = lbs
            existing.updatedAt = stamp
            weighIn = existing
        } else {
            weighIn = WeighIn.make(userId: userId, date: day, weightLbs: lbs, now: stamp)
        }
        save(weighIn)
        if localStorage.fetchLatestWeighIn(userId: userId)?.id == weighIn.id { applyProfileWeight(weighIn) }
        return weighIn
    }

    /// Changes the weight of an existing weigh-in (its day stays; to move it, delete and log again).
    @discardableResult
    func updateWeighIn(id: UUID, userId: UUID, value: Double, unit: BodyWeightUnit) -> WeighIn? {
        let lbs = unit.toLbs(value)
        guard value.isFinite, lbs > 0, lbs.isFinite, var weighIn = localStorage.fetchWeighIn(id: id),
              weighIn.userId == userId else { return nil }
        weighIn.weightLbs = lbs
        weighIn.updatedAt = now()
        save(weighIn)
        if localStorage.fetchLatestWeighIn(userId: userId)?.id == weighIn.id { applyProfileWeight(weighIn) }
        return weighIn
    }

    /// Deletes a weigh-in. If it was the newest, the profile weight falls back to the next newest one
    /// (none left = the profile is left as it is).
    func deleteWeighIn(id: UUID, userId: UUID) {
        guard let weighIn = localStorage.fetchWeighIn(id: id), weighIn.userId == userId else { return }
        let wasNewest = localStorage.fetchLatestWeighIn(userId: userId)?.id == id
        localStorage.deleteWeighIns(ids: [id])
        offlineQueueManager.submit(.deleteWeighIn, payload: DeleteNutritionRecordPayload(id: id))
        offlineQueueManager.submitTombstones(.weighIn, ids: [id])
        if wasNewest, let next = localStorage.fetchLatestWeighIn(userId: userId) { applyProfileWeight(next) }
    }

    /// Weigh-ins from `range.lowerBound`'s day through `range.upperBound`'s day, oldest first.
    func weighIns(userId: UUID, in range: ClosedRange<Date>) -> [WeighIn] {
        localStorage.fetchWeighIns(userId: userId, in: range)
    }

    func weighIn(userId: UUID, on date: Date) -> WeighIn? {
        localStorage.fetchWeighIn(userId: userId, on: date)
    }

    func latestWeighIn(userId: UUID) -> WeighIn? {
        localStorage.fetchLatestWeighIn(userId: userId)
    }

    private func save(_ weighIn: WeighIn) {
        localStorage.saveWeighIn(weighIn)
        offlineQueueManager.submit(.upsertWeighIn, payload: weighIn, recordKey: weighIn.id.uuidString)
    }

    /// Copies a weigh-in's weight into the profile (local save, then the queued profile upsert). No profile
    /// on this device yet = nothing to update.
    private func applyProfileWeight(_ weighIn: WeighIn) {
        guard let entity = localStorage.fetchProfile(userId: weighIn.userId) else { return }
        var profile = UserProfile(from: entity)
        guard profile.weightLbs != weighIn.weightLbs else { return }
        profile.weightLbs = weighIn.weightLbs
        profile.updatedAt = now()
        localStorage.saveProfile(profile)
        offlineQueueManager.submit(.upsertProfile, payload: profile, recordKey: profile.userId.uuidString)
    }

    // MARK: - Dashboard

    /// The Dashboard numbers for `date`. Reads the last 90 days of entries (the longest window shown) and every
    /// logged day (for streaks); everything else is computed in memory by `NutritionDashboardStats`.
    func dashboardStats(userId: UUID, endingOn date: Date) -> NutritionDashboardStats {
        let end = date.startOfDay
        let calendar = Calendar.current
        // The week strip can reach 6 days past `date`; the 90-day range ends on `date`.
        let first = calendar.date(byAdding: .day, value: -120, to: end) ?? end
        let last = calendar.date(byAdding: .day, value: 7, to: end) ?? end
        return NutritionDashboardStats(
            entries: localStorage.fetchFoodEntries(userId: userId, in: first...last),
            plans: plans(userId: userId),
            history: localStorage.fetchNutritionTargets(userId: userId),
            weighIns: localStorage.fetchAllWeighIns(userId: userId),
            loggedDays: localStorage.fetchLoggedFoodDays(userId: userId),
            calendar: calendar)
    }
}
