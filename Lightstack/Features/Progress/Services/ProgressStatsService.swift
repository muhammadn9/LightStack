import Foundation

// MARK: - Input records

/// One logged set with the date of its workout.
struct LoggedSet {
    let date: Date
    let exerciseName: String
    let weightLbs: Double
    let reps: Int
}

struct LoggedWorkout {
    let id: UUID
    let date: Date
}

// MARK: - Output

struct BestSet: Equatable {
    let weightLbs: Double
    let reps: Int
    let e1rm: Double
}

struct LiftTrend: Identifiable, Equatable {
    let key: String
    let name: String
    let setCount: Int
    /// Best e1RM per week, oldest first (last = current week). Nil where nothing was lifted.
    let weeklyE1RM: [Double?]
    let allTimeBest: Double
    let thisMonth: BestSet?
    let lastMonth: BestSet?
    /// This month's best e1RM minus the best e1RM before this month.
    let monthDelta: Double?
    var id: String { key }
}

struct ProgressSnapshot: Equatable {
    /// Sets per equipment kind, current Mon-Sun week.
    var equipmentThisWeek: [EquipmentKind: Int] = [:]
    /// Same, last 4 weeks, oldest first.
    var equipmentByWeek: [[EquipmentKind: Int]] = []
    /// Weekday indices (0 = Monday) with a workout this week.
    var trainedWeekdays: Set<Int> = []
    var streak = 0
    /// Workouts per week, last 4 weeks, oldest first.
    var workoutsPerWeek: [Int] = []
    /// 13 weeks x 7 days of set counts, oldest week first. -1 = a day still in the future.
    var heatmap: [[Int]] = []
    /// Most-logged lifts, best first.
    var lifts: [LiftTrend] = []
    var totalWorkouts = 0
    /// Start-of-day dates that have at least one workout (all time).
    var workoutDays: Set<Date> = []
    /// Start-of-day dates marked as rest days inside the heatmap window (13 weeks).
    /// Rest days count toward the streak only; never toward workouts, sets or heat levels.
    var restDays: Set<Date> = []

    var daysTrainedThisWeek: Int { trainedWeekdays.count }
    var totalSetsThisWeek: Int { equipmentThisWeek.values.reduce(0, +) }
    var averageWorkoutsPerWeek: Double {
        guard !workoutsPerWeek.isEmpty else { return 0 }
        return Double(workoutsPerWeek.reduce(0, +)) / Double(workoutsPerWeek.count)
    }
    var topLifts: [LiftTrend] { Array(lifts.prefix(3)) }
}

// MARK: - Pure computations

enum ProgressStats {

    /// The user's calendar, with weeks running Monday to Sunday.
    static func weekCalendar(_ base: Calendar = .current) -> Calendar {
        var calendar = base
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func weekStart(of date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// Index of the week `date` falls in, counted back from the week of `now` (0 = this week).
    private static func weeksAgo(_ date: Date, now: Date, calendar: Calendar) -> Int {
        let start = weekStart(of: date, calendar: calendar)
        let current = weekStart(of: now, calendar: calendar)
        let days = calendar.dateComponents([.day], from: start, to: current).day ?? 0
        return Int((Double(days) / 7).rounded())
    }

    static func equipmentSets(_ sets: [LoggedSet], weeksBack: Int = 0, now: Date,
                              calendar: Calendar) -> [EquipmentKind: Int] {
        var result: [EquipmentKind: Int] = [:]
        for set in sets where weeksAgo(set.date, now: now, calendar: calendar) == weeksBack {
            for kind in EquipmentClassifier.kinds(forName: set.exerciseName) {
                result[kind, default: 0] += 1
            }
        }
        return result
    }

    static func trainedWeekdays(_ workouts: [LoggedWorkout], now: Date, calendar: Calendar) -> Set<Int> {
        let start = weekStart(of: now, calendar: calendar)
        var result = Set<Int>()
        for workout in workouts where weeksAgo(workout.date, now: now, calendar: calendar) == 0 {
            let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: workout.date)).day ?? 0
            if (0..<7).contains(days) { result.insert(days) }
        }
        return result
    }

    /// Workout counts for the last `weeks` weeks, oldest first.
    static func workoutsPerWeek(_ workouts: [LoggedWorkout], weeks: Int = 4, now: Date,
                                calendar: Calendar) -> [Int] {
        var counts = Array(repeating: 0, count: weeks)
        for workout in workouts {
            let ago = weeksAgo(workout.date, now: now, calendar: calendar)
            if (0..<weeks).contains(ago) { counts[weeks - 1 - ago] += 1 }
        }
        return counts
    }

