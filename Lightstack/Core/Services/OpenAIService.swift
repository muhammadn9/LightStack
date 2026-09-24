import Foundation
import os

/// Service for OpenAI ChatGPT API (GPT-4o-mini free tier).
final class OpenAIService: AIProvider {

    private let apiKey: String
    private let session: URLSession
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let model = "gpt-4o-mini" // Free tier model
    private let logger = Logger(subsystem: "org.lightstack.app", category: "OpenAIService")

    init() {
        self.apiKey = Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String ?? ""
        self.session = URLSession.shared
    }

    // MARK: - AIProvider

    var name: String { "OpenAI" }
    var rateLimitKey: String { "openai_rate_limit_until" }

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
        logger.debug("🔵 API CALL INITIATED - This counts against quota!")
        logger.debug("System prompt: \(systemPrompt.count) chars")
        logger.debug("Messages: \(messages.count) messages, \(messages.reduce(0) { $0 + $1.content.count }) total chars")

        guard !apiKey.isEmpty else {
            completion(.failure(missingAPIKeyError()))
            return
        }

        guard let url = URL(string: baseURL) else {
            completion(.failure(invalidURLError()))
            return
        }

        let body = buildRequestBody(
            systemPrompt: systemPrompt,
            messages: messages,
            expectsJSON: expectsJSON
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
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

    func buildRequestBody(
        systemPrompt: String,
        messages: [ChatMessage],
        expectsJSON: Bool
    ) -> [String: Any] {
        var chatMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]

        for message in messages {
            let role: String
            switch message.role {
            case .user:
                role = "user"
            case .coach:
                role = "assistant"
            }
            chatMessages.append(["role": role, "content": message.content])
        }

        var body: [String: Any] = [
            "model": model,
            "messages": chatMessages,
            "max_tokens": 2048,
            "temperature": 0.7
        ]
        // See GeminiService: JSON mode is an API-level constraint, so it must
        // only be set for callers that actually decode JSON.
        if expectsJSON {
            body["response_format"] = ["type": "json_object"]
        }
        return body
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

        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            logger.error("Failed to extract content. Keys: \(String(describing: json.keys))")
            throw parseError("invalid structure")
        }

        return content
    }
}
