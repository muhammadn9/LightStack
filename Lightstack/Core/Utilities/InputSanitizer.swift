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

    /// Sanitize and clamp a numeric Double to a given range.
    static func sanitizeNumeric(_ value: Double, min: Double, max: Double) -> Double {
        return Swift.min(Swift.max(value, min), max)
    }

    /// Sanitize and clamp an integer to a given range.
    static func sanitizeInteger(_ value: Int, min: Int, max: Int) -> Int {
        return Swift.min(Swift.max(value, min), max)
    }
}
