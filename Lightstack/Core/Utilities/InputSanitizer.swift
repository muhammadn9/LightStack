import Foundation

/// Prompt injection defense layer.
/// Provides static methods to strip dangerous patterns from user input
/// before it reaches any AI prompt.
struct InputSanitizer {

    /// Patterns are compiled once at startup via a validated factory.
    /// `try!` is intentionally avoided: a regex syntax error would crash the
    /// app on launch with no recovery path. Instead, bad patterns are caught
    /// by `assertionFailure` during development and silently skipped in release.
    private static let blockedPatterns: [NSRegularExpression] = {
        let rawPatterns: [(String, NSRegularExpression.Options)] = [
            // Classic instruction override attempts
            ("ignore (previous|all|your) instructions",        .caseInsensitive),
            ("disregard (previous|all|your) instructions",     .caseInsensitive),
            ("forget (previous|all|your) instructions",        .caseInsensitive),
            // Role / identity hijacking
            ("you are now",                                     .caseInsensitive),
            ("act as (a |an )?",                               .caseInsensitive),
            ("pretend (you are|to be)",                        .caseInsensitive),
            ("roleplay as",                                     .caseInsensitive),
            // Prompt structure leakage
            ("system prompt",                                   .caseInsensitive),
            ("your instructions",                               .caseInsensitive),
            ("your (system |original )?prompt",                .caseInsensitive),
            // Model-specific injection tokens
            ("\\[INST\\]",                                      []),
            ("\\[/INST\\]",                                     []),
            ("<\\|system\\|>",                                  []),
            ("<\\|user\\|>",                                    []),
            ("<\\|assistant\\|>",                               []),
            // General jailbreak terms
            ("jailbreak",                                       .caseInsensitive),
            ("DAN mode",                                        .caseInsensitive),
            ("developer mode",                                  .caseInsensitive),
        ]

        return rawPatterns.compactMap { pattern, options in
            do {
                return try NSRegularExpression(pattern: pattern, options: options)
            } catch {
                assertionFailure("InputSanitizer: invalid regex pattern '\(pattern)': \(error)")
                return nil
            }
        }
    }()

    private static let maxLength = 500
    private static let maxLabelLength = 50

    /// Trim whitespace, strip blocked regex patterns, truncate to 500 chars.
    static func sanitize(_ input: String) -> String {
        var result = input.trimmingCharacters(in: .whitespacesAndNewlines)

        for pattern in blockedPatterns {
            result = pattern.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }

        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        if result.count > maxLength {
            result = String(result.prefix(maxLength))
        }

        return result
    }

    /// Sanitize a short label (split day name, workout type, exercise name).
    /// Strips markdown bold/italic markers first, then applies the same pattern
    /// stripping and caps at 50 chars.
    static func sanitizeLabel(_ input: String) -> String {
        // Strip markdown bold/italic markers first
        var cleaned = input
        // Remove **text** and *text* → text
        cleaned = cleaned.replacingOccurrences(of: #"\*{1,2}([^*\n]+)\*{1,2}"#, with: "$1", options: .regularExpression)
        // Remove leading heading markers: ### text → text
        cleaned = cleaned.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: [.regularExpression, .anchored])

        var result = sanitize(cleaned)
        if result.count > maxLabelLength {
            result = String(result.prefix(maxLabelLength))
        }
        return result
    }

    /// A sentence or two of free text (a coach's reason or cue): the same cleaning as a label (markdown markers,
    /// blocked patterns) but kept whole up to `limit` characters, cut at a word boundary with "…".
    static func sanitizeSentence(_ input: String, limit: Int = 200) -> String {
        var cleaned = input.replacingOccurrences(of: #"\*{1,2}([^*\n]+)\*{1,2}"#, with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: [.regularExpression, .anchored])
        let flat = sanitize(cleaned).split(whereSeparator: { $0.isNewline || $0 == "\t" || $0 == " " }).joined(separator: " ")
        return clipAtWord(flat, limit: limit)
    }

    /// `text` unchanged when it fits in `limit` characters; otherwise cut at the last word boundary that leaves
    /// `limit` characters or fewer including a trailing "…". Never cuts mid-word (a single word longer than the
    /// limit is the only exception).
    static func clipAtWord(_ text: String, limit: Int) -> String {
        guard limit > 1, text.count > limit else { return text }
        let room = String(text.prefix(limit - 1))
        var cut = room
        // Only back up to a space when the character right after the cut is not itself a space (we are mid-word).
        let nextIndex = text.index(text.startIndex, offsetBy: limit - 1)
        if text[nextIndex] != " ", let space = room.lastIndex(of: " ") {
            cut = String(room[..<space])
        }
        let trimmed = cut.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—.").union(.whitespaces))
        return (trimmed.isEmpty ? room : trimmed) + "…"
    }

    /// Sanitize and clamp a numeric Double to a given range.
    static func sanitizeNumeric(_ value: Double, min: Double, max: Double) -> Double {
        return Swift.min(Swift.max(value, min), max)
    }

    /// Sanitize and clamp an integer to a given range.
    static func sanitizeInteger(_ value: Int, min: Int, max: Int) -> Int {
        return Swift.min(Swift.max(value, min), max)
    }
}
