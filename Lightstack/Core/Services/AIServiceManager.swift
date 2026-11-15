import Foundation
import os

/// Manages multiple AI providers and automatically rotates between them
/// when rate limits are hit (Gemini models, all reached through the ai-proxy Edge Function).
final class AIServiceManager {

    private var providers: [AIProvider]
    private var currentProviderIndex: Int = 0
    private let logger = Logger(subsystem: "org.lightstack.app", category: "AIServiceManager")
    private let now: () -> Date

    /// `now` is injectable so tests can simulate slow attempts without waiting.
    init(providers: [AIProvider], now: @escaping () -> Date = Date.init) {
        self.providers = providers
        self.now = now
        logger.debug("Initialized with providers: \(providers.map { $0.name }.joined(separator: ", "))")
    }

    /// Name of the provider (model) the next request will try first.
    var activeProviderName: String {
        providers.first(where: { $0.isAvailable })?.name ?? providers.first?.name ?? "unknown"
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
        options: AIRequestOptions = .default,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        generateReply(systemPrompt: systemPrompt, messages: messages, expectsJSON: expectsJSON, options: options) {
            completion($0.map(\.text))
        }
    }

    /// Like `generateChat` but keeps the search-grounding sources. Same provider fallback, one call per provider tried.
    func generateReply(
        systemPrompt: String,
        messages: [ChatMessage],
        expectsJSON: Bool = true,
        options: AIRequestOptions = .default,
        completion: @escaping (Result<AIReply, Error>) -> Void
    ) {
        logger.debug("Starting chat generation with \(self.providers.count) providers available")
        let chain = providers.filter { $0.isAvailable }
        let state = RetryState(
            started: now(),
            // Immediate-failover tasks: original model, the next model, then the original once more.
            maxAttempts: options.retryPolicy.failoverImmediately ? (chain.count >= 2 ? 3 : 2) : .max)
        tryNextProvider(
            systemPrompt: systemPrompt,
            messages: messages,
            expectsJSON: expectsJSON,
            options: options,
            state: state,
            completion: completion
        )
    }

    // MARK: - Private

    private struct RetryState {
        let started: Date
        let maxAttempts: Int
        var attempts = 0
        var attempted: [String] = []
        /// Hops made because of a timeout, 504 or lost connection (standard policy allows one).
        var timeoutHops = 0
        var original: AIProvider?
        init(started: Date, maxAttempts: Int) {
            self.started = started
            self.maxAttempts = maxAttempts
        }
    }

    private func tryNextProvider(
        systemPrompt: String,
        messages: [ChatMessage],
        expectsJSON: Bool,
        options: AIRequestOptions,
        state: RetryState,
        forced: AIProvider? = nil,
        completion: @escaping (Result<AIReply, Error>) -> Void
    ) {
        // Find next available provider (or the one we were told to use, e.g. the original model again).
        guard let availableProvider = forced ?? findNextAvailableProvider(excluding: state.attempted) else {
            logger.debug("All providers exhausted or rate limited")
            completion(.failure(AIProviderError.allProvidersUnavailable))
            return
        }

        logger.debug("Trying provider: \(availableProvider.name)")
        var state = state
        state.attempts += 1
        if state.original == nil { state.original = availableProvider }
        if !state.attempted.contains(availableProvider.name) { state.attempted.append(availableProvider.name) }
        let attemptState = state

        availableProvider.generateReply(
            systemPrompt: systemPrompt,
            messages: messages,
            expectsJSON: expectsJSON,
            options: options
        ) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let response):
                self.logger.debug("✅ Success with \(availableProvider.name)")
                completion(.success(response))

            case .failure(let error):
                self.logger.error("❌ Failed with \(availableProvider.name): \(error.localizedDescription)")

                // ai-proxy refusals (per-user rate limit, signed out) apply to every
                // model, so show them as-is instead of trying the next provider.
                if (error as NSError).domain == GeminiService.proxyErrorDomain {
                    completion(.failure(error))
                    return
                }

                let next: (provider: AIProvider?, state: RetryState)? = self.nextAttempt(
                    after: error, from: availableProvider, state: attemptState, policy: options.retryPolicy)
                guard let next else {
                    // Not worth another attempt: report what happened.
                    completion(.failure(error))
                    return
                }
                self.tryNextProvider(
                    systemPrompt: systemPrompt,
                    messages: messages,
                    expectsJSON: expectsJSON,
                    options: options,
                    state: next.state,
                    forced: next.provider,
                    completion: completion
                )
            }
        }
    }

    /// Decides what follows a failed attempt: nil = give up with this error, else the next attempt
    /// (`provider` nil = let the manager pick the next available model).
    private func nextAttempt(after error: Error, from provider: AIProvider, state: RetryState,
                             policy: AIRetryPolicy) -> (provider: AIProvider?, state: RetryState)? {
        var state = state

        if let transient = AITransientError.from(error) {
            if policy.failoverImmediately {
                // No backoff on an overloaded model: straight to the next one, then the original once more.
                guard state.attempts < state.maxAttempts,
                      now().timeIntervalSince(state.started) <= policy.totalBudget - policy.attemptTimeout else { return nil }
                if let other = findNextAvailableProvider(excluding: state.attempted) {
                    return (other, state)
                }
                // Nothing else to hop to: the original model again.
                return (state.original ?? provider, state)
            }
            // Standard: a 503 marks the model busy and moves on, as before. A 504, timeout or lost connection
            // makes one hop to the next model (which gets its own full timeout) and no more.
            if transient.isOverload503 {
                handleRateLimitError(error, provider: provider)
                return (nil, state)
            }
            guard state.timeoutHops < 1, findNextAvailableProvider(excluding: state.attempted) != nil else { return nil }
            state.timeoutHops += 1
            return (nil, state)
        }

        if isRateLimitError(error) {
            handleRateLimitError(error, provider: provider)
            return (nil, state)
        }
        // Anything else is not a reason to try another model.
        return nil
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
