import Foundation

struct ImportedSet: Equatable {
    let weightLbs: Double
    let reps: Int
    let rir: Int?
}

struct ImportedExercise: Equatable {
    let name: String
    let muscleGroup: String
    let notes: String?
    let sets: [ImportedSet]
    /// Exercises in one workout sharing a label form a superset; nil = not in a superset.
    var supersetLabel: String? = nil
}

struct ImportedWorkout: Equatable {
    let date: Date
    let name: String
    let notes: String?
    let exercises: [ImportedExercise]
}

enum ImportSkipReason: Equatable {
    case noDate(workoutName: String?)
    case noExercises(workoutName: String?, date: Date?)
}

struct WorkoutImportParseResult: Equatable {
    let workouts: [ImportedWorkout]
    let skipped: [ImportSkipReason]
}

enum WorkoutImportError: Error, Equatable {
    case noJSONFound
    case invalidJSON
    case noWorkouts
}

enum WorkoutImportParser {

    static func parse(_ text: String) throws -> WorkoutImportParseResult {
        let cleaned = text.replacingOccurrences(of: "```json", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "```", with: "")
        guard let jsonString = extractJSON(cleaned) else { throw WorkoutImportError.noJSONFound }
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            throw WorkoutImportError.invalidJSON
        }

        let rawWorkouts: [Any]
        if let array = root as? [Any] {
            rawWorkouts = array
        } else if let dict = root as? [String: Any], let array = dict["workouts"] as? [Any] {
            rawWorkouts = array
        } else {
            throw WorkoutImportError.invalidJSON
        }

        var workouts: [ImportedWorkout] = []
        var skipped: [ImportSkipReason] = []

        for raw in rawWorkouts {
            guard let dict = raw as? [String: Any] else { continue }
            let rawName = string(dict["name"])
            guard let date = parseDate(dict["date"]) else {
                skipped.append(.noDate(workoutName: rawName))
                continue
            }
            var combinedCounter = 0
            let exercises = ((dict["exercises"] as? [Any]) ?? []).flatMap { parseExercises($0, combinedCounter: &combinedCounter) }
            if exercises.isEmpty {
                skipped.append(.noExercises(workoutName: rawName, date: date))
                continue
            }
            workouts.append(ImportedWorkout(
                date: date,
                name: rawName ?? "Imported Workout",
                notes: string(dict["notes"]),
                exercises: exercises
            ))
        }

