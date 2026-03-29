import Foundation

/// Prompt injection defense layer.
/// Provides static methods to strip dangerous patterns from user input
/// before it reaches any AI prompt.
struct InputSanitizer {

    private static let blockedPatterns: [NSRegularExpression] = [
        // Classic instruction override attempts
        try! NSRegularExpression(pattern: "ignore (previous|all|your) instructions", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "disregard (previous|all|your) instructions", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "forget (previous|all|your) instructions", options: .caseInsensitive),
        // Role/identity hijacking
        try! NSRegularExpression(pattern: "you are now", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "act as (a |an )?", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "pretend (you are|to be)", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "roleplay as", options: .caseInsensitive),
        // Prompt structure leakage
        try! NSRegularExpression(pattern: "system prompt", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "your instructions", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "your (system |original )?prompt", options: .caseInsensitive),
        // Model-specific injection tokens
        try! NSRegularExpression(pattern: "\\[INST\\]", options: []),
        try! NSRegularExpression(pattern: "\\[/INST\\]", options: []),
        try! NSRegularExpression(pattern: "<\\|system\\|>", options: []),
        try! NSRegularExpression(pattern: "<\\|user\\|>", options: []),
        try! NSRegularExpression(pattern: "<\\|assistant\\|>", options: []),
        // General jailbreak terms
        try! NSRegularExpression(pattern: "jailbreak", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "DAN mode", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "developer mode", options: .caseInsensitive),
    ]

    private static let maxLength = 500

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

    /// Sanitize a short label (split day name, workout type).
    /// Applies the same pattern stripping but caps at 50 chars.
    static func sanitizeLabel(_ input: String) -> String {
        var result = sanitize(input)
        if result.count > 50 {
            result = String(result.prefix(50))
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
