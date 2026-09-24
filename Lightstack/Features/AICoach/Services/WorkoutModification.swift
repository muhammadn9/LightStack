import Foundation

/// Represents a modification the AI suggests to the current workout.
/// `targetWeight` is a free-form string ("130 lbs") to match how workout
/// generation already records it — there is no numeric weight column on
/// `Exercise`; it is carried in `coachNote` as a "Target: …" segment.
enum WorkoutModification {
    case addExercise(name: String, muscleGroup: String, targetSets: Int, targetReps: String?, targetRir: String?, restSeconds: Int?, targetWeight: String?, note: String?)
    case removeExercise(name: String)
    case modifyExercise(name: String, newTargetSets: Int?, newTargetReps: String?, newTargetRir: String?, newRest: Int?, newTargetWeight: String?, note: String?)
    case replaceExercise(oldName: String, newName: String, muscleGroup: String, targetSets: Int, targetReps: String?, targetRir: String?, restSeconds: Int?, targetWeight: String?, note: String?)

    var description: String {
        switch self {
        case .addExercise(let name, let muscleGroup, let sets, _, _, _, let weight, _):
            var text = "Add \(name) (\(muscleGroup)) - \(sets) sets"
            if let weight = weight { text += " @ \(weight)" }
            return text
        case .removeExercise(let name):
            return "Remove \(name)"
        case .modifyExercise(let name, let newSets, let newReps, let newRir, _, let newWeight, let note):
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
        case .replaceExercise(let oldName, let newName, let muscleGroup, let sets, _, _, _, let weight, _):
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