        if workouts.isEmpty && skipped.isEmpty { throw WorkoutImportError.noWorkouts }
        return WorkoutImportParseResult(workouts: workouts, skipped: skipped)
    }

    // MARK: - Helpers

    private static func extractJSON(_ text: String) -> String? {
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
        let closer: Character = text[start] == "{" ? "}" : "]"
        guard let end = text.lastIndex(of: closer), end > start else { return nil }
        return String(text[start...end])
    }

    private static func isUnknown(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t.isEmpty || t == "n/a" || t == "null"
    }

    /// Trimmed string, or nil when unknown.
    private static func string(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        let s: String
        if let str = value as? String { s = str } else if let n = value as? NSNumber { s = n.stringValue } else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return isUnknown(t) ? nil : t
    }

    /// Leading number from a number or string such as "135 lbs".
    private static func number(_ value: Any?) -> Double? {
        guard let value, !(value is NSNull) else { return nil }
        if let n = value as? NSNumber, !(value is Bool) { return n.doubleValue }
        guard let s = string(value),
              let range = s.range(of: #"^-?\d+(\.\d+)?"#, options: .regularExpression) else { return nil }
        return Double(s[range])
    }

    private static func parseRIR(_ value: Any?) -> Int? {
        guard let n = number(value) else { return nil }
        let rounded = Int(n.rounded(.down))
        return (0...10).contains(rounded) ? rounded : nil
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let s = string(value) else { return nil }
        let calendar = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateFormat = "yyyy-MM-dd"
        if let day = dayFormatter.date(from: s) {
            return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)
        }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: s)
    }

    private static func parseExercises(_ raw: Any, combinedCounter: inout Int) -> [ImportedExercise] {
        if let combined = parseCombined(raw, counter: &combinedCounter) { return combined }
        return parseExercise(raw).map { [$0] } ?? []
    }

    private static func parseExercise(_ raw: Any) -> ImportedExercise? {
        guard let dict = raw as? [String: Any], let name = string(dict["name"]) else { return nil }
        let sets = ((dict["sets"] as? [Any]) ?? []).compactMap { parseSet($0) }
        guard !sets.isEmpty else { return nil }
        let muscle = string(dict["muscle_group"]) ?? WorkoutSessionService.inferMuscleGroup(name)
        return ImportedExercise(name: name, muscleGroup: muscle, notes: string(dict["notes"]), sets: sets,
                                supersetLabel: string(dict["superset"]))
    }

    // MARK: - Combined superset form ("A x B" with "setA / setB" entries)

    private static func parseCombined(_ raw: Any, counter: inout Int) -> [ImportedExercise]? {
        guard let dict = raw as? [String: Any], let rawName = string(dict["name"]),
              let entries = dict["sets"] as? [Any], !entries.isEmpty else { return nil }
        let names = splitName(rawName)
        guard names.count >= SupersetGroup.minMembers, names.count <= SupersetGroup.maxMembers else { return nil }

        var perExercise = Array(repeating: [ImportedSet](), count: names.count)
        for entry in entries {
            guard let text = entry as? String else { return nil }
            let parts = text.components(separatedBy: " / ")
            guard parts.count == names.count else { return nil }
            var parsed: [ImportedSet] = []
            for part in parts {
                guard let set = parseSetText(part) else { return nil }
                parsed.append(set)
            }
            for (k, set) in parsed.enumerated() { perExercise[k].append(set) }
        }

        counter += 1
        let label = "__combined\(counter)"
        let notes = string(dict["notes"])
        return names.enumerated().map { k, name in
            ImportedExercise(name: name, muscleGroup: WorkoutSessionService.inferMuscleGroup(name),
                             notes: k == 0 ? notes : nil, sets: perExercise[k], supersetLabel: label)
        }
    }

    /// Splits "A x B" on a case-insensitive, space-surrounded "x"; trims trailing colons.
    private static func splitName(_ name: String) -> [String] {
        let cleaned = name.trimmingCharacters(in: CharacterSet(charactersIn: ": ").union(.whitespacesAndNewlines))
        let parts = cleaned.replacingOccurrences(of: #"\s+[xX]\s+"#, with: "\u{1F}", options: .regularExpression)
            .components(separatedBy: "\u{1F}")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ": ").union(.whitespacesAndNewlines)) }
        return parts.contains(where: { $0.isEmpty }) ? [cleaned] : parts
    }

    /// Parses text like "50 x 15 abt 2 rir" (weight x reps, optional RIR).
    static func parseSetText(_ text: String) -> ImportedSet? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let m = t.range(of: #"^(bw|\d+(?:\.\d+)?)\s*(?:lbs?|kgs?)?\s*[xX]\s*(\d+)"#,
                              options: [.regularExpression, .caseInsensitive]) else { return nil }
        let head = String(t[m])
        let headParts = head.components(separatedBy: CharacterSet(charactersIn: "xX"))
        guard let repsText = headParts.last?.trimmingCharacters(in: .whitespaces), let reps = Int(repsText) else { return nil }
        let weightMatch = head.range(of: #"^\d+(?:\.\d+)?"#, options: .regularExpression)
        let weight = weightMatch.flatMap { Double(head[$0]) } ?? 0
        let rest = String(t[m.upperBound...])
        var rir: Int?
        if let r = rest.range(of: #"(?:abt|about|~|@)?\s*(\d+)\s*rir"#, options: [.regularExpression, .caseInsensitive]),
           let n = rest[r].range(of: #"\d+"#, options: .regularExpression) {
            rir = Int(rest[r][n])
        } else if let r = rest.range(of: #"rir\s*(\d+)"#, options: [.regularExpression, .caseInsensitive]),
                  let n = rest[r].range(of: #"\d+"#, options: .regularExpression) {
            rir = Int(rest[r][n])
        }
        if let v = rir, !(0...10).contains(v) { rir = nil }
        return ImportedSet(weightLbs: weight, reps: reps, rir: rir)
    }

    private static func parseSet(_ raw: Any) -> ImportedSet? {
        guard let dict = raw as? [String: Any],
              let repsValue = number(dict["reps"]) else { return nil }
        let reps = Int(repsValue)
        guard reps >= 0 else { return nil }  // 0 = unable, matching in-app logging
        return ImportedSet(
            weightLbs: max(0, number(dict["weight_lbs"]) ?? 0),
            reps: reps,
            rir: parseRIR(dict["rir"])
        )
    }
}
