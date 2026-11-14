import Foundation

/// What the coach decided for one lift. The app turns it into sets; the coach never writes numbers for a lift with history.
enum CoachMove: String, Codable, Equatable, CaseIterable {
    case asPlanned = "as_planned"
    case push
    case ease
    case goalStep = "goal_step"
    case swap
    case add
    case drop

    /// Reads the model's word for a decision, forgiving case, spaces and dashes. nil for anything unknown.
    static func parse(_ text: String?) -> CoachMove? {
        guard let raw = text?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let key = raw.replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
        switch key {
        case "as_planned", "asplanned", "as-planned", "keep", "hold": return .asPlanned
        case "push": return .push
        case "ease", "reduce", "lighten": return .ease
        case "goal_step", "goalstep", "goal": return .goalStep
        case "swap", "replace": return .swap
        case "add": return .add
        case "drop", "remove": return .drop
        default: return nil
        }
    }

    /// Used in "Coach wanted to push; held: ...".
    var verb: String {
        switch self {
        case .push: return "push"
        case .ease: return "ease"
        case .goalStep: return "take the goal step"
        case .swap: return "swap"
        case .add: return "add"
        case .drop: return "drop"
        case .asPlanned: return "change"
        }
    }

    /// Decisions that change the engine's numbers for a lift that has history.
    var changesDraft: Bool { self == .push || self == .ease || self == .goalStep || self == .swap }
}

/// One lift's decision after the app applied it: what was asked, what happened, and why.
struct LiftDecision: Codable, Equatable {
    var name: String
    /// What was applied to the plan.
    var move: CoachMove
    /// What the coach asked for when the app could not do it (a push held back); nil when the request was applied.
    var requested: CoachMove?
    /// For `ease`: the reduction applied, in percent (negative).
    var percent: Double?
    /// For `swap`: the draft lift this one replaces.
    var replaces: String?
    /// Why a requested move was held back, e.g. "you trained chest about 5 hours ago".
    var held: String?
    /// The reason shown to the athlete: the coach's, with the app's evidence line appended when the coach named none.
    var reason: String
    /// The engine's top set before the decision, e.g. "175x5@2"; nil for a lift with no history.
    var draftTop: String?
    /// The top set in the final plan.
    var finalTop: String?

    /// "As planned", "Pushed by coach", "Eased by coach −5%", "Goal step", "Swapped in for X", "Added",
    /// or "Coach wanted to push; held: <why>".
    var label: String {
        if let held, let requested { return "Coach wanted to \(requested.verb); held: \(held)" }
        switch move {
        case .asPlanned: return "As planned"
        case .push: return "Pushed by coach"
        case .ease:
            let text = percent.map { " \(Self.percentText($0))" } ?? ""
            return "Eased by coach\(text)"
        case .goalStep: return "Goal step"
        case .swap: return replaces.map { "Swapped in for \($0)" } ?? "Swapped in"
        case .add: return "Added"
        case .drop: return "Dropped"
        }
    }

    /// "−5%" (a real minus sign), "+5%".
    static func percentText(_ percent: Double) -> String {
        let magnitude = String(format: "%g", abs(percent))
        return (percent < 0 ? "\u{2212}" : "+") + magnitude + "%"
    }

    /// True when the coach changed something (or was refused): worth a line of its own on the plan screen.
    var isNotable: Bool { move != .asPlanned || held != nil }
}

/// One check the app ran over the finished plan, and what it had to change to make it pass.
struct PlanCheck: Codable, Equatable {
    var id: String
    var title: String
    /// What the app changed so the plan passes; empty when the plan passed as built.
    var adjustments: [String] = []

    var passed: Bool { adjustments.isEmpty }
    var adjusted: Bool { !adjustments.isEmpty }

    enum CodingKeys: String, CodingKey { case id, title, adjustments }
}

/// The coach's plan as shown on the plan screen: summary, one decision per lift, the checks that ran.
struct CoachPlanReview: Codable, Equatable {
    var summary: String
    /// One short coaching sentence from the coach (the old `coaching_notes`).
    var notes: String?
    var decisions: [LiftDecision]
    var checks: [PlanCheck]
    /// "You trained chest, shoulders and arms about 5 hours ago, so today's targets are held or lighter."
    var recencyMessage: String?
    /// True when the coach's reply was missing or unusable and the plan is the app's own, straight from the log.
    var engineOnly: Bool

    init(summary: String = "", notes: String? = nil, decisions: [LiftDecision] = [], checks: [PlanCheck] = [],
         recencyMessage: String? = nil, engineOnly: Bool = false) {
        self.summary = summary
        self.notes = notes
        self.decisions = decisions
        self.checks = checks
        self.recencyMessage = recencyMessage
        self.engineOnly = engineOnly
    }

