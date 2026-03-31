import Foundation

/// Protocol for AI service providers (Gemini, OpenAI, Claude).
/// Allows rotation between providers when rate limits are hit.
protocol AIProvider {
    /// Provider name for logging and identification
    var name: String { get }

    /// Whether provider is currently available (not rate limited)
    var isAvailable: Bool { get }

    /// When the provider will be available again (after rate limit)
    var nextAvailableTime: Date? { get }

    /// Generate chat completion with system prompt and messages
    func generateChat(
        systemPrompt: String,
        messages: [ChatMessage],
        completion: @escaping (Result<String, Error>) -> Void
    )

    /// Mark provider as rate limited until specified time
    func markRateLimited(until: Date)

    /// Clear rate limit status
    func clearRateLimit()
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
