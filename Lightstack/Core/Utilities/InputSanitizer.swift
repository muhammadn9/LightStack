import Foundation

/// Prompt injection defense layer.
/// Provides static methods to strip dangerous patterns from user input
/// before it reaches any AI prompt.
struct InputSanitizer {

    private static let blockedPatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: "ignore (previous|all) instructions", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "you are now", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "system prompt", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "\\[INST\\]", options: []),
        try! NSRegularExpression(pattern: "<\\|system\\|>", options: []),
        try! NSRegularExpression(pattern: "jailbreak", options: .caseInsensitive),
    ]

    private static let maxLength = 500

    /// Trim whitespace, strip blocked regex patterns, truncate to 500 chars.
    static func sanitize(_ input: String) -> String {
        var result = input.trimmingCharacters(in: .whitespacesAndNewlines)

        let range = NSRange(result.startIndex..., in: result)
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

    /// Sanitize and clamp a numeric Double to a given range.
    static func sanitizeNumeric(_ value: Double, min: Double, max: Double) -> Double {
        return Swift.min(Swift.max(value, min), max)
    }

    /// Sanitize and clamp an integer to a given range.
    static func sanitizeInteger(_ value: Int, min: Int, max: Int) -> Int {
        return Swift.min(Swift.max(value, min), max)
    }
}
