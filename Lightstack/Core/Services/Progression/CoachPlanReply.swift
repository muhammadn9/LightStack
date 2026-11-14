import Foundation

/// One starting set the coach proposes for a lift with no history.
struct StartingSet: Equatable {
    var isWarmup: Bool
    var weight: Double?
    var reps: Int?
    var rir: Int?
    var rest: Int?
}

/// One line of the coach's final ordered list.
struct CoachReplyEntry: Equatable {
    var name: String
    /// nil when the reply gave no decision or one the app does not know (both mean as planned).
    var move: CoachMove?
    /// For `ease`: -2.5 ... -15 (clamped by the app); nil means the default, -5.
    var percent: Double?
    /// The working-set count the coach wants (the app clamps it).
    var sets: Int?
    /// For `swap`: the draft lift this one replaces.
    var replaces: String?
    var reason: String?
    var cue: String?
    var superset: String?
    var muscleGroup: String?
    /// Only used for a lift with no history. Also read from a coach-v3 style `sets` array.
    var startingSets: [StartingSet] = []
}

struct CoachReplyDrop: Equatable {
    var name: String
    var reason: String?
}

/// The coach's plan reply: a summary and one decision per lift. Never numbers for lifts with history.
struct CoachPlanReply: Equatable {
    var summary: String?
    var notes: String?
    var entries: [CoachReplyEntry]
    var dropped: [CoachReplyDrop]

    /// Reads the reply. nil when it is not a JSON object with an `exercises` list. Extra keys, code fences, missing
    /// optional fields, numbers as strings and an old-style `sets` array are all fine.
    static func parse(_ text: String) -> CoachPlanReply? {
        guard let object = JSONReply.object(from: text), let list = object["exercises"] as? [Any] else { return nil }
        var entries: [CoachReplyEntry] = []
        for case let raw as [String: Any] in list {
            guard let name = JSONReply.string(raw["name"]) else { continue }
            var starting = startingSets(raw["starting_sets"])
            // A coach-v3 reply carries its sets in "sets": use them only as starting sets (the app ignores them for
            // a lift with history), and never read a count out of them.
            var count: Int?
            if let array = raw["sets"] as? [Any] {
                if starting.isEmpty { starting = startingSets(array) }
            } else {
                count = JSONReply.int(raw["sets"])
            }
            entries.append(CoachReplyEntry(
                name: name,
                move: CoachMove.parse(JSONReply.string(raw["decision"])),
                percent: JSONReply.double(raw["percent"]),
                sets: count,
                replaces: JSONReply.string(raw["replaces"]),
                reason: JSONReply.string(raw["reason"]),
                cue: JSONReply.string(raw["cue"]),
                superset: JSONReply.string(raw["superset"]),
                muscleGroup: JSONReply.string(raw["muscle_group"]),
                startingSets: starting))
        }
        var dropped: [CoachReplyDrop] = []
        for case let raw as [String: Any] in (object["dropped"] as? [Any]) ?? [] {
            if let name = JSONReply.string(raw["name"]) { dropped.append(CoachReplyDrop(name: name, reason: JSONReply.string(raw["reason"]))) }
        }
        return CoachPlanReply(
            summary: JSONReply.string(object["summary"]).map { InputSanitizer.clipAtWord($0, limit: 400) },
            notes: JSONReply.string(object["coaching_notes"]).map { InputSanitizer.clipAtWord($0, limit: 200) },
            entries: entries, dropped: dropped)
    }

    private static func startingSets(_ value: Any?) -> [StartingSet] {
        var sets: [StartingSet] = []
        for case let raw as [String: Any] in (value as? [Any]) ?? [] {
            let type = JSONReply.string(raw["type"])?.lowercased() ?? "work"
            sets.append(StartingSet(
                isWarmup: type.contains("warm"), weight: JSONReply.double(raw["weight"]), reps: JSONReply.int(raw["reps"]),
                rir: JSONReply.int(raw["rir"]), rest: JSONReply.int(raw["rest"])))
        }
        return sets
    }
}
