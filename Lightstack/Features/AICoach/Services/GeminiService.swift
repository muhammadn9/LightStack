import Foundation

// MARK: - GeminiServiceDelegate

protocol GeminiServiceDelegate: AnyObject {
    func geminiService(_ service: GeminiService, didReceiveResponse text: String)
    func geminiService(_ service: GeminiService, didFailWith error: Error)
}

// MARK: - GeminiService

/// Handles all Google Gemini API calls.
/// Single responsibility: send prompt, receive response.
/// No context building — that's CoachContextBuilder's job.
final class GeminiService {

    weak var delegate: GeminiServiceDelegate?

    private let apiKey: String
    private let session: URLSession
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"

    init() {
        self.apiKey = Bundle.main.infoDictionary?["GEMINI_API_KEY"] as? String ?? ""
        self.session = URLSession.shared
    }

    // MARK: - Single-Turn (Delegate-based)

    func generateContent(systemPrompt: String, userMessage: String) {
        guard !apiKey.isEmpty else {
            let error = NSError(domain: "GeminiService", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Missing GEMINI_API_KEY"])
            delegate?.geminiService(self, didFailWith: error)
            return
        }

        guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
            let error = NSError(domain: "GeminiService", code: -2,
                                userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
            delegate?.geminiService(self, didFailWith: error)
            return
        }

        let body = buildRequestBody(systemPrompt: systemPrompt, userMessage: userMessage)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            delegate?.geminiService(self, didFailWith: error)
            return
        }

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                self.notifyError(error)
                return
            }

            guard let data = data else {
                let error = NSError(domain: "GeminiService", code: -3,
                                    userInfo: [NSLocalizedDescriptionKey: "No response data"])
                self.notifyError(error)
                return
            }

            do {
                let text = try self.parseResponse(data)
                self.notifyResponse(text)
            } catch {
                self.notifyError(error)
            }
        }
        task.resume()
    }

    // MARK: - Multi-Turn Chat (Callback-based)

    /// Sends a multi-turn conversation to Gemini with alternating user/model roles.
    /// Uses a completion handler instead of the delegate to support multiple concurrent calls.
    func generateChatAsync(
        systemPrompt: String,
        messages: [ChatMessage],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard !apiKey.isEmpty else {
            let error = NSError(domain: "GeminiService", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Missing GEMINI_API_KEY"])
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
            let error = NSError(domain: "GeminiService", code: -2,
                                userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        let body = buildChatRequestBody(systemPrompt: systemPrompt, messages: messages)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        let task = session.dataTask(with: request) { [weak self] data, _, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let data = data else {
                let error = NSError(domain: "GeminiService", code: -3,
                                    userInfo: [NSLocalizedDescriptionKey: "No response data"])
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            do {
                let text = try self?.parseResponse(data) ?? ""
                DispatchQueue.main.async { completion(.success(text)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }

    // MARK: - Private

    private func buildRequestBody(systemPrompt: String, userMessage: String) -> [String: Any] {
        [
            "system_instruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": userMessage]]
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 2048
            ]
        ]
    }

    private func buildChatRequestBody(systemPrompt: String, messages: [ChatMessage]) -> [String: Any] {
        var contents: [[String: Any]] = []

        for message in messages {
            let role = message.role == .user ? "user" : "model"
            contents.append([
                "role": role,
                "parts": [["text": message.content]]
            ])
        }

        return [
            "system_instruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": contents,
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 2048
            ]
        ]
    }

    private func parseResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String
        else {
            throw NSError(domain: "GeminiService", code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to parse Gemini response"])
        }
        return text
    }

    private func notifyResponse(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.geminiService(self, didReceiveResponse: text)
        }
    }

    private func notifyError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.geminiService(self, didFailWith: error)
        }
    }
}
