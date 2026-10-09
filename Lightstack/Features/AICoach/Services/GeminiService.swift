import Foundation
import os

// MARK: - GeminiService

/// Handles all Gemini calls.
/// Single responsibility: send prompt, receive response.
/// No context building — that's CoachContextBuilder's job.
///
/// The app never holds a Gemini key. Requests go to the `ai-proxy` Supabase Edge
/// Function, signed with the user's session token; the function checks the user's
/// rate limit and calls Gemini with a server-side key.
final class GeminiService {

    private let logger = Logger(subsystem: "org.lightstack.app", category: "GeminiService")

    private let session: URLSession
    /// Gemini model id, e.g. "gemini-3.5-flash". Each model gets its own
    /// provider instance so a busy model can fall back to another.
    let model: String
    /// `<SUPABASE_URL>/functions/v1/ai-proxy`; nil when Supabase isn't configured.
    private let proxyURL: URL?
    private let anonKey: String
    /// The signed-in user's access token, or nil when signed out.
    private let accessToken: () async -> String?

    /// Error domain for refusals from ai-proxy itself (rate limit, not signed in).
    static let proxyErrorDomain = "AIProxy"

    init(
        model: String = "gemini-3.5-flash",
        proxyURL: URL? = nil,
        anonKey: String = "",
        accessToken: @escaping () async -> String? = { nil }
    ) {
        self.model = model
        self.proxyURL = proxyURL
        self.anonKey = anonKey
        self.accessToken = accessToken
        self.session = URLSession.shared
    }

    // MARK: - Multi-Turn Chat (Callback-based)

