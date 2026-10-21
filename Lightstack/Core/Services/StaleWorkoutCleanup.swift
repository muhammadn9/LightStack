import Foundation

/// Removes generated plans that were never started. A plan is saved as a workout with
/// exercises when it is generated; if the user never logs a set it stays behind as an
/// empty "workout". Deletes go through `WorkoutRepository.deleteWorkout`, so they sync and
/// are tombstoned.
///
/// TODO(plan-generation agent): call `removeSupersededPlans(userId:newPlanId:)` from
/// `WorkoutSessionService.finalizePlan` right after the new plan is saved, so generating a
/// new plan removes the previous unstarted one for the same day immediately.
final class StaleWorkoutCleanup {

    private let localStorage: LocalStorageService
    private let workoutRepository: WorkoutRepository
    private let now: () -> Date

    init(localStorage: LocalStorageService, workoutRepository: WorkoutRepository, now: @escaping () -> Date = { Date() }) {
        self.localStorage = localStorage
        self.workoutRepository = workoutRepository
        self.now = now
    }

    /// Deletes workouts with zero logged sets that are not `currentPendingId` (or in `protecting`)
    /// and are either dated before today or superseded by a newer plan the same day. Today's
    /// newest plan survives (it is the one waiting to be started). Returns the number removed.
    @discardableResult
    func removeUnstartedPlans(userId: UUID, keeping currentPendingId: UUID?, protecting: Set<UUID> = []) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now())
        let keep = protecting.union(currentPendingId.map { [$0] } ?? [])

        var empty: [CDWorkout] = []
        for cd in localStorage.fetchAllWorkouts(userId: userId) {
            guard let id = cd.id, !keep.contains(id), localStorage.loggedSetCount(workoutId: id) == 0 else { continue }
            empty.append(cd)
        }

        // Today's newest plan stays, unless the pending plan is newer than all of them.
        let todaysEmpty = empty
            .filter { ($0.date.map { calendar.startOfDay(for: $0) } ?? .distantPast) >= today }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        var survivors = Set<UUID>()
        if let latest = todaysEmpty.first, let latestId = latest.id {
            let pendingCreated = currentPendingId.flatMap { localStorage.fetchWorkout(id: $0)?.createdAt }
            if pendingCreated == nil || (latest.createdAt ?? .distantPast) > (pendingCreated ?? .distantPast) {
                survivors.insert(latestId)
            }
        }

        var removed = 0
        for cd in empty {
            guard let id = cd.id, !survivors.contains(id) else { continue }
            workoutRepository.deleteWorkout(Workout(from: cd))
            removed += 1
        }
        return removed
    }

    /// Removes empty plans for the same day as `newPlanId` that are older than it.
    /// For plan generation to call once the new plan is saved (see the TODO above).
    @discardableResult
    func removeSupersededPlans(userId: UUID, newPlanId: UUID) -> Int {
        guard let newPlan = localStorage.fetchWorkout(id: newPlanId), let planDate = newPlan.date else { return 0 }
        let calendar = Calendar.current
        var removed = 0
        for cd in localStorage.fetchWorkoutsForDate(userId: userId, date: planDate) {
            guard let id = cd.id, id != newPlanId, localStorage.loggedSetCount(workoutId: id) == 0,
                  (cd.createdAt ?? .distantPast) < (newPlan.createdAt ?? .distantFuture),
                  calendar.isDate(planDate, inSameDayAs: cd.date ?? planDate) else { continue }
            workoutRepository.deleteWorkout(Workout(from: cd))
            removed += 1
        }
        return removed
    }
}
