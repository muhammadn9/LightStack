import Foundation

/// One set's target as the coach states it. All fields are free-form strings
/// ("40 lbs", "8-10", "1-2") because that is how the coach writes them.
struct SetTarget: Codable, Equatable, Hashable {
    var weight: String?
    var reps: String?
    var rir: String?

    init(weight: String? = nil, reps: String? = nil, rir: String? = nil) {
        self.weight = weight
        self.reps = reps
        self.rir = rir
    }

    /// Weight text for a set row: the leading number, or "BW". Empty when unusable.
    var prefillWeight: String {
        guard let raw = weight?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return "" }
        let upper = raw.uppercased()
        if upper.contains("BW") || upper.contains("BODYWEIGHT") { return "BW" }
        if let first = raw.components(separatedBy: " ").first, Double(first) != nil { return first }
        if let range = raw.range(of: #"\d+(\.\d+)?"#, options: .regularExpression) { return String(raw[range]) }
        return ""
    }

    /// First integer in the reps text ("8-10" -> "8"). Empty when none.
    var prefillReps: String { SetTarget.firstInteger(in: reps) }

    /// Lower bound of the RIR text ("1-2" -> "1"), matching import behaviour. Empty when none.
    var prefillRir: String { SetTarget.firstInteger(in: rir) }

