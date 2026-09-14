import Foundation
import os

/// Service for Anthropic Claude API (claude-3-5-haiku free tier).
final class ClaudeService: AIProvider {

    private let apiKey: String
    private let session: URLSession
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let model = "claude-3-5-haiku-20241022" // Free tier model
    private let apiVersion = "2023-06-01"
    private let logger = Logger(subsystem: "org.lightstack.app", category: "ClaudeService")

    init() {
        self.apiKey = Bundle.main.infoDictionary?["CLAUDE_API_KEY"] as? String ?? ""
        self.session = URLSession.shared
    }

    // MARK: - AIProvider

    var name: String { "Claude" }
    var rateLimitKey: String { "claude_rate_limit_until" }

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

        let body = buildRequestBody(systemPrompt: systemPrompt, messages: messages)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
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

    private func buildRequestBody(systemPrompt: String, messages: [ChatMessage]) -> [String: Any] {
        var claudeMessages: [[String: String]] = []

        for message in messages {
            let role: String
            switch message.role {
            case .user:
                role = "user"
            case .coach:
                role = "assistant"
            }
            claudeMessages.append(["role": role, "content": message.content])
        }

        return [
            "model": model,
            "system": systemPrompt,
            "messages": claudeMessages,
            "max_tokens": 2048,
            "temperature": 0.7
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

        guard let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            logger.error("Failed to extract content. Keys: \(String(describing: json.keys))")
            throw parseError("invalid structure")
        }

        return text
    }
}