    /// Set counts per day, `weeks` columns (oldest first) x 7 rows (Monday first).
    static func heatmap(_ sets: [LoggedSet], weeks: Int = 13, now: Date, calendar: Calendar) -> [[Int]] {
        var grid = Array(repeating: Array(repeating: 0, count: 7), count: weeks)
        let currentStart = weekStart(of: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        for set in sets {
            let ago = weeksAgo(set.date, now: now, calendar: calendar)
            guard (0..<weeks).contains(ago) else { continue }
            let start = weekStart(of: set.date, calendar: calendar)
            let day = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: set.date)).day ?? 0
            guard (0..<7).contains(day) else { continue }
            grid[weeks - 1 - ago][day] += 1
        }
        for day in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: day, to: currentStart), date > today {
                grid[weeks - 1][day] = -1
            }
        }
        return grid
    }

    /// Heatmap intensity 0...4 for a set count (-1 stays -1).
    static func heatLevel(_ count: Int) -> Int {
        switch count {
        case ..<0: return -1
        case 0: return 0
        case 1...6: return 1
        case 7...12: return 2
        case 13...18: return 3
        default: return 4
        }
    }

    /// Trends for the most-logged lifts. Variants of one name share a group.
    static func liftTrends(_ sets: [LoggedSet], limit: Int = 8, weeks: Int = 8, now: Date,
                           calendar: Calendar) -> [LiftTrend] {
        var groups: [String: [LoggedSet]] = [:]
        for set in sets {
            guard PersonalRecordsListView.estimatedOneRepMax(weight: set.weightLbs, reps: set.reps) != nil else { continue }
            groups[PersonalRecordsListView.exerciseKey(set.exerciseName), default: []].append(set)
        }
        let ranked = groups.sorted {
            $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key
        }
        guard let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: now) else { return [] }

        return ranked.prefix(limit).map { key, group in
            var weekly = Array<Double?>(repeating: nil, count: weeks)
            var thisMonth: BestSet?
            var lastMonth: BestSet?
            var allTime = 0.0
            var beforeThisMonth = 0.0
            for set in group {
                guard let e1rm = PersonalRecordsListView.estimatedOneRepMax(weight: set.weightLbs, reps: set.reps) else { continue }
                allTime = max(allTime, e1rm)
                let ago = weeksAgo(set.date, now: now, calendar: calendar)
                if (0..<weeks).contains(ago) {
                    let index = weeks - 1 - ago
                    weekly[index] = max(weekly[index] ?? 0, e1rm)
                }
                let best = BestSet(weightLbs: set.weightLbs, reps: set.reps, e1rm: e1rm)
                if calendar.isDate(set.date, equalTo: now, toGranularity: .month) {
                    if e1rm > (thisMonth?.e1rm ?? 0) { thisMonth = best }
                } else {
                    if set.date < now { beforeThisMonth = max(beforeThisMonth, e1rm) }
                    if calendar.isDate(set.date, equalTo: lastMonthDate, toGranularity: .month),
                       e1rm > (lastMonth?.e1rm ?? 0) {
                        lastMonth = best
                    }
                }
            }
            let latest = group.max { $0.date < $1.date }?.exerciseName ?? key
            let delta: Double? = {
                guard let thisMonth, beforeThisMonth > 0 else { return nil }
                return thisMonth.e1rm - beforeThisMonth
            }()
            return LiftTrend(key: key, name: latest, setCount: group.count, weeklyE1RM: weekly,
                             allTimeBest: allTime, thisMonth: thisMonth, lastMonth: lastMonth,
                             monthDelta: delta)
        }
    }

    static func snapshot(sets: [LoggedSet], workouts: [LoggedWorkout], restDays: Set<Date> = [],
                         streak: Int, now: Date, calendar: Calendar) -> ProgressSnapshot {
        var snap = ProgressSnapshot()
        snap.equipmentThisWeek = equipmentSets(sets, now: now, calendar: calendar)
        snap.equipmentByWeek = (0..<4).reversed().map { equipmentSets(sets, weeksBack: $0, now: now, calendar: calendar) }
        snap.trainedWeekdays = trainedWeekdays(workouts, now: now, calendar: calendar)
        snap.streak = streak
        snap.workoutsPerWeek = workoutsPerWeek(workouts, now: now, calendar: calendar)
        snap.heatmap = heatmap(sets, now: now, calendar: calendar)
        snap.lifts = liftTrends(sets, now: now, calendar: calendar)
        snap.totalWorkouts = workouts.count
        snap.workoutDays = Set(workouts.map { calendar.startOfDay(for: $0.date) })
        let windowStart = calendar.date(byAdding: .weekOfYear, value: -12, to: weekStart(of: now, calendar: calendar))
            ?? calendar.startOfDay(for: now)
        snap.restDays = Set(restDays.map { calendar.startOfDay(for: $0) }.filter { $0 >= windowStart })
        return snap
    }
}

// MARK: - Service

/// Reads logged sets from local Core Data and computes the Progress / Today stats.
final class ProgressStatsService {
    private let localStorage: LocalStorageService

    init(localStorage: LocalStorageService) {
        self.localStorage = localStorage
    }

    func snapshot(userId: UUID, now: Date = Date(), calendar: Calendar = .current) -> ProgressSnapshot {
        var sets: [LoggedSet] = []
        var workouts: [LoggedWorkout] = []
        for cdWorkout in localStorage.fetchRecentWorkouts(userId: userId, limit: 100000) {
            guard let date = cdWorkout.date, let workoutId = cdWorkout.id else { continue }
            workouts.append(LoggedWorkout(id: workoutId, date: date))
            for cdExercise in localStorage.fetchExercises(workoutId: workoutId) {
                guard let exerciseId = cdExercise.id else { continue }
                let name = cdExercise.name ?? ""
                for cdSet in localStorage.fetchSets(exerciseId: exerciseId) {
                    sets.append(LoggedSet(date: date, exerciseName: name,
                                          weightLbs: cdSet.weightLbs, reps: Int(cdSet.reps)))
                }
            }
        }
        let restDays = Set(localStorage.fetchRestDays(userId: userId).compactMap(\.date))
        return ProgressStats.snapshot(
            sets: sets, workouts: workouts, restDays: restDays,
            streak: localStorage.countConsecutiveWorkoutDays(userId: userId),
            now: now, calendar: ProgressStats.weekCalendar(calendar))
    }
}
