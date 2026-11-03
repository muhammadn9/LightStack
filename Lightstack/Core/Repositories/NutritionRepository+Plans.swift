import Foundation

/// Goal settings, the setup calculator hand-off and weekday macro plans.
/// Same rules as the rest of the repository: local save first, then the cloud write goes through the queue.
extension NutritionRepository {

    // MARK: - Goal settings

    func goalSettings(userId: UUID) -> NutritionGoalSettings? {
        localStorage.fetchGoalSettings(userId: userId)
    }

    /// True once the wizard has been finished on any device.
    func isSetupComplete(userId: UUID) -> Bool {
        goalSettings(userId: userId)?.isComplete ?? false
    }

    /// The saved settings, or a fresh draft prefilled from the profile (age, height, weight).
    func goalSettingsOrDraft(userId: UUID) -> NutritionGoalSettings {
        if let saved = goalSettings(userId: userId) { return saved }
        let profile = localStorage.fetchProfile(userId: userId).map { UserProfile(from: $0) }
        return NutritionGoalSettings.draft(userId: userId, profile: profile, now: now())
    }

    /// Saves the settings (one row per user), and copies age, height and weight into the profile the way the
    /// app already does (local save, then the profile upsert goes through the queue).
    @discardableResult
    func saveGoalSettings(_ settings: NutritionGoalSettings, updateProfile: Bool = true) -> NutritionGoalSettings {
        var saved = settings
        let stamp = now()
        if let existing = localStorage.fetchGoalSettings(userId: settings.userId) {
            saved = NutritionGoalSettings(
                id: existing.id, userId: settings.userId, goal: settings.goal, sex: settings.sex, age: settings.age,
                heightInches: settings.heightInches, currentWeightLbs: settings.currentWeightLbs,
                targetWeightLbs: settings.targetWeightLbs, weeklyRateLbs: settings.weeklyRateLbs,
                activityLevel: settings.activityLevel, liftsWeights: settings.liftsWeights, unit: settings.unit,
                completedAt: settings.completedAt, createdAt: existing.createdAt, updatedAt: stamp)
        } else {
            saved = NutritionGoalSettings(
                id: NutritionGoalSettings.id(userId: settings.userId), userId: settings.userId, goal: settings.goal,
                sex: settings.sex, age: settings.age, heightInches: settings.heightInches,
                currentWeightLbs: settings.currentWeightLbs, targetWeightLbs: settings.targetWeightLbs,
                weeklyRateLbs: settings.weeklyRateLbs, activityLevel: settings.activityLevel,
                liftsWeights: settings.liftsWeights, unit: settings.unit, completedAt: settings.completedAt,
                createdAt: stamp, updatedAt: stamp)
        }
        localStorage.saveGoalSettings(saved)
        offlineQueueManager.submit(.upsertGoalSettings, payload: saved, recordKey: saved.id.uuidString)
        if updateProfile { applyToProfile(saved) }
        return saved
    }

    private func applyToProfile(_ settings: NutritionGoalSettings) {
        guard let entity = localStorage.fetchProfile(userId: settings.userId) else { return }
        var profile = UserProfile(from: entity)
        profile.age = settings.age > 0 ? settings.age : profile.age
        profile.heightInches = settings.heightInches > 0 ? settings.heightInches : profile.heightInches
        profile.weightLbs = settings.currentWeightLbs > 0 ? settings.currentWeightLbs : profile.weightLbs
        profile.updatedAt = now()
        localStorage.saveProfile(profile)
        offlineQueueManager.submit(.upsertProfile, payload: profile, recordKey: profile.userId.uuidString)
    }

    /// Finishes the wizard: saves the settings as complete, updates the profile, and makes ONE plan covering all
    /// seven days from the calculator result (any other plans are replaced).
    @discardableResult
    func completeSetup(settings: NutritionGoalSettings, calculation: GoalCalculation,
                       planName: String = "Daily") -> (settings: NutritionGoalSettings, plan: NutritionPlan?) {
        var done = settings
        done.weeklyRateLbs = calculation.weeklyRateLbs
        done.completedAt = now()
        let saved = saveGoalSettings(done)
        let plan = savePlan(userId: settings.userId, id: nil, name: planName, weekdayMask: WeekdayMask.all,
                            protein: calculation.proteinGrams, carbs: calculation.carbsGrams,
                            fat: calculation.fatGrams, kcalOverride: nil)
        return (saved, plan)
    }

    // MARK: - Plans

