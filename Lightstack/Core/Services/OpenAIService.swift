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

    var isAvailable: Bool {
        guard !apiKey.isEmpty else { return false }
        if let rateLimitUntil = UserDefaults.standard.object(forKey: "openai_rate_limit_until") as? Date {
            return Date() >= rateLimitUntil
        }
        return true
    }

    var nextAvailableTime: Date? {
        UserDefaults.standard.object(forKey: "openai_rate_limit_until") as? Date
    }

    func generateChat(
        systemPrompt: String,
        messages: [ChatMessage],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        logger.debug("🔵 API CALL INITIATED - This counts against quota!")
        logger.debug("System prompt: \(systemPrompt.count) chars")
        logger.debug("Messages: \(messages.count) messages, \(messages.reduce(0) { $0 + $1.content.count }) total chars")

        guard !apiKey.isEmpty else {
            let error = NSError(
                domain: "OpenAIService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing OPENAI_API_KEY"]
            )
            completion(.failure(error))
            return
        }

        guard let url = URL(string: baseURL) else {
            let error = NSError(
                domain: "OpenAIService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"]
            )
            completion(.failure(error))
            return
        }

        let body = buildRequestBody(systemPrompt: systemPrompt, messages: messages)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let data = data else {
                let error = NSError(
                    domain: "OpenAIService",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "No data received"]
                )
                DispatchQueue.main.async { completion(.failure(error)) }
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

    func markRateLimited(until: Date) {
        UserDefaults.standard.set(until, forKey: "openai_rate_limit_until")
        logger.debug("Rate limited until \(until)")
    }

    func clearRateLimit() {
        UserDefaults.standard.removeObject(forKey: "openai_rate_limit_until")
        logger.debug("Rate limit cleared")
    }

    // MARK: - Private

    private func buildRequestBody(systemPrompt: String, messages: [ChatMessage]) -> [String: Any] {
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

        return [
            "model": model,
            "messages": chatMessages,
            "max_tokens": 2048,
            "temperature": 0.7,
            "response_format": ["type": "json_object"]
        ]
    }

    private func parseResponse(_ data: Data) throws -> String {
        // Log raw response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            logger.debug("Raw API response: \(responseString)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.error("Failed to parse JSON from response")
            throw NSError(
                domain: "OpenAIService",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse OpenAI response - invalid JSON"]
            )
        }

        // Check for API error response
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            logger.error("API error: \(message)")
            throw NSError(
                domain: "OpenAIService",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "OpenAI API error: \(message)"]
            )
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            logger.error("Failed to extract content. Keys: \(String(describing: json.keys))")
            throw NSError(
                domain: "OpenAIService",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse OpenAI response - invalid structure"]
            )
        }

        return content
    }
}
