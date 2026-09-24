import Foundation
import os

/// Manages multiple AI providers and automatically rotates between them
/// when rate limits are hit. Prioritizes providers in order: Gemini → OpenAI → Claude.
final class AIServiceManager {

    private var providers: [AIProvider]
    private var currentProviderIndex: Int = 0
    private let logger = Logger(subsystem: "org.lightstack.app", category: "AIServiceManager")

    init(providers: [AIProvider]) {
        self.providers = providers
        logger.debug("Initialized with providers: \(providers.map { $0.name }.joined(separator: ", "))")
    }

    /// Generate chat completion using the first available provider.
    /// Automatically falls back to next provider if current one is rate limited.
    ///
    /// - Parameter expectsJSON: pass false for anything the user reads directly.
    ///   See `AIProvider.generateChat` — this is enforced by the API, not the prompt.
    func generateChat(
        systemPrompt: String,
        messages: [ChatMessage],
        expectsJSON: Bool = true,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        logger.debug("Starting chat generation with \(self.providers.count) providers available")
        tryNextProvider(
            systemPrompt: systemPrompt,
            messages: messages,
            expectsJSON: expectsJSON,
            attemptedProviders: [],
            completion: completion
        )
    }

    // MARK: - Private

    private func tryNextProvider(
        systemPrompt: String,
        messages: [ChatMessage],
        expectsJSON: Bool,
        attemptedProviders: [String],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        // Find next available provider
        guard let availableProvider = findNextAvailableProvider(excluding: attemptedProviders) else {
            logger.debug("All providers exhausted or rate limited")
            completion(.failure(AIProviderError.allProvidersUnavailable))
            return
        }

        logger.debug("Trying provider: \(availableProvider.name)")

        availableProvider.generateChat(
            systemPrompt: systemPrompt,
            messages: messages,
            expectsJSON: expectsJSON
        ) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let response):
                self.logger.debug("✅ Success with \(availableProvider.name)")
                completion(.success(response))

            case .failure(let error):
                self.logger.error("❌ Failed with \(availableProvider.name): \(error.localizedDescription)")

                // Check if this is a rate limit error
                if self.isRateLimitError(error) {
                    self.handleRateLimitError(error, provider: availableProvider)
                    // Try next provider
                    var attempted = attemptedProviders
                    attempted.append(availableProvider.name)
                    self.tryNextProvider(
                        systemPrompt: systemPrompt,
                        messages: messages,
                        expectsJSON: expectsJSON,
                        attemptedProviders: attempted,
                        completion: completion
                    )
                } else {
                    // Non-rate-limit error, fail immediately
                    completion(.failure(error))
                }
            }
        }
    }

    private func findNextAvailableProvider(excluding: [String]) -> AIProvider? {
        // Try to find an available provider we haven't tried yet
        for provider in providers where !excluding.contains(provider.name) {
            if provider.isAvailable {
                return provider
            } else if let nextAvailable = provider.nextAvailableTime {
                let timeRemaining = nextAvailable.timeIntervalSinceNow
                logger.debug("\(provider.name) rate limited, available in \(Int(timeRemaining))s")
            }
        }
        return nil
    }

    private func isRateLimitError(_ error: Error) -> Bool {
        let errorString = error.localizedDescription.lowercased()
        return errorString.contains("rate limit") ||
               errorString.contains("quota") ||
               errorString.contains("429") ||
               errorString.contains("resource_exhausted") ||
               errorString.contains("503") ||
               errorString.contains("unavailable") ||
               errorString.contains("high demand") ||
               errorString.contains("try again")
    }

    private func handleRateLimitError(_ error: Error, provider: AIProvider) {
        // Try to extract retry-after time from error
        let retryAfter = extractRetryAfter(from: error)
        let retryTime = Date().addingTimeInterval(retryAfter)
        provider.markRateLimited(until: retryTime)
        logger.debug("Marked \(provider.name) as rate limited until \(retryTime)")
    }

    private func extractRetryAfter(from error: Error) -> TimeInterval {
        // Try to parse "retry in X seconds" from error message
        let errorString = error.localizedDescription

        // Look for patterns like "retry in 56.5s" or "Please retry in 56.505034153s"
        let patterns = [
            "retry in ([0-9.]+)s",
            "retry in ([0-9.]+) seconds",
            "wait ([0-9.]+) seconds"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: errorString, range: NSRange(errorString.startIndex..., in: errorString)),
               let range = Range(match.range(at: 1), in: errorString),
               let seconds = Double(errorString[range]) {
                return seconds
            }
        }

        // Default to 60 seconds if we can't parse
        return 60
    }
}