    /// Sends a multi-turn conversation to Gemini with alternating user/model roles.
    /// Retries on HTTP 503 with exponential backoff (1s → 2s → 4s) per Google's recommendation.
    func generateChatAsync(
        systemPrompt: String,
        messages: [ChatMessage],
        expectsJSON: Bool = true,
        options: AIRequestOptions = .default,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        logger.debug("🔵 API CALL INITIATED - This counts against quota!")
        logger.debug("System prompt: \(systemPrompt.count) chars")
        logger.debug("Messages: \(messages.count) messages, \(messages.reduce(0) { $0 + $1.content.count }) total chars")

        guard let url = proxyURL else {
            DispatchQueue.main.async { completion(.failure(self.invalidURLError())) }
            return
        }

        var body = buildChatRequestBody(
            systemPrompt: systemPrompt,
            messages: messages,
            expectsJSON: expectsJSON,
            options: options
        )
        body["model"] = model

        // If Gemini rejects the thinking field for this model, the same request is
        // retried once without it (see `performWithRetry`).
        var plainBody: Data?
        if options.minimalThinking {
            var plain = buildChatRequestBody(
                systemPrompt: systemPrompt,
                messages: messages,
                expectsJSON: expectsJSON,
                options: options,
                includeThinking: false
            )
            plain["model"] = model
            plainBody = try? JSONSerialization.data(withJSONObject: plain)
        }

        let httpBody: Data
        do {
            httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        Task {
            guard let token = await accessToken() else {
                DispatchQueue.main.async { completion(.failure(Self.proxyError(401, "Please sign in to use the AI coach."))) }
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.httpBody = httpBody
            #if DEBUG
            AIUsageTracker.shared.recordCall(task: options.task)
            #endif
            performWithRetry(request: request, attempt: 0, task: options.task,
                             thinkingFallbackBody: plainBody, expectsJSON: expectsJSON, completion: completion)
        }
    }

    /// A refusal from ai-proxy itself. The manager shows these as-is instead of
    /// falling back to another model, which would be refused the same way.
    static func proxyError(_ status: Int, _ message: String) -> NSError {
        NSError(domain: proxyErrorDomain, code: status, userInfo: [NSLocalizedDescriptionKey: message])
    }

    /// Executes the request, retrying on 503 with exponential backoff: 1s, 2s, 4s.
    private func performWithRetry(
        request: URLRequest,
        attempt: Int,
        task: AITask,
        thinkingFallbackBody: Data?,
        expectsJSON: Bool,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            let http = response as? HTTPURLResponse
            let httpStatus = http?.statusCode ?? 200

            // ai-proxy's own refusals (rate limit, signed out, …): surface the message.
            if http?.value(forHTTPHeaderField: "x-ai-proxy-error") != nil {
                let message = data.flatMap(Self.proxyMessage(from:)) ?? "The AI coach is unavailable right now."
                DispatchQueue.main.async { completion(.failure(Self.proxyError(httpStatus, message))) }
                return
            }

            // The thinking field is model-specific. If Gemini rejects it, retry once without.
            if httpStatus == 400, let fallback = thinkingFallbackBody, let data,
               Self.isThinkingRejection(data) {
                var plain = request
                plain.httpBody = fallback
                self.logger.debug("400 mentioning thinking, retrying without thinkingConfig")
                self.performWithRetry(request: plain, attempt: attempt, task: task,
                                      thinkingFallbackBody: nil, expectsJSON: expectsJSON, completion: completion)
                return
            }

            // Retry on 503 with exponential backoff: 1s → 2s → 4s (max 3 retries)
            if httpStatus == 503 && attempt < 3 {
                let delay = pow(2.0, Double(attempt))   // 1, 2, 4 seconds
                self.logger.debug("503 received, retrying in \(Int(delay))s (attempt \(attempt + 1)/3)")
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.performWithRetry(request: request, attempt: attempt + 1, task: task,
                                           thinkingFallbackBody: thinkingFallbackBody, expectsJSON: expectsJSON,
                                           completion: completion)
                }
                return
            }

            guard let data else {
                DispatchQueue.main.async { completion(.failure(self.noDataError())) }
                return
            }

            do {
                let text = try self.parseResponse(data, task: task, expectsJSON: expectsJSON)
                DispatchQueue.main.async { completion(.success(text)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }

    /// True when a Gemini 400 body complains about the thinking settings.
    static func isThinkingRejection(_ data: Data) -> Bool {
        guard let message = proxyMessage(from: data)?.lowercased() else { return false }
        return message.contains("thinking")
    }

    /// Smallest thinking setting per model family. Gemini 2.5 takes a token budget
    /// (0 turns thinking off); Gemini 3.x takes a level.
    static func thinkingConfig(forModel model: String) -> [String: Any]? {
        if model.hasPrefix("gemini-2.5") { return ["thinkingBudget": 0] }
        if model.hasPrefix("gemini-3") { return ["thinkingLevel": "minimal"] }
        return nil
    }

    static func proxyMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }

    // MARK: - Private

    func buildChatRequestBody(
        systemPrompt: String,
        messages: [ChatMessage],
        expectsJSON: Bool,
        options: AIRequestOptions = .default,
        includeThinking: Bool = true
    ) -> [String: Any] {
        var contents: [[String: Any]] = []

        for message in messages {
            let role = message.role == .user ? "user" : "model"
            contents.append([
                "role": role,
                "parts": [["text": message.content]]
            ])
        }

        var generationConfig: [String: Any] = [
            "temperature": options.temperature,
            "maxOutputTokens": options.maxOutputTokens
        ]
        if options.minimalThinking, includeThinking,
           let thinking = Self.thinkingConfig(forModel: model) {
            generationConfig["thinkingConfig"] = thinking
        }
        // Only constrain the response for callers that decode JSON. Setting this
        // unconditionally forces JSON on prose replies too, which no prompt can
        // override — that is how raw JSON ended up in Coach Chat.
        if expectsJSON {
            generationConfig["responseMimeType"] = "application/json"
        }

        return [
            "system_instruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": contents,
            "generationConfig": generationConfig
        ]
    }

    func parseResponse(_ data: Data, task: AITask = .other, expectsJSON: Bool = false) throws -> String {
        if let responseString = String(data: data, encoding: .utf8) {
            logger.debug("Raw API response: \(responseString)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.error("Failed to parse JSON from response")
            throw parseError("invalid JSON")
        }

        if let errorObj = json["error"] as? [String: Any],
           let message = errorObj["message"] as? String {
            logger.error("API error: \(message)")
            throw apiResponseError(message)
        }

        #if DEBUG
        if let usage = AIUsage.from(response: json) {
            AIUsageTracker.shared.recordUsage(task: task, usage: usage)
        }
        #endif

        guard let candidates = json["candidates"] as? [[String: Any]] else {
            logger.error("No 'candidates' array in response. Keys: \(String(describing: json.keys))")
            throw parseError("no candidates")
        }

        guard let firstCandidate = candidates.first else {
            logger.error("Candidates array is empty")
            throw parseError("empty candidates")
        }

        // A JSON reply cut off by the token cap is not a valid plan/note: fail instead of parsing it.
        if expectsJSON, (firstCandidate["finishReason"] as? String) == "MAX_TOKENS" {
            logger.error("finishReason MAX_TOKENS on a JSON task (\(task.rawValue)); discarding truncated reply")
            throw parseError("response truncated (MAX_TOKENS)")
        }

        guard let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            logger.error("Failed to extract text from candidate. Candidate keys: \(String(describing: firstCandidate.keys))")
            throw parseError("invalid structure")
        }

        return text
    }
}

// MARK: - AIProvider Conformance

extension GeminiService: AIProvider {
    var name: String { "Gemini (\(model))" }
    var rateLimitKey: String { "gemini_rate_limit_until_\(model)" }

    var isAvailable: Bool {
        guard proxyURL != nil else { return false }
        if let rateLimitUntil = UserDefaults.standard.object(forKey: rateLimitKey) as? Date {
            return Date() >= rateLimitUntil
        }
        return true
    }

    func generateChat(
        systemPrompt: String,
        messages: [ChatMessage],
        expectsJSON: Bool,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        generateChat(systemPrompt: systemPrompt, messages: messages, expectsJSON: expectsJSON,
                     options: .default, completion: completion)
    }

    func generateChat(
        systemPrompt: String,
        messages: [ChatMessage],
        expectsJSON: Bool,
        options: AIRequestOptions,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        generateChatAsync(
            systemPrompt: systemPrompt,
            messages: messages,
            expectsJSON: expectsJSON,
            options: options,
            completion: completion
        )
    }
}