    enum CodingKeys: String, CodingKey { case summary, notes, decisions, checks, recencyMessage, engineOnly }

    /// Lenient: documents stored by older builds (verdict, changes, safeguards) decode with empty decisions and checks.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = (try? c.decodeIfPresent(String.self, forKey: .summary)) ?? ""
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? nil
        decisions = (try? c.decodeIfPresent([LiftDecision].self, forKey: .decisions)) ?? []
        checks = (try? c.decodeIfPresent([PlanCheck].self, forKey: .checks)) ?? []
        recencyMessage = (try? c.decodeIfPresent(String.self, forKey: .recencyMessage)) ?? nil
        engineOnly = (try? c.decodeIfPresent(Bool.self, forKey: .engineOnly)) ?? false
    }

    var isEmpty: Bool { summary.isEmpty && decisions.isEmpty && checks.isEmpty && recencyMessage == nil && !engineOnly }

    var passedCount: Int { checks.filter(\.passed).count }
    var adjustedChecks: [PlanCheck] { checks.filter(\.adjusted) }

    /// "Checks: 5 of 6 passed, 1 adjusted" ("Checks: 6 of 6 passed" when nothing was adjusted).
    var checksLine: String {
        guard !checks.isEmpty else { return "" }
        var line = "Checks: \(passedCount) of \(checks.count) passed"
        if !adjustedChecks.isEmpty { line += ", \(adjustedChecks.count) adjusted" }
        return line
    }

    func decision(for name: String) -> LiftDecision? {
        decisions.first { ExerciseNameResolver.isMatch($0.name, name) }
    }

    /// One line per lift decision, check and note, for the debug screen.
    var logLines: [String] {
        var lines: [String] = []
        if engineOnly { lines.append("Coach unavailable: plan built from your log") }
        if !summary.isEmpty { lines.append("Summary: \(summary)") }
        if let recencyMessage { lines.append("Recency: \(recencyMessage)") }
        for d in decisions { lines.append("\(d.name): \(d.label) — \(d.reason)") }
        if !checks.isEmpty {
            lines.append(checksLine)
            for check in adjustedChecks { lines.append("Adjusted \(check.title): " + check.adjustments.joined(separator: "; ")) }
        }
        return lines
    }
}

/// Lenient JSON helpers for model replies (numbers may arrive as strings, fences may wrap the object).
enum JSONReply {
    static func object(from text: String) -> [String: Any]? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            trimmed = lines.dropFirst().filter { !$0.hasPrefix("```") }.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func string(_ value: Any?) -> String? {
        if let s = value as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String {
            let cleaned = s.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "lbs", with: "")
                .replacingOccurrences(of: "lb", with: "").replacingOccurrences(of: "\u{2212}", with: "-")
                .trimmingCharacters(in: .whitespaces)
            return Double(cleaned)
        }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        if let d = double(value) { return Int(d.rounded()) }
        return nil
    }
}

/// An agreed goal attempt due today: the lift's top weight may reach `weight` for `reps` (see `PlanGuardrails.RailContext`).
struct GoalAllowance: Equatable {
    var name: String
    var weight: Double
    var reps: Int
}

/// Everything the plan pipeline knows about the athlete besides the exercise history.
struct PlanCoachContext {
    var focus: CoachFocus = .hypertrophy
    var restPreference: Int = RestPreference.fallbackSeconds
    /// Latest review target per exercise name (lowercased) with the session date it came from.
    var nextTargets: [String: DatedTarget] = [:]
    /// Muscle (canonical) -> last trained.
    var recency: [String: MuscleRecency] = [:]
    var now: Date = Date()
    /// Goal attempts due today (one per lift); the e1RM ceiling for those lifts is the attempt's.
    var goalAllowances: [GoalAllowance] = []
    /// Low fuel today (and why): no lift may progress. nil = no hold.
    var fuelHold: FuelAssessment?

    func goalAllowance(for name: String) -> GoalAllowance? {
        goalAllowances.first { ExerciseNameResolver.isMatch($0.name, name) }
    }

    struct DatedTarget: Equatable {
        var target: NextTarget
        var date: Date
    }

    func nextTarget(for name: String, lastSessionDate: Date?) -> NextTarget? {
        let hit = nextTargets[name.lowercased()]
            ?? nextTargets.first { ExerciseNameResolver.isMatch($0.key, name) }?.value
        guard let hit else { return nil }
        // A target older than the exercise's latest session is stale.
        if let last = lastSessionDate, hit.date < last.addingTimeInterval(-12 * 3600) { return nil }
        return hit.target
    }

    func isFresh(muscle: String) -> Bool {
        recency[muscle]?.isFresh(now: now) ?? false
    }
}
