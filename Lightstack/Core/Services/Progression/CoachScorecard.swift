import Foundation

/// Is the coach helping? Over the last sessions, how did the lifts where the coach CHANGED the engine's draft
/// (push, ease, goal step, swap) turn out, against the lifts left as planned. Pure; reads only stored decisions that
/// carry a decision and an outcome, so documents from older builds are ignored.
struct CoachScorecard: Equatable {

    struct Tally: Equatable {
        var onTarget = 0
        var missed = 0
        var total: Int { onTarget + missed }
    }

    /// Decisions where the coach changed the draft.
    var changed = Tally()
    /// Decisions left as planned (the engine's own numbers).
    var asPlanned = Tally()
    /// Sessions that contributed at least one scored decision.
    var sessions = 0

    /// How many recent sessions the scorecard looks at.
    static let defaultSessions = 20

    var isEmpty: Bool { changed.total == 0 && asPlanned.total == 0 }

    /// "Coach changes: 6 (4 on target, 2 missed) · As planned: 18 (15 on target, 3 missed)"
    var line: String {
        guard !isEmpty else { return "Coach scorecard: no scored decisions yet" }
        func part(_ title: String, _ t: Tally) -> String { "\(title): \(t.total) (\(t.onTarget) on target, \(t.missed) missed)" }
        return part("Coach changes", changed) + " · " + part("As planned", asPlanned)
    }

    /// - Parameter decisionsPerSession: newest session first.
    static func compute(decisionsPerSession: [[CoachDecision]], lastSessions: Int = defaultSessions) -> CoachScorecard {
        var card = CoachScorecard()
        var used = 0
        for decisions in decisionsPerSession {
            guard used < lastSessions else { break }
            var counted = false
            for d in decisions {
                guard let raw = d.move, let move = CoachMove(rawValue: raw), let outcome = d.outcome else { continue }
                let hit = outcome.hit
                switch move {
                case .push, .ease, .goalStep, .swap:
                    if hit { card.changed.onTarget += 1 } else { card.changed.missed += 1 }
                    counted = true
                case .asPlanned:
                    if hit { card.asPlanned.onTarget += 1 } else { card.asPlanned.missed += 1 }
                    counted = true
                case .add, .drop:
                    continue
                }
            }
            if counted { used += 1 }
        }
        card.sessions = used
        return card
    }

    static func compute(memory: CoachMemoryIndex, lastSessions: Int = defaultSessions) -> CoachScorecard {
        compute(decisionsPerSession: memory.records.map(\.document.decisions), lastSessions: lastSessions)
    }
}
