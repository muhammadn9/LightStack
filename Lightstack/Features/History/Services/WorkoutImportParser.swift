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
            let exercises = ((dict["exercises"] as? [Any]) ?? []).compactMap { parseExercise($0) }
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

    private static func parseExercise(_ raw: Any) -> ImportedExercise? {
        guard let dict = raw as? [String: Any], let name = string(dict["name"]) else { return nil }
        let sets = ((dict["sets"] as? [Any]) ?? []).compactMap { parseSet($0) }
        guard !sets.isEmpty else { return nil }
        let muscle = string(dict["muscle_group"]) ?? WorkoutSessionService.inferMuscleGroup(name)
        return ImportedExercise(name: name, muscleGroup: muscle, notes: string(dict["notes"]), sets: sets)
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
