import Foundation

/// Service for Anthropic Claude API (claude-3-5-haiku free tier).
final class ClaudeService: AIProvider {

    private let apiKey: String
    private let session: URLSession
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let model = "claude-3-5-haiku-20241022" // Free tier model
    private let apiVersion = "2023-06-01"

    init() {
        self.apiKey = Bundle.main.infoDictionary?["CLAUDE_API_KEY"] as? String ?? ""
        self.session = URLSession.shared
    }

    // MARK: - AIProvider

    var name: String { "Claude" }

    var isAvailable: Bool {
        guard !apiKey.isEmpty else { return false }
        if let rateLimitUntil = UserDefaults.standard.object(forKey: "claude_rate_limit_until") as? Date {
            return Date() >= rateLimitUntil
        }
        return true
    }

    var nextAvailableTime: Date? {
        UserDefaults.standard.object(forKey: "claude_rate_limit_until") as? Date
    }

    func generateChat(
        systemPrompt: String,
        messages: [ChatMessage],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        print("[ClaudeService] 🔵 API CALL INITIATED - This counts against quota!")
        print("[ClaudeService] System prompt: \(systemPrompt.count) chars")
        print("[ClaudeService] Messages: \(messages.count) messages, \(messages.reduce(0) { $0 + $1.content.count }) total chars")

        guard !apiKey.isEmpty else{
            let error = NSError(
                domain: "ClaudeService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing CLAUDE_API_KEY"]
            )
            completion(.failure(error))
            return
        }

        guard let url = URL(string: baseURL) else {
            let error = NSError(
                domain: "ClaudeService",
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
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let data = data else {
                let error = NSError(
                    domain: "ClaudeService",
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
        UserDefaults.standard.set(until, forKey: "claude_rate_limit_until")
        print("[ClaudeService] Rate limited until \(until)")
    }

    func clearRateLimit() {
        UserDefaults.standard.removeObject(forKey: "claude_rate_limit_until")
        print("[ClaudeService] Rate limit cleared")
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
        // Log raw response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("[ClaudeService] Raw API response: \(responseString)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[ClaudeService] Failed to parse JSON from response")
            throw NSError(
                domain: "ClaudeService",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse Claude response - invalid JSON"]
            )
        }

        // Check for API error response
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            print("[ClaudeService] API error: \(message)")
            throw NSError(
                domain: "ClaudeService",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Claude API error: \(message)"]
            )
        }

        guard let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            print("[ClaudeService] Failed to extract content. Keys: \(json.keys)")
            throw NSError(
                domain: "ClaudeService",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse Claude response - invalid structure"]
            )
        }

        return text
    }
}
