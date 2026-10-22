import Foundation

enum PlanChangeType: String, Codable, Equatable, CaseIterable {
    case reorder, swap, drop, add, setCount, loadAdjust
}

/// One edit the coach proposed while reviewing the draft, and what the app did with it.
struct PlanChange: Codable, Equatable {
    var type: PlanChangeType
    var exercise: String
    var detail: String
    var reason: String
    /// For `setCount`: the working-set count asked for.
    var sets: Int?
    /// For `loadAdjust`: relative change in percent (-10 = ten percent lighter).
    var percent: Double?
    /// True when the plan now reflects the change (possibly clamped, see `note`).
    var applied: Bool = false
    /// What the app did, e.g. "clamped to -15%", or why it was refused.
    var note: String?
}

/// The coach's review of the draft structure, shown on the plan screen.
struct CoachPlanReview: Codable, Equatable {
    enum Verdict: String, Codable, Equatable { case sound, adjusted }

    var verdict: Verdict
    var summary: String
    var changes: [PlanChange]
    /// Deterministic rules that fired regardless of the AI (recency, set caps, ordering).
    var safeguards: [String] = []

    static let empty = CoachPlanReview(verdict: .sound, summary: "", changes: [])

    var isEmpty: Bool { summary.isEmpty && changes.isEmpty && safeguards.isEmpty }
    /// Changes that are reflected in the plan.
    var appliedChanges: [PlanChange] { changes.filter(\.applied) }

    /// One line per applied change or safeguard, for the debug screen.
    var logLines: [String] {
        var lines: [String] = []
        if !summary.isEmpty { lines.append("Review (\(verdict.rawValue)): \(summary)") }
        for c in changes {
            lines.append("Change \(c.type.rawValue) \(c.exercise): \(c.detail) — \(c.reason) [\(c.applied ? "applied" : "not applied")\(c.note.map { ": \($0)" } ?? "")]")
        }
        lines.append(contentsOf: safeguards.map { "Safeguard: \($0)" })
        return lines
    }

    // MARK: - Parsing the model's reply

    /// Reads `{"review": {...}}` out of a plan reply. nil when there is no review object.
    static func parse(fromReply text: String) -> CoachPlanReview? {
        guard let object = JSONReply.object(from: text),
              let review = object["review"] as? [String: Any] else { return nil }
        let verdict = (review["verdict"] as? String).flatMap { Verdict(rawValue: $0.lowercased()) } ?? .sound
        let summary = JSONReply.string(review["summary"]) ?? ""
        var changes: [PlanChange] = []
        for raw in (review["changes"] as? [[String: Any]]) ?? [] {
            guard let typeText = JSONReply.string(raw["type"]),
                  let type = PlanChangeType(rawValue: typeText) ?? PlanChangeType.allCases.first(where: { $0.rawValue.lowercased() == typeText.lowercased() }),
                  let exercise = JSONReply.string(raw["exercise"]), !exercise.isEmpty else { continue }
            changes.append(PlanChange(
                type: type, exercise: exercise,
                detail: JSONReply.string(raw["detail"]) ?? "",
                reason: JSONReply.string(raw["reason"]) ?? "",
                sets: JSONReply.int(raw["sets"]),
                percent: JSONReply.double(raw["percent"])))
        }
        return CoachPlanReview(verdict: verdict,
                               summary: String(summary.prefix(400)), changes: Array(changes.prefix(12)))
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
                .replacingOccurrences(of: "lb", with: "").trimmingCharacters(in: .whitespaces)
            return Double(cleaned)
        }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        if let d = double(value) { return Int(d.rounded()) }
        return nil
    }
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