    /// Plans in display order. Archived (deleted) ones only when asked.
    func plans(userId: UUID, includeArchived: Bool = false) -> [NutritionPlan] {
        let all = localStorage.fetchNutritionPlans(userId: userId)
        return includeArchived ? all : all.filter { !$0.isArchived }
    }

    /// Weekdays (Calendar 1...7) that no plan covers; these fall back to the target history.
    func uncoveredWeekdays(userId: UUID) -> [Int] {
        NutritionPlanResolver.uncoveredWeekdays(in: plans(userId: userId))
    }

    /// Creates a plan (`id == nil`) or edits one. The plan takes its weekdays: other plans lose any day it claims,
    /// and a plan left with no days is archived. Calories derive from the macros (4/4/9) unless `kcalOverride`.
    /// Returns nil for an empty weekday set, a blank name or an unknown id.
    @discardableResult
    func savePlan(userId: UUID, id: UUID?, name: String, weekdayMask: Int, protein: Double, carbs: Double,
                  fat: Double, kcalOverride: Double?) -> NutritionPlan? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let mask = weekdayMask & WeekdayMask.all
        guard !trimmed.isEmpty, mask != 0 else { return nil }
        let stamp = now()
        let p = max(0, protein), c = max(0, carbs), f = max(0, fat)
        let kcal = max(0, kcalOverride ?? NutritionMath.derivedKcal(protein: p, carbs: c, fat: f))
        let all = localStorage.fetchNutritionPlans(userId: userId)

        var plan: NutritionPlan
        if let id {
            guard var existing = all.first(where: { $0.id == id }) else { return nil }
            existing.name = trimmed; existing.weekdayMask = mask
            existing.protein = p; existing.carbs = c; existing.fat = f
            existing.kcal = kcal; existing.kcalOverridden = kcalOverride != nil
            existing.isArchived = false
            existing.updatedAt = stamp
            plan = existing
        } else {
            let next = (all.map(\.sortOrder).max() ?? -1) + 1
            plan = NutritionPlan(id: UUID(), userId: userId, name: trimmed, weekdayMask: mask, protein: p, carbs: c,
                                 fat: f, kcal: kcal, kcalOverridden: kcalOverride != nil, sortOrder: next,
                                 isArchived: false, createdAt: stamp, updatedAt: stamp)
        }

        var changed: [NutritionPlan] = [plan]
        for other in all where other.id != plan.id && !other.isArchived && other.weekdayMask & mask != 0 {
            var moved = other
            moved.weekdayMask &= ~mask
            if moved.weekdayMask == 0 { moved.isArchived = true }
            moved.updatedAt = stamp
            changed.append(moved)
        }
        localStorage.saveNutritionPlans(changed)
        changed.forEach { queue($0) }
        return plan
    }

    /// Soft delete: the plan stops applying and its days fall back to the target history.
    @discardableResult
    func archivePlan(id: UUID, userId: UUID) -> NutritionPlan? {
        guard var plan = localStorage.fetchNutritionPlan(id: id), plan.userId == userId else { return nil }
        plan.isArchived = true
        plan.updatedAt = now()
        localStorage.saveNutritionPlan(plan)
        queue(plan)
        return plan
    }

    /// Puts the given plans in this order (positions 0...n-1); other plans keep their relative order after them.
    func reorderPlans(userId: UUID, orderedIds: [UUID]) {
        let all = localStorage.fetchNutritionPlans(userId: userId)
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        let first = orderedIds.compactMap { byId[$0] }
        let firstIds = Set(first.map(\.id))
        let rest = all.filter { !firstIds.contains($0.id) }
        let stamp = now()
        var changed: [NutritionPlan] = []
        for (index, plan) in (first + rest).enumerated() where plan.sortOrder != index {
            var updated = plan
            updated.sortOrder = index
            updated.updatedAt = stamp
            changed.append(updated)
        }
        localStorage.saveNutritionPlans(changed)
        changed.forEach { queue($0) }
    }

    /// The plan that applies on that day, if any.
    func plan(userId: UUID, on date: Date) -> NutritionPlan? {
        NutritionPlanResolver.plan(in: plans(userId: userId), on: date)
    }

    /// The target in force on that day: the weekday plan, else the effective-date target history.
    func resolvedTarget(userId: UUID, on date: Date) -> NutritionTarget? {
        NutritionPlanResolver.target(plans: plans(userId: userId), history: localStorage.fetchNutritionTargets(userId: userId),
                                     on: date.startOfDay)
    }

    private func queue(_ plan: NutritionPlan) {
        offlineQueueManager.submit(.upsertNutritionPlan, payload: plan, recordKey: plan.id.uuidString)
    }
}
