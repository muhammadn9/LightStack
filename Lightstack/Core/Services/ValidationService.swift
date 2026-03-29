import Foundation

/// Input sanitization and validation.
/// Called on every user-provided string before it touches any AI prompt.
/// Thin wrapper over InputSanitizer for dependency injection.
final class ValidationService {

    func sanitize(_ input: String) -> String {
        InputSanitizer.sanitize(input)
    }

    func sanitizeNumeric(_ value: Double, min: Double, max: Double) -> Double {
        InputSanitizer.sanitizeNumeric(value, min: min, max: max)
    }

    func sanitizeInteger(_ value: Int, min: Int, max: Int) -> Int {
        InputSanitizer.sanitizeInteger(value, min: min, max: max)
    }

    /// Returns true if the sanitized string is non-empty.
    func isValid(_ input: String) -> Bool {
        !sanitize(input).isEmpty
    }
}
