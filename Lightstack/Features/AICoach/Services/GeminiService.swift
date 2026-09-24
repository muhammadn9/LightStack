import Foundation
import os

// MARK: - GeminiService

/// Handles all Google Gemini API calls.
/// Single responsibility: send prompt, receive response.
/// No context building — that's CoachContextBuilder's job.
final class GeminiService {

    private let logger = Logger(subsystem: "org.lightstack.app", category: "GeminiService")

    private let apiKey: String
    private let session: URLSession
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

    init() {
        self.apiKey = Bundle.main.infoDictionary?["GEMINI_API_KEY"] as? String ?? ""
        self.session = URLSession.shared
    }

    // MARK: - Multi-Turn Chat (Callback-based)

    /// Sends a multi-turn conversation to Gemini with alternating user/model roles.
    /// Retries on HTTP 503 with exponential backoff (1s → 2s → 4s) per Google's recommendation.
    func generateChatAsync(
        systemPrompt: String,
        messages: [ChatMessage],
        expectsJSON: Bool = true,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        logger.debug("🔵 API CALL INITIATED - This counts against quota!")
        logger.debug("System prompt: \(systemPrompt.count) chars")
        logger.debug("Messages: \(messages.count) messages, \(messages.reduce(0) { $0 + $1.content.count }) total chars")

        guard !apiKey.isEmpty else {
            DispatchQueue.main.async { completion(.failure(self.missingAPIKeyError())) }
            return
        }

        guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
            DispatchQueue.main.async { completion(.failure(self.invalidURLError())) }
            return
        }

        let body = buildChatRequestBody(
            systemPrompt: systemPrompt,
            messages: messages,
            expectsJSON: expectsJSON
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        performWithRetry(request: request, attempt: 0, completion: completion)
    }

    /// Executes the request, retrying on 503 with exponential backoff: 1s, 2s, 4s.
    private func performWithRetry(
        request: URLRequest,
        attempt: Int,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 200

            // Retry on 503 with exponential backoff: 1s → 2s → 4s (max 3 retries)
            if httpStatus == 503 && attempt < 3 {
                let delay = pow(2.0, Double(attempt))   // 1, 2, 4 seconds
                self.logger.debug("503 received, retrying in \(Int(delay))s (attempt \(attempt + 1)/3)")
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.performWithRetry(request: request, attempt: attempt + 1, completion: completion)
                }
                return
            }

            guard let data else {
                DispatchQueue.main.async { completion(.failure(self.noDataError())) }
                return
            }

            do {
                let text = try self.parseResponse(data)
                DispatchQueue.main.async { completion(.success(text)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }

    // MARK: - Private

    func buildChatRequestBody(
        systemPrompt: String,
        messages: [ChatMessage],
        expectsJSON: Bool
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
            "temperature": 0.7,
            "maxOutputTokens": 8192
        ]
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

    private func parseResponse(_ data: Data) throws -> String {
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

        guard let candidates = json["candidates"] as? [[String: Any]] else {
            logger.error("No 'candidates' array in response. Keys: \(String(describing: json.keys))")
            throw parseError("no candidates")
        }

        guard let firstCandidate = candidates.first else {
            logger.error("Candidates array is empty")
            throw parseError("empty candidates")
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
    var name: String { "Gemini" }
    var rateLimitKey: String { "gemini_rate_limit_until" }

    var isAvailable: Bool {
        guard !apiKey.isEmpty else { return false }
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
        generateChatAsync(
            systemPrompt: systemPrompt,
            messages: messages,
            expectsJSON: expectsJSON,
            completion: completion
        )
    }
}