    private static func firstInteger(in text: String?) -> String {
        guard let text, let range = text.range(of: #"\d+"#, options: .regularExpression) else { return "" }
        return String(text[range])
    }

    /// "Set 1 · 40 lbs × 8 · RIR 2" — only the parts that exist.
    func summaryLine(position: Int) -> String {
        var parts = ["Set \(position)"]
        var load = ""
        if let weight, !weight.isEmpty { load = weight }
        if let reps, !reps.isEmpty { load += load.isEmpty ? "\(reps) reps" : " × \(reps)" }
        if !load.isEmpty { parts.append(load) }
        if let rir, !rir.isEmpty { parts.append("RIR \(rir)") }
        return parts.joined(separator: " · ")
    }

    /// "40 / 45 / 50 lbs" when every weight shares a unit, else the raw weights joined.
    static func compactWeights(_ sets: [SetTarget]) -> String? {
        let weights = sets.compactMap { $0.weight?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !weights.isEmpty else { return nil }
        let split = weights.map { w -> (String, String) in
            let pieces = w.split(separator: " ", maxSplits: 1).map(String.init)
            return (pieces.first ?? w, pieces.count > 1 ? pieces[1] : "")
        }
        let units = Set(split.map { $0.1 })
        if units.count == 1, let unit = units.first {
            let numbers = split.map { $0.0 }.joined(separator: " / ")
            return unit.isEmpty ? numbers : "\(numbers) \(unit)"
        }
        return weights.joined(separator: " / ")
    }
}

/// Represents a modification the AI suggests to the current workout.
/// `targetWeight` is a free-form string ("130 lbs") to match how workout
/// generation already records it — there is no numeric weight column on
/// `Exercise`; it is carried in `coachNote` as a "Target: …" segment.
/// `sets` (last associated value) holds optional per-set targets for pyramids,
/// ramps and top sets; empty means one target applies to every set.
enum WorkoutModification {
    case addExercise(name: String, muscleGroup: String, targetSets: Int, targetReps: String?, targetRir: String?, restSeconds: Int?, targetWeight: String?, note: String?, sets: [SetTarget] = [])
    case removeExercise(name: String)
    case modifyExercise(name: String, newTargetSets: Int?, newTargetReps: String?, newTargetRir: String?, newRest: Int?, newTargetWeight: String?, note: String?, sets: [SetTarget] = [])
    case replaceExercise(oldName: String, newName: String, muscleGroup: String, targetSets: Int, targetReps: String?, targetRir: String?, restSeconds: Int?, targetWeight: String?, note: String?, sets: [SetTarget] = [])

    /// Short header for a confirmation card, e.g. "Modify · Dumbbell Shoulder Press".
    var title: String {
        switch self {
        case .addExercise(let name, _, _, _, _, _, _, _, _): return "Add · \(name)"
        case .removeExercise(let name): return "Remove · \(name)"
        case .modifyExercise(let name, _, _, _, _, _, _, _): return "Modify · \(name)"
        case .replaceExercise(let oldName, let newName, _, _, _, _, _, _, _, _): return "Replace · \(oldName) → \(newName)"
        }
    }

    /// Bullet lines under the title: per-set lines when sets exist, else the target summary.
    var detailLines: [String] {
        switch self {
        case .removeExercise:
            return []
        case .addExercise(_, let muscleGroup, let sets, let reps, let rir, _, let weight, _, let perSet):
            return Self.details(setCount: sets, reps: reps, rir: rir, weight: weight, perSet: perSet, muscleGroup: muscleGroup)
        case .modifyExercise(_, let sets, let reps, let rir, let rest, let weight, _, let perSet):
            var lines = Self.details(setCount: sets, reps: reps, rir: rir, weight: weight, perSet: perSet, muscleGroup: nil)
            if let rest { lines.append("Rest \(rest)s") }
            return lines
        case .replaceExercise(_, _, let muscleGroup, let sets, let reps, let rir, _, let weight, _, let perSet):
            return Self.details(setCount: sets, reps: reps, rir: rir, weight: weight, perSet: perSet, muscleGroup: muscleGroup)
        }
    }

    /// The coach's short cue, if any.
    var noteText: String? {
        let raw: String?
        switch self {
        case .addExercise(_, _, _, _, _, _, _, let note, _): raw = note
        case .removeExercise: raw = nil
        case .modifyExercise(_, _, _, _, _, _, let note, _): raw = note
        case .replaceExercise(_, _, _, _, _, _, _, _, let note, _): raw = note
        }
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// One-line confirmation shown in chat after applying,
    /// e.g. "✓ Updated Dumbbell Shoulder Press: 3 sets — 40 / 45 / 50 lbs".
    var appliedSummary: String {
        switch self {
        case .removeExercise(let name):
            return "✓ Removed \(name)"
        case .addExercise(let name, _, let sets, _, _, _, let weight, _, let perSet):
            return "✓ Added \(name): " + Self.shortTargets(setCount: sets, weight: weight, perSet: perSet)
        case .modifyExercise(let name, let sets, _, _, _, let weight, _, let perSet):
            let tail = Self.shortTargets(setCount: sets, weight: weight, perSet: perSet)
            return tail.isEmpty ? "✓ Updated \(name)" : "✓ Updated \(name): \(tail)"
        case .replaceExercise(let oldName, let newName, _, let sets, _, _, _, let weight, _, let perSet):
            return "✓ Replaced \(oldName) with \(newName): " + Self.shortTargets(setCount: sets, weight: weight, perSet: perSet)
        }
    }

    private static func shortTargets(setCount: Int?, weight: String?, perSet: [SetTarget]) -> String {
        var text = ""
        if let setCount { text = "\(setCount) sets" }
        let weights = perSet.isEmpty ? weight : SetTarget.compactWeights(perSet)
        if let weights, !weights.isEmpty { text += text.isEmpty ? weights : " — \(weights)" }
        return text
    }

    private static func details(setCount: Int?, reps: String?, rir: String?, weight: String?, perSet: [SetTarget], muscleGroup: String?) -> [String] {
        if !perSet.isEmpty {
            return perSet.enumerated().map { $1.summaryLine(position: $0 + 1) }
        }
        var parts: [String] = []
        if let setCount { parts.append("\(setCount) sets") }
        if let reps, !reps.isEmpty { parts.append("\(reps) reps") }
        if let rir, !rir.isEmpty { parts.append("RIR \(rir)") }
        if let weight, !weight.isEmpty { parts.append(weight) }
        var lines: [String] = []
        if !parts.isEmpty { lines.append(parts.joined(separator: " · ")) }
        if let muscleGroup, !muscleGroup.isEmpty { lines.append(muscleGroup) }
        return lines
    }

    var description: String {
        switch self {
        case .addExercise(let name, let muscleGroup, let sets, _, _, _, let weight, _, _):
            var text = "Add \(name) (\(muscleGroup)) - \(sets) sets"
            if let weight = weight { text += " @ \(weight)" }
            return text
        case .removeExercise(let name):
            return "Remove \(name)"
        case .modifyExercise(let name, let newSets, let newReps, let newRir, _, let newWeight, let note, _):
            var parts = ["Modify \(name)"]
            if let sets = newSets {
                parts.append("\(sets) sets")
            }
            if let reps = newReps {
                parts.append("\(reps) reps")
            }
            if let rir = newRir {
                parts.append("RIR \(rir)")
            }
            if let weight = newWeight {
                parts.append(weight)
            }
            if let note = note {
                parts.append("(\(note))")
            }
            return parts.joined(separator: " - ")
        case .replaceExercise(let oldName, let newName, let muscleGroup, let sets, _, _, _, let weight, _, _):
            var text = "Replace \(oldName) with \(newName) (\(muscleGroup)) - \(sets) sets"
            if let weight = weight { text += " @ \(weight)" }
            return text
        }
    }
}

/// Parses AI responses for structured workout modifications.
struct WorkoutModificationParser {

    /// Extracts modification commands from AI response text.
    /// Looks for special markers like [ADD], [REMOVE], [MODIFY], [REPLACE]
    func parse(_ text: String) -> [WorkoutModification] {
        var modifications: [WorkoutModification] = []
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // [ADD] Exercise Name | Muscle Group | Sets | Reps | RIR | Rest | Note
            if trimmed.hasPrefix("[ADD]") {
                if let mod = parseAdd(trimmed) {
                    modifications.append(mod)
                }
            }

            // [REMOVE] Exercise Name
            else if trimmed.hasPrefix("[REMOVE]") {
                if let mod = parseRemove(trimmed) {
                    modifications.append(mod)
                }
            }

            // [MODIFY] Exercise Name | Sets | Reps | RIR | Rest | Note
            else if trimmed.hasPrefix("[MODIFY]") {
                if let mod = parseModify(trimmed) {
                    modifications.append(mod)
                }
            }

            // [REPLACE] Old Name -> New Name | Muscle Group | Sets | Reps | RIR | Rest | Note
            else if trimmed.hasPrefix("[REPLACE]") {
                if let mod = parseReplace(trimmed) {
                    modifications.append(mod)
                }
            }
        }

        return modifications
    }

    private func parseAdd(_ line: String) -> WorkoutModification? {
        let content = line.replacingOccurrences(of: "[ADD]", with: "").trimmingCharacters(in: .whitespaces)
        let parts = content.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }

        guard parts.count >= 3 else { return nil }

        let name = parts[0]
        let muscleGroup = parts[1]
        let sets = Int(parts[2]) ?? 3
        let reps = parts.count > 3 ? parts[3] : nil
        let rir = parts.count > 4 ? parts[4] : nil
        let rest = parts.count > 5 ? Int(parts[5]) : nil
        let note = parts.count > 6 ? parts[6] : nil

        // The legacy pipe format has no weight column; only the JSON block carries one.
        return .addExercise(name: name, muscleGroup: muscleGroup, targetSets: sets, targetReps: reps, targetRir: rir, restSeconds: rest, targetWeight: nil, note: note)
    }

    private func parseRemove(_ line: String) -> WorkoutModification? {
        let name = line.replacingOccurrences(of: "[REMOVE]", with: "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return .removeExercise(name: name)
    }

    private func parseModify(_ line: String) -> WorkoutModification? {
        let content = line.replacingOccurrences(of: "[MODIFY]", with: "").trimmingCharacters(in: .whitespaces)
        let parts = content.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }

        guard parts.count >= 1 else { return nil }

        let name = parts[0]
        let sets = parts.count > 1 ? Int(parts[1]) : nil
        let reps = parts.count > 2 ? parts[2] : nil
        let rir = parts.count > 3 ? parts[3] : nil
        let rest = parts.count > 4 ? Int(parts[4]) : nil
        let note = parts.count > 5 ? parts[5] : nil

        return .modifyExercise(name: name, newTargetSets: sets, newTargetReps: reps, newTargetRir: rir, newRest: rest, newTargetWeight: nil, note: note)
    }

    private func parseReplace(_ line: String) -> WorkoutModification? {
        let content = line.replacingOccurrences(of: "[REPLACE]", with: "").trimmingCharacters(in: .whitespaces)
        let parts = content.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }

        guard parts.count >= 3 else { return nil }

        let normalized = parts[0].replacingOccurrences(of: "->", with: "→")
        let names = normalized.split(separator: "→").map { $0.trimmingCharacters(in: .whitespaces) }
        guard names.count == 2 else { return nil }

        let oldName = names[0]
        let newName = names[1]
        let muscleGroup = parts[1]
        let sets = Int(parts[2]) ?? 3
        let reps = parts.count > 3 ? parts[3] : nil
        let rir = parts.count > 4 ? parts[4] : nil
        let rest = parts.count > 5 ? Int(parts[5]) : nil
        let note = parts.count > 6 ? parts[6] : nil

        return .replaceExercise(oldName: oldName, newName: newName, muscleGroup: muscleGroup, targetSets: sets, targetReps: reps, targetRir: rir, restSeconds: rest, targetWeight: nil, note: note)
    }
}
