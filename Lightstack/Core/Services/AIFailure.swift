import Foundation

/// How a request is retried. Per task, set on `AIRequestOptions.retryPolicy`.
struct AIRetryPolicy: Equatable {
    /// Client timeout for one attempt.
    var attemptTimeout: TimeInterval
    /// Backoff retries (1 s, 2 s, 4 s) on the same model after HTTP 503, before the manager falls back.
    var sameModel503Retries: Int
    /// On 503, 504, a timeout or a lost connection, go straight to the next model in the chain, then make one
    /// more attempt on the original model. Gives up after `totalBudget`.
    var failoverImmediately: Bool
    var totalBudget: TimeInterval

    /// What every task used before: 58 s attempts, 503 backoff on the same model, one hop after a timeout.
    static let standard = AIRetryPolicy(attemptTimeout: 58, sameModel503Retries: 3, failoverImmediately: false, totalBudget: 120)
    /// Interactive results that must not make the user wait: 25 s attempts, immediate model hop, ~60 s total.
    static let fastFailover = AIRetryPolicy(attemptTimeout: 25, sameModel503Retries: 0, failoverImmediately: true, totalBudget: 60)
}

/// A failure that says "this model is overloaded or too slow", not "your request is wrong".
/// Another model, or another try, may well succeed.
struct AITransientError: LocalizedError, Equatable {
    enum Cause: Equatable {
        /// HTTP 502, 503 or 504 (Gemini overloaded, or the proxy's own upstream timeout).
        case busy(Int)
        case timedOut
        case connectionLost
    }
    let cause: Cause

    var errorDescription: String? {
        switch cause {
        case .busy(let status): return "The AI service is busy (HTTP \(status)). Please try again."
        case .timedOut: return "The AI service took too long to respond. Please try again."
        case .connectionLost: return "The connection was lost. Please try again."
        }
    }

    /// The typed error itself, or a transient URLError (timeout, lost connection) wrapped as one.
    static func from(_ error: Error) -> AITransientError? {
        if let typed = error as? AITransientError { return typed }
        guard let url = error as? URLError else { return nil }
        switch url.code {
        case .timedOut: return AITransientError(cause: .timedOut)
        case .networkConnectionLost: return AITransientError(cause: .connectionLost)
        default: return nil
        }
    }

    /// True for the 503 flavour that the existing code treats as "rate limited": mark the model, try the next.
    var isOverload503: Bool {
        if case .busy(let status) = cause { return status == 503 }
        return false
    }
}

/// Why an AI request failed, in the words the app shows.
enum AIFailureReason: Equatable {
    case busy, offline, limit, signedOut, other

    var message: String {
        switch self {
        case .busy: return "The AI service is busy right now."
        case .offline: return "No connection."
        case .limit: return "You've hit today's AI limit."
        case .signedOut: return "Sign in to use the coach."
        case .other: return "Coach feedback is unavailable right now."
        }
    }

    /// Worth trying again automatically a little later.
    var isTemporary: Bool { self == .busy }

    static func classify(_ error: Error) -> AIFailureReason {
        let ns = error as NSError
        if ns.domain == GeminiService.proxyErrorDomain {
            switch ns.code {
            case 429: return .limit
            case 401, 403: return .signedOut
            default: return .other
            }
        }
        if AITransientError.from(error) != nil { return .busy }
        if let provider = error as? AIProviderError {
            switch provider {
            case .allProvidersUnavailable, .rateLimitExceeded: return .busy
            default: return .other
            }
        }
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed:
                return .offline
            default: break
            }
        }
        let text = error.localizedDescription.lowercased()
        if text.contains("503") || text.contains("unavailable") || text.contains("high demand") { return .busy }
        if text.contains("quota") || text.contains("rate limit") || text.contains("429") { return .limit }
        return .other
    }
}
