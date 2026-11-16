import Foundation

// MARK: - Input

/// One exercise as it was logged in one workout (sets in set order).
struct LiftEntry {
    let workoutId: UUID
    let date: Date
    let workoutName: String
    let exerciseName: String
    let muscleGroup: String
    /// Logged weights are per arm (single-side exercise).
    let isPerArm: Bool
    let sets: [HistorySet]
}

// MARK: - Output

struct LiftSet: Equatable {
    let weightLbs: Double
    let reps: Int
    let rir: Int?
    let isWarmup: Bool
    let e1rm: Double
}

/// One workout's worth of a lift.
struct LiftSession: Identifiable, Equatable {
    let workoutId: UUID
    let date: Date
    let workoutName: String
    /// Every logged set with weight and reps, in order, warm-ups flagged.
    let sets: [LiftSet]
    /// Best estimated 1RM among the working sets.
    let e1rm: Double
    /// Heaviest working-set weight.
    let topWeightLbs: Double
    /// Working-set weight x reps (doubled for per-arm lifts, like total volume elsewhere in the app).
    let volumeLbs: Double
    var id: UUID { workoutId }
}

struct LiftBest: Equatable {
    let weightLbs: Double
    let reps: Int
    let e1rm: Double
    let date: Date
    let workoutId: UUID
}

/// Change in estimated 1RM over the last 30 days.
enum LiftChange: Equatable {
    /// No session from before the window to compare with.
    case new
    case even
    /// Signed change in lbs (positive = up).
    case delta(Double)
}

struct LiftSummary: Identifiable, Equatable {
    let key: String
    let name: String
    let muscleGroup: String
    let isPerArm: Bool
    /// Oldest first.
    let sessions: [LiftSession]
    /// Estimated 1RM of the latest session.
    let currentE1RM: Double
    let change: LiftChange
    let bestSet: LiftBest
    let heaviest: LiftBest
    var id: String { key }

    var sessionCount: Int { sessions.count }
    var firstDate: Date? { sessions.first?.date }
    var lastDate: Date? { sessions.last?.date }
    /// Newest first.
    var recentSessions: [LiftSession] { sessions.reversed() }
}

// MARK: - Calculation

enum LiftStats {
    static let changeWindowDays = 30

    /// Every strength lift ever logged, A to Z. Variants of one name share a lift
    /// (same grouping as the personal-records list); cardio is left out.
    static func summaries(_ entries: [LiftEntry], now: Date, calendar: Calendar) -> [LiftSummary] {
        var groups: [String: [LiftEntry]] = [:]
        for entry in entries where !isCardio(entry.muscleGroup) {
            groups[PersonalRecordsListView.exerciseKey(entry.exerciseName), default: []].append(entry)
        }
        let cutoff = calendar.date(byAdding: .day, value: -changeWindowDays, to: now) ?? now
        let summaries = groups.compactMap { key, group in
            summary(key: key, entries: group, cutoff: cutoff)
        }
        return summaries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func isCardio(_ muscleGroup: String) -> Bool {
        muscleGroup.caseInsensitiveCompare("Cardio") == .orderedSame
    }

    private static func summary(key: String, entries: [LiftEntry], cutoff: Date) -> LiftSummary? {
        // One session per workout, even when the lift appears twice in it.
        var byWorkout: [UUID: [LiftEntry]] = [:]
        for entry in entries { byWorkout[entry.workoutId, default: []].append(entry) }

        var sessions: [LiftSession] = []
        var bestSet: LiftBest?
        var heaviest: LiftBest?
        let perArmByWorkout = Dictionary(uniqueKeysWithValues: byWorkout.map { id, group in
            (id, group.contains { $0.isPerArm })
        })

        for (workoutId, group) in byWorkout {
            guard let first = group.first else { continue }
            let valid = group.flatMap { $0.sets }.filter {
                PersonalRecordsListView.estimatedOneRepMax(weight: $0.weight, reps: $0.reps) != nil
            }
            guard !valid.isEmpty else { continue }
            var flags = SetStyleDetector.warmupFlags(valid)
            if flags.allSatisfy({ $0 }) { flags = flags.map { _ in false }}
            let sets = zip(valid, flags).map {
                LiftSet(weightLbs: $0.weight, reps: $0.reps, rir: $0.rir, isWarmup: $1,
                        e1rm: OneRepMax.estimate(weight: $0.weight, reps: $0.reps))
            }
            let working = sets.filter { !$0.isWarmup }
            guard let topE1RM = working.map(\.e1rm).max(),
                  let topWeight = working.map(\.weightLbs).max() else { continue }
            let side = (perArmByWorkout[workoutId] ?? false) ? 2.0 : 1.0
            let volume = working.reduce(0) { $0 + $1.weightLbs * Double($1.reps) } * side
            sessions.append(LiftSession(workoutId: workoutId, date: first.date, workoutName: first.workoutName,
                                        sets: sets, e1rm: topE1RM, topWeightLbs: topWeight, volumeLbs: volume))
            for set in working {
                let candidate = LiftBest(weightLbs: set.weightLbs, reps: set.reps, e1rm: set.e1rm,
                                         date: first.date, workoutId: workoutId)
                if bestSet == nil || (candidate.e1rm, candidate.date) > (bestSet?.e1rm ?? 0, bestSet?.date ?? .distantPast) {
                    bestSet = candidate
                }
                if heaviest == nil || (candidate.weightLbs, candidate.date) > (heaviest?.weightLbs ?? 0, heaviest?.date ?? .distantPast) {
                    heaviest = candidate
                }
            }
        }

        sessions.sort { $0.date != $1.date ? $0.date < $1.date : $0.workoutId.uuidString < $1.workoutId.uuidString }
        guard let latestSession = sessions.last, let bestSet, let heaviest,
              let latestEntry = entries.max(by: { $0.date < $1.date }) else { return nil }

        return LiftSummary(
            key: key,
            name: latestEntry.exerciseName,
            muscleGroup: latestEntry.muscleGroup,
            isPerArm: latestEntry.isPerArm,
            sessions: sessions,
            currentE1RM: latestSession.e1rm,
            change: change(sessions: sessions, cutoff: cutoff),
            bestSet: bestSet,
            heaviest: heaviest)
    }

    /// Latest session's 1RM against the latest session on or before the cutoff (30 days ago).
    static func change(sessions: [LiftSession], cutoff: Date) -> LiftChange {
        guard let latest = sessions.last,
              let before = sessions.dropLast().last(where: { $0.date <= cutoff }) else { return .new }
        let delta = latest.e1rm - before.e1rm
        return abs(delta) < 0.5 ? .even : .delta(delta)
    }
}
