import XCTest
@testable import Lightstack

/// JSON mode is enforced by the Gemini and OpenAI APIs, not by the prompt. If it
/// leaks onto prose calls the athlete sees raw JSON, so pin it to `expectsJSON`.
final class AIRequestFormatTests: XCTestCase {

    private let messages = [ChatMessage(role: .user, content: "How did I do?")]

    // MARK: - Gemini

    private func geminiConfig(expectsJSON: Bool) -> [String: Any] {
        let body = GeminiService().buildChatRequestBody(
            systemPrompt: "system",
            messages: messages,
            expectsJSON: expectsJSON
        )
        return body["generationConfig"] as? [String: Any] ?? [:]
    }

    func testGeminiConstrainsResponseWhenJSONExpected() {
        let config = geminiConfig(expectsJSON: true)
        XCTAssertEqual(config["responseMimeType"] as? String, "application/json")
    }

    func testGeminiLeavesResponseUnconstrainedForProse() {
        let config = geminiConfig(expectsJSON: false)
        XCTAssertNil(config["responseMimeType"])
    }

    func testGeminiKeepsOtherGenerationSettingsEitherWay() {
        for expectsJSON in [true, false] {
            let config = geminiConfig(expectsJSON: expectsJSON)
            XCTAssertEqual(config["temperature"] as? Double, 0.7)
            XCTAssertEqual(config["maxOutputTokens"] as? Int, 8192)
        }
    }

    // MARK: - OpenAI

    private func openAIBody(expectsJSON: Bool) -> [String: Any] {
        OpenAIService().buildRequestBody(
            systemPrompt: "system",
            messages: messages,
            expectsJSON: expectsJSON
        )
    }

    func testOpenAIRequestsJSONObjectWhenJSONExpected() {
        let format = openAIBody(expectsJSON: true)["response_format"] as? [String: String]
        XCTAssertEqual(format?["type"], "json_object")
    }

    func testOpenAIOmitsResponseFormatForProse() {
        XCTAssertNil(openAIBody(expectsJSON: false)["response_format"])
    }

    func testOpenAIKeepsSystemPromptAsFirstMessage() {
        let body = openAIBody(expectsJSON: false)
        let chat = body["messages"] as? [[String: String]]
        XCTAssertEqual(chat?.first?["role"], "system")
        XCTAssertEqual(chat?.first?["content"], "system")
    }
}
