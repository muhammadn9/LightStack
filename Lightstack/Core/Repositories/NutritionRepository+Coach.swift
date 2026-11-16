import Foundation

/// What the AI coach reads from the nutrition data. Read-only; sharing switches are applied by the caller.
extension NutritionRepository {

    /// The fuel summary as of `now`: today so far, the last 7 completed days, weight trends, the goal.
    /// nil when there is no nutrition data at all.
    func coachFuel(userId: UUID, now: Date) -> CoachFuelSummary? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let first = calendar.date(byAdding: .day, value: -8, to: today) ?? today
        let weighStart = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        return CoachFuelBuilder.build(
            entries: localStorage.fetchFoodEntries(userId: userId, in: first...today),
            plans: plans(userId: userId),
            targets: localStorage.fetchNutritionTargets(userId: userId),
            weighIns: localStorage.fetchWeighIns(userId: userId, in: weighStart...today),
            goals: goalSettings(userId: userId), now: now, calendar: calendar)
    }

    /// The meals eaten in the 24 hours before `start` (a workout's start, or now for a plan).
    func coachPreWorkoutMeals(userId: UUID, before start: Date) -> PreWorkoutMeals? {
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: start)) ?? start
        return PreWorkoutMealsBuilder.build(
            entries: localStorage.fetchFoodEntries(userId: userId, in: from...start),
            before: start, calendar: calendar)
    }
}
