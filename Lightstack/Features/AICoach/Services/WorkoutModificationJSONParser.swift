import Foundation

// MARK: - Errors

enum WorkoutModificationJSONParserError: Error, LocalizedError {
    case malformedJSON(underlying: Error)
    case invalidSchema(reason: String)

    var errorDescription: String? {
        switch self {
        case .malformedJSON(let underlying):
            return "Malformed JSON in modification block: \(underlying.localizedDescription)"
        case .invalidSchema(let reason):
            return "Invalid modification schema: \(reason)"
        }
    }
}

// MARK: - DTOs

/// Top-level wrapper for the JSON block emitted by the AI coach.
private struct WorkoutModificationPayload: Decodable {
    let modifications: [WorkoutModificationDTO]
}

/// Discriminated union — the `action` field drives which fields are required.
private struct WorkoutModificationDTO: Decodable {
    let action: String

    // addExercise / replaceExercise fields
    let name: String?
    let muscleGroup: String?
    let targetSets: Int?
    let targetReps: String?
    let targetRir: String?
    let restSeconds: Int?
    /// Free-form, e.g. "135 lbs" — matches how generation records weight.
    let targetWeight: String?
    let note: String?

    // removeExercise field
    // uses `name` for the exercise name

    // modifyExercise fields (all optional overrides)
    let newTargetSets: Int?
    let newTargetReps: String?
    let newTargetRir: String?
    let newRest: Int?
    let newTargetWeight: String?

    // replaceExercise extra fields
    let oldName: String?
    let newName: String?

    enum CodingKeys: String, CodingKey {
        case action
        case name
        case muscleGroup       = "muscle_group"
        case targetSets        = "target_sets"
        case targetReps        = "target_reps"
        case targetRir         = "target_rir"
        case restSeconds       = "rest_seconds"
        case targetWeight      = "target_weight"
        case note
        case newTargetSets     = "new_target_sets"
        case newTargetReps     = "new_target_reps"
        case newTargetRir      = "new_target_rir"
        case newRest           = "new_rest"
        case newTargetWeight   = "new_target_weight"
        case oldName           = "old_name"
        case newName           = "new_name"
    }
}

// MARK: - Parser

/// Extracts a fenced ```json … ``` block from AI response text and decodes it
/// into an array of `WorkoutModification` values.
///
/// - Absence of a fenced block → returns empty array (normal, no error).
/// - Presence of a malformed / non-decodable block → throws `WorkoutModificationJSONParserError`.
struct WorkoutModificationJSONParser {

    // MARK: Public interface

    /// Parse AI response text, extracting any fenced JSON block.
    func parse(_ text: String) throws -> [WorkoutModification] {
        guard let jsonString = extractJSONBlock(from: text) else {
            return []  // No block present — normal case.
        }
        return try decode(jsonString)
    }

    /// Returns the response text with any JSON removed, for clean display.
    ///
    /// Strips the fenced block first, then any bare unfenced JSON object. The
    /// second pass matters: the model is capable of emitting an unfenced workout
    /// plan object, and without this it lands verbatim in a chat bubble.
    func strippingJSONBlock(from text: String) -> String {
        removeBareJSONObjects(from: removeJSONBlock(from: text))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Block extraction

    /// Extracts the content inside the first fenced code block.
    /// Accepts ``` json (with space), ```json, or plain ``` fences.
    private func extractJSONBlock(from text: String) -> String? {
        // Regex-free approach: scan for the opening fence.
        let lines = text.components(separatedBy: "\n")
        var insideBlock = false
        var blockLines: [String] = []

        for line in lines {
            // Must trim newlines too: on \r\n responses the trailing \r would
            // otherwise stop the fence from ever matching (see issue #13).
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !insideBlock {
                // Accept ```json, ``` json, or just ``` as an opening fence
                if trimmed == "```" || trimmed.lowercased() == "```json" || trimmed.lowercased() == "``` json" {
                    insideBlock = true
                    blockLines = []
                }
            } else {
                if trimmed == "```" {
                    // End of block
                    let content = blockLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !content.isEmpty { return content }
                    // Empty block — keep scanning for another one
                    insideBlock = false
                    blockLines = []
                } else {
                    blockLines.append(line)
                }
            }
        }

        // If we hit end-of-text still inside a block, accept it (model omitted closing fence)
        if insideBlock && !blockLines.isEmpty {
            let content = blockLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty { return content }
        }

        return nil
    }

    /// Returns the text with the first fenced block (and its fences) removed.
    private func removeJSONBlock(from text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        var openIndex: Int?

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if openIndex == nil {
                if trimmed == "```" || trimmed.lowercased() == "```json" || trimmed.lowercased() == "``` json" {
                    openIndex = i
                }
            } else {
                if trimmed == "```" {
                    // Remove from openIndex through i inclusive
                    if let start = openIndex {
                        let count = i - start + 1
                        lines.removeSubrange(start...(start + count - 1))
                    }
                    return lines.joined(separator: "\n")
                }
            }
        }

        // If block had no closing fence, remove from openIndex to end
        if let start = openIndex {
            lines.removeSubrange(start...)
            return lines.joined(separator: "\n")
        }

        return text
    }

