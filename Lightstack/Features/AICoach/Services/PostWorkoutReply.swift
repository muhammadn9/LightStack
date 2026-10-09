import Foundation

/// The single post-workout AI reply: `{"note": "...", "summary": "..."}`.
struct PostWorkoutReply: Equatable {
    /// Shown on the post-workout screen. Empty means "no note".
    let note: String
    /// Rolling context summary to store; nil when the reply had none.
    let summary: String?

    /// Never throws. If the reply isn't the expected JSON, prose is treated as the note
    /// (no summary) and anything JSON-looking that can't be read yields an empty note.
    static func parse(_ text: String) -> PostWorkoutReply {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return PostWorkoutReply(note: "", summary: nil) }

        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            trimmed = lines.dropFirst().filter { !$0.hasPrefix("```") }.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let note = (object["note"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let summary = (object["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return PostWorkoutReply(note: note, summary: (summary?.isEmpty ?? true) ? nil : summary)
        }

        // Looks like JSON but unreadable (e.g. cut off): show nothing rather than raw JSON.
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return PostWorkoutReply(note: "", summary: nil)
        }
        return PostWorkoutReply(note: trimmed, summary: nil)
    }
}
