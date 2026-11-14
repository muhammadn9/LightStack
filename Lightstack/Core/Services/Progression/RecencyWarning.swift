import Foundation

/// A session-level heads-up: the muscles of the requested workout were trained hard hours ago.
/// Pure. The planning path exposes it (`AppliedPlan.recencyWarning`, `PlanDraftBuilder.recencyWarning`) so the UI
/// and the coach can say so; the engine separately refuses to progress the affected lifts.
struct RecencyWarning: Equatable {
    /// Display names, e.g. ["chest", "shoulders", "arms"] (triceps, biceps and forearms read as "arms").
    var muscles: [String]
    /// Hours since the most recently trained of them, rounded.
    var hoursAgo: Int
    /// "You trained chest, shoulders and arms about 5 hours ago."
    var message: String
    /// "about 5 hours" (no "ago").
    var hoursText: String = ""

    /// Hard sets (RIR 3 or less) a muscle needs before it counts.
    static var minHardSets: Int { ProgressionEngine.muscleRecentMinHardSets }
    /// How recent counts as "hours ago".
    static var withinHours: Double { ProgressionEngine.muscleRecentHours }

    /// - Parameters:
    ///   - lifts: the exercises of the requested workout (name and muscle group).
    ///   - recency: last training per canonical muscle (`MuscleRecencyBuilder`).
    /// nil when none of the workout's primary muscles had `minHardSets`+ hard sets within `withinHours`.
    static func make(lifts: [(name: String, muscleGroup: String)], recency: [String: MuscleRecency],
                     now: Date) -> RecencyWarning? {
        var affected: [(label: String, hours: Double)] = []
        var seenKeys = Set<String>()
        for lift in lifts {
            let muscle = MuscleGroups.canonical(forExercise: lift.name, muscleGroup: lift.muscleGroup)
            guard seenKeys.insert(muscle).inserted, let r = recency[muscle],
                  r.hardSets >= minHardSets, r.hoursSince(now) <= withinHours else { continue }
            affected.append((label(for: muscle), r.hoursSince(now)))
        }
        guard !affected.isEmpty else { return nil }
        var labels: [String] = []
        for item in affected where !labels.contains(item.label) { labels.append(item.label) }
        let hours = affected.map(\.hours).min() ?? 0
        let rounded = max(0, Int(hours.rounded()))
        return RecencyWarning(
            muscles: labels, hoursAgo: rounded,
            message: "You trained \(list(labels)) \(hoursPhrase(hours)) ago.", hoursText: hoursPhrase(hours))
    }

    /// For the athlete: "You trained chest, shoulders and arms about 5 hours ago, so today's targets are held or lighter."
    var athleteText: String {
        (message.hasSuffix(".") ? String(message.dropLast()) : message) + ", so today's targets are held or lighter."
    }

    /// The first line of the coach's message: "NOTE: chest, shoulders and arms were trained about 5 hours ago; the app
    /// has already held or reduced those lifts."
    var promptNote: String {
        "NOTE: \(Self.list(muscles)) \(muscles.count == 1 ? "was" : "were") trained \(hoursText) ago; the app has already held or reduced those lifts."
    }

    /// "5 hours", "1 hour", "less than an hour" (with "about" where it is a rounded number).
    static func hoursPhrase(_ hours: Double) -> String {
        if hours < 1 { return "less than an hour" }
        let n = Int(hours.rounded())
        return "about \(n) hour\(n == 1 ? "" : "s")"
    }

    static func displayLabel(for muscle: String) -> String { label(for: muscle) }

    private static func label(for muscle: String) -> String {
        ["triceps", "biceps", "forearms"].contains(muscle) ? "arms" : muscle
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and " + (items.last ?? "")
        }
    }
}

extension PlanCoachContext {

    /// The muscle had `RecencyWarning.minHardSets`+ hard sets within `RecencyWarning.withinHours`.
    func isVeryRecent(muscle: String) -> Bool {
        guard let r = recency[muscle] else { return false }
        return r.hardSets >= RecencyWarning.minHardSets && r.hoursSince(now) <= RecencyWarning.withinHours
    }

    func recencyWarning(forLifts lifts: [(name: String, muscleGroup: String)]) -> RecencyWarning? {
        RecencyWarning.make(lifts: lifts, recency: recency, now: now)
    }
}
