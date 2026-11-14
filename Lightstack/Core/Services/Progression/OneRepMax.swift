import Foundation

/// The one estimated-one-rep-max formula for the whole app (Epley: weight x (1 + reps / 30)).
///
/// RIR is deliberately NOT folded in: most history has no RIR, and mixing "reps + reserve" with plain reps would make
/// two sessions of the same lift incomparable. Personal records, charts, the engine's caps, the brief and the goal
/// block all use this exact number so the same lift never shows two different e1RMs.
enum OneRepMax {

    static func estimate(weight: Double, reps: Int) -> Double {
        weight * (1 + Double(reps) / 30)
    }

    /// Same formula for callers that already hold reps as a Double.
    static func estimate(weight: Double, reps: Double) -> Double {
        weight * (1 + reps / 30)
    }

    /// How many sessions of a lift count as "now" when the coach talks about the athlete's current strength.
    static let recentSessions = ExerciseHistoryGroup.recentWindow

    /// The athlete's CURRENT estimate: the best e1RM among the top sets of the last `recentSessions` sessions
    /// (newest first). This is the value the brief's e1RM trend ends on and the goal line's "now".
    static func recentBest(sessions: [HistorySession]) -> Double? {
        let values = sessions.prefix(recentSessions).compactMap { session -> Double? in
            ProgressionEngine.referenceTop(SetStyleDetector.splitWarmups(session.sets).working.filter { $0.weight > 0 })?.e1RM
        }
        return values.max()
    }

    /// The weight that carries `e1RM` at `reps`.
    static func weight(forE1RM e1RM: Double, reps: Int) -> Double {
        e1RM / (1 + Double(reps) / 30)
    }
}
