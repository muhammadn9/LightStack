import Foundation
import os

/// Protocol for AI service providers (Gemini, OpenAI, Claude).
/// Allows rotation between providers when rate limits are hit.
protocol AIProvider {
    /// Provider name for logging and identification
    var name: String { get }

    /// UserDefaults key used to persist the rate-limit date.
    /// Each provider MUST supply a distinct key so stored state is never cross-contaminated.
    var rateLimitKey: String { get }

    /// Whether provider is currently available (not rate limited)
    var isAvailable: Bool { get }

    /// When the provider will be available again (after rate limit)
    var nextAvailableTime: Date? { get }

    /// Generate chat completion with system prompt and messages.
    ///
    /// - Parameter expectsJSON: when true the provider constrains the response
    ///   to a JSON object. Prose callers MUST pass false — Gemini and OpenAI
    ///   enforce this at the API level, so a prompt asking for plain text is
    ///   ignored and the caller gets raw JSON back.
    func generateChat(
        systemPrompt: String,
        messages: [ChatMessage],
        expectsJSON: Bool,
        completion: @escaping (Result<String, Error>) -> Void
    )

    /// Mark provider as rate limited until specified time
    func markRateLimited(until: Date)

    /// Clear rate limit status
    func clearRateLimit()
}

// MARK: - Default implementations

extension AIProvider {
    /// Default: available when the API key is non-empty and the rate-limit window has passed.
    /// Providers that embed apiKey as a stored property satisfy this automatically.
    var isAvailable: Bool {
        if let rateLimitUntil = UserDefaults.standard.object(forKey: rateLimitKey) as? Date {
            return Date() >= rateLimitUntil
        }
        return true
    }

    var nextAvailableTime: Date? {
        UserDefaults.standard.object(forKey: rateLimitKey) as? Date
    }

    func markRateLimited(until: Date) {
        UserDefaults.standard.set(until, forKey: rateLimitKey)
        let logger = Logger(subsystem: "org.lightstack.app", category: name)
        logger.debug("Rate limited until \(until)")
    }

    func clearRateLimit() {
        UserDefaults.standard.removeObject(forKey: rateLimitKey)
        let logger = Logger(subsystem: "org.lightstack.app", category: name)
        logger.debug("Rate limit cleared")
    }
}

// MARK: - Shared error helpers

extension AIProvider {
    func missingAPIKeyError() -> NSError {
        NSError(
            domain: "\(name)Service",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Missing \(name.uppercased())_API_KEY"]
        )
    }

    func invalidURLError() -> NSError {
        NSError(
            domain: "\(name)Service",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"]
        )
    }

    func noDataError() -> NSError {
        NSError(
            domain: "\(name)Service",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: "No data received"]
        )
    }

    func parseError(_ detail: String) -> NSError {
        NSError(
            domain: "\(name)Service",
            code: -4,
            userInfo: [NSLocalizedDescriptionKey: "Failed to parse \(name) response - \(detail)"]
        )
    }

    func apiResponseError(_ message: String) -> NSError {
        NSError(
            domain: "\(name)Service",
            code: -4,
            userInfo: [NSLocalizedDescriptionKey: "\(name) API error: \(message)"]
        )
    }
}

/// Error type for AI provider failures
enum AIProviderError: Error, LocalizedError {
    case allProvidersUnavailable
    case rateLimitExceeded(retryAfter: TimeInterval)
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .allProvidersUnavailable:
            return "All AI providers are currently unavailable. Please try again later."
        case .rateLimitExceeded(let retryAfter):
            return "Rate limit exceeded. Please try again in \(Int(retryAfter)) seconds."
        case .invalidResponse:
            return "Invalid response from AI provider."
        case .apiError(let message):
            return "API error: \(message)"
        }
    }
}