    /// Removes every bare `{ … }` run that actually parses as JSON, leaving
    /// surrounding prose intact. A `{` that doesn't open valid JSON is left
    /// alone — the coach is allowed to write braces in a sentence.
    private func removeBareJSONObjects(from text: String) -> String {
        var result = ""
        var remainder = Substring(text)

        while let start = remainder.firstIndex(of: "{") {
            guard let end = matchingBrace(in: remainder, from: start) else {
                // Unbalanced. If the tail still looks like JSON the model was
                // cut off mid-object; drop it rather than show the fragment.
                if remainder[start...].contains("\":") {
                    result += remainder[remainder.startIndex..<start]
                    return result
                }
                break
            }

            let candidate = remainder[start...end]
            if (try? JSONSerialization.jsonObject(with: Data(candidate.utf8))) != nil {
                result += remainder[remainder.startIndex..<start]
                remainder = remainder[remainder.index(after: end)...]
            } else {
                // Keep this brace and resume scanning after it.
                result += remainder[remainder.startIndex...start]
                remainder = remainder[remainder.index(after: start)...]
            }
        }

        result += remainder
        return result
    }

    /// Index of the `}` that closes the `{` at `start`, or nil if unbalanced.
    /// Braces inside string literals are ignored.
    private func matchingBrace(in text: Substring, from start: Substring.Index) -> Substring.Index? {
        var depth = 0
        var inString = false
        var escaped = false
        var index = start

        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if inString && character == "\\" {
                escaped = true
            } else if character == "\"" {
                inString.toggle()
            } else if !inString {
                if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 { return index }
                }
            }
            index = text.index(after: index)
        }

        return nil
    }

    // MARK: - Decoding

    private func decode(_ jsonString: String) throws -> [WorkoutModification] {
        guard let data = jsonString.data(using: .utf8) else {
            throw WorkoutModificationJSONParserError.malformedJSON(
                underlying: NSError(domain: "WorkoutModificationJSONParser", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Could not encode string to UTF-8 data"])
            )
        }

        let payload: WorkoutModificationPayload
        do {
            payload = try JSONDecoder().decode(WorkoutModificationPayload.self, from: data)
        } catch {
            throw WorkoutModificationJSONParserError.malformedJSON(underlying: error)
        }

        return try payload.modifications.map { try convert($0) }
    }

    private func convert(_ dto: WorkoutModificationDTO) throws -> WorkoutModification {
        switch dto.action.lowercased() {

        case "add":
            guard let name = dto.name, !name.isEmpty else {
                throw WorkoutModificationJSONParserError.invalidSchema(reason: "add action missing `name`")
            }
            guard let muscleGroup = dto.muscleGroup, !muscleGroup.isEmpty else {
                throw WorkoutModificationJSONParserError.invalidSchema(reason: "add action missing `muscle_group`")
            }
            guard let sets = dto.targetSets else {
                throw WorkoutModificationJSONParserError.invalidSchema(reason: "add action missing `target_sets`")
            }
            return .addExercise(
                name: name,
                muscleGroup: muscleGroup,
                targetSets: sets,
                targetReps: dto.targetReps,
                targetRir: dto.targetRir,
                restSeconds: dto.restSeconds,
                targetWeight: dto.targetWeight,
                note: dto.note
            )

        case "remove":
            guard let name = dto.name, !name.isEmpty else {
                throw WorkoutModificationJSONParserError.invalidSchema(reason: "remove action missing `name`")
            }
            return .removeExercise(name: name)

        case "modify":
            guard let name = dto.name, !name.isEmpty else {
                throw WorkoutModificationJSONParserError.invalidSchema(reason: "modify action missing `name`")
            }
            return .modifyExercise(
                name: name,
                newTargetSets: dto.newTargetSets,
                newTargetReps: dto.newTargetReps,
                newTargetRir: dto.newTargetRir,
                newRest: dto.newRest,
                newTargetWeight: dto.newTargetWeight,
                note: dto.note
            )

        case "replace":
            guard let oldName = dto.oldName, !oldName.isEmpty else {
                throw WorkoutModificationJSONParserError.invalidSchema(reason: "replace action missing `old_name`")
            }
            guard let newName = dto.newName, !newName.isEmpty else {
                throw WorkoutModificationJSONParserError.invalidSchema(reason: "replace action missing `new_name`")
            }
            guard let muscleGroup = dto.muscleGroup, !muscleGroup.isEmpty else {
                throw WorkoutModificationJSONParserError.invalidSchema(reason: "replace action missing `muscle_group`")
            }
            guard let sets = dto.targetSets else {
                throw WorkoutModificationJSONParserError.invalidSchema(reason: "replace action missing `target_sets`")
            }
            return .replaceExercise(
                oldName: oldName,
                newName: newName,
                muscleGroup: muscleGroup,
                targetSets: sets,
                targetReps: dto.targetReps,
                targetRir: dto.targetRir,
                restSeconds: dto.restSeconds,
                targetWeight: dto.targetWeight,
                note: dto.note
            )

        default:
            throw WorkoutModificationJSONParserError.invalidSchema(reason: "Unknown action: \(dto.action)")
        }
    }
}
