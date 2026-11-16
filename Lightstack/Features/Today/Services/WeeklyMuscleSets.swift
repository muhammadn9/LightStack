import Foundation

/// The coarse muscle groups the Today "This week" card reports, in their fixed display order.
enum WeeklyMuscleGroup: String, CaseIterable, Identifiable {
    case chest = "Chest"
    case back = "Back"
    case legs = "Legs"
    case shoulders = "Shoulders"
    case arms = "Arms"
    case core = "Core"

    var id: String { rawValue }

    /// Group for a logged exercise, or nil when it belongs to none (cardio, unknown).
    /// Arms is biceps + triceps + forearms; rear delts count as shoulders.
    static func group(forExercise name: String, muscleGroup: String) -> WeeklyMuscleGroup? {
        // "forearm" contains "rear", which the shared canonicaliser reads as rear delts.
        if muscleGroup.lowercased().contains("forearm") { return .arms }
        switch MuscleGroups.canonical(forExercise: name, muscleGroup: muscleGroup) {
        case "chest": return .chest
        case "back": return .back
        case "shoulders", "rear delts": return .shoulders
        case "biceps", "triceps", "forearms", "arms": return .arms
        case "quads", "hamstrings", "glutes", "calves", "legs": return .legs
        case "core": return .core
        default: return nil
        }
    }
}

/// One exercise as logged: its group inputs and how many sets were logged.
struct WeeklyLoggedExercise: Equatable {
    var name: String
    var muscleGroup: String
    var isCardio = false
    var setCount: Int
}

/// A past workout with its logged exercises.
struct WeeklyLoggedWorkout: Equatable {
    var date: Date
    var exercises: [WeeklyLoggedExercise]
}

/// Workouts and sets per muscle group for the current Monday-to-Sunday week.
struct WeeklyMuscleSummary: Equatable {
    struct Entry: Equatable, Identifiable {
        let group: WeeklyMuscleGroup
        let sets: Int
        var id: String { group.rawValue }
    }

    var workouts = 0
    var totalSets = 0
    /// Groups with sets first (most sets first), then the "not yet" groups in display order.
    var entries: [Entry] = WeeklyMuscleGroup.allCases.map { Entry(group: $0, sets: 0) }

    var isEmpty: Bool { totalSets == 0 }

    /// "3 workouts · 35 sets"
    var headline: String {
        "\(workouts) \(workouts == 1 ? "workout" : "workouts") · \(totalSets) \(totalSets == 1 ? "set" : "sets")"
    }

    static func compute(workouts: [WeeklyLoggedWorkout], now: Date = Date(), calendar: Calendar = .current) -> WeeklyMuscleSummary {
        var cal = calendar
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        guard let week = cal.dateInterval(of: .weekOfYear, for: now) else { return WeeklyMuscleSummary() }

        var perGroup: [WeeklyMuscleGroup: Int] = [:]
        var workoutCount = 0
        var total = 0
        for workout in workouts where week.contains(workout.date) {
            let sets = workout.exercises.reduce(0) { $0 + max(0, $1.setCount) }
            guard sets > 0 else { continue }
            workoutCount += 1
            total += sets
            for exercise in workout.exercises where !exercise.isCardio && exercise.setCount > 0 {
                if let group = WeeklyMuscleGroup.group(forExercise: exercise.name, muscleGroup: exercise.muscleGroup) {
                    perGroup[group, default: 0] += exercise.setCount
                }
            }
        }
        let all = WeeklyMuscleGroup.allCases.map { Entry(group: $0, sets: perGroup[$0] ?? 0) }
        let worked = all.enumerated().filter { $0.element.sets > 0 }
            .sorted { $0.element.sets != $1.element.sets ? $0.element.sets > $1.element.sets : $0.offset < $1.offset }
            .map(\.element)
        let notYet = all.filter { $0.sets == 0 }
        return WeeklyMuscleSummary(workouts: workoutCount, totalSets: total, entries: worked + notYet)
    }
}

/// Reads this week's logged sets from local storage.
struct WeeklyMuscleService {
    let workoutRepository: WorkoutRepository

    func summary(userId: UUID, now: Date = Date(), calendar: Calendar = .current) -> WeeklyMuscleSummary {
        var cal = calendar
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        guard let week = cal.dateInterval(of: .weekOfYear, for: now) else { return WeeklyMuscleSummary() }
        var rows: [WeeklyLoggedWorkout] = []
        for workout in workoutRepository.fetchRecentWorkouts(userId: userId, limit: 60) where week.contains(workout.date) {
            let exercises = workoutRepository.fetchExercises(workoutId: workout.id).map { exercise in
                WeeklyLoggedExercise(
                    name: exercise.name, muscleGroup: exercise.muscleGroup,
                    isCardio: exercise.trackingType == .cardio,
                    setCount: workoutRepository.fetchSets(exerciseId: exercise.id).count)
            }
            rows.append(WeeklyLoggedWorkout(date: workout.date, exercises: exercises))
        }
        return compute(workouts: rows, now: now, calendar: calendar)
    }

    private func compute(workouts: [WeeklyLoggedWorkout], now: Date, calendar: Calendar) -> WeeklyMuscleSummary {
        WeeklyMuscleSummary.compute(workouts: workouts, now: now, calendar: calendar)
    }
}
