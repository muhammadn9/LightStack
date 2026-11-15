import XCTest
@testable import Lightstack

/// JSON mode is enforced by the Gemini API, not by the prompt. If it
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

    // MARK: - Thinking and schema

    func testMediumThinkingMapsPerModel() {
        XCTAssertEqual(GeminiService.thinkingConfig(forModel: "gemini-3.5-flash", effort: .medium) as? [String: String],
                       ["thinkingLevel": "medium"])
        XCTAssertEqual(GeminiService.thinkingConfig(forModel: "gemini-2.5-flash", effort: .medium) as? [String: Int],
                       ["thinkingBudget": 4096])
    }

    func testPlanTaskUsesLowThinkingLowTemperatureAndRoomForTheCompactJSON() {
        let options = AIRequestOptions.forTask(.plan)
        XCTAssertEqual(options.thinking, .low)
        XCTAssertEqual(options.temperature, 0.2)
        XCTAssertEqual(options.maxOutputTokens, 3000)
        XCTAssertNil(options.schema)
        XCTAssertEqual(AIRequestOptions.forTask(.postWorkout).temperature, 0.3)
    }

    private let sampleSchema = AIResponseSchema([
        "type": "OBJECT",
        "properties": ["title": ["type": "STRING"]]
    ])

    func testSchemaIsSentWhenSetAndJSONExpected() {
        let body = GeminiService().buildChatRequestBody(
            systemPrompt: "system", messages: messages, expectsJSON: true,
            options: AIRequestOptions(schema: sampleSchema))
        let config = body["generationConfig"] as? [String: Any]
        let sent = config?["responseSchema"] as? [String: Any]
        XCTAssertEqual(sent?["type"] as? String, "OBJECT")
    }

    func testNoSchemaWhenNotSetOrNotJSON() {
        let plain = GeminiService().buildChatRequestBody(
            systemPrompt: "system", messages: messages, expectsJSON: true)
        XCTAssertNil((plain["generationConfig"] as? [String: Any])?["responseSchema"])

        let prose = GeminiService().buildChatRequestBody(
            systemPrompt: "system", messages: messages, expectsJSON: false,
            options: AIRequestOptions(schema: sampleSchema))
        XCTAssertNil((prose["generationConfig"] as? [String: Any])?["responseSchema"])
    }

    // MARK: - Plan schema

    func testPlanSchemaIsSmallAndDescribesTheCoachDecisions() throws {
        let schema = CoachPromptService.planResponseSchema
        let data = try JSONSerialization.data(withJSONObject: schema.definition)
        XCTAssertLessThan(data.count, 6000)
        let text = String(decoding: data, as: UTF8.self)
        for key in ["summary", "exercises", "dropped", "coaching_notes", "decision", "percent", "replaces", "superset", "cue",
                    "reason", "sets", "starting_sets", "weight", "reps", "rir", "rest", "warmup", "work",
                    "as_planned", "push", "ease", "goal_step", "swap", "add"] {
            XCTAssertTrue(text.contains("\"\(key)\""), "schema is missing \(key)")
        }
    }

    func testPlanRequestCarriesTheSchemaAsResponseSchema() {
        var options = AIRequestOptions.forTask(.plan)
        options.schema = CoachPromptService.planResponseSchema
        let body = GeminiService().buildChatRequestBody(
            systemPrompt: "system", messages: messages, expectsJSON: true, options: options)
        let config = body["generationConfig"] as? [String: Any]
        let sent = config?["responseSchema"] as? [String: Any]
        XCTAssertEqual(sent?["type"] as? String, "OBJECT")
        let properties = sent?["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["exercises"])
        XCTAssertEqual(config?["maxOutputTokens"] as? Int, 3000)
        XCTAssertEqual(config?["temperature"] as? Double, 0.2)
        XCTAssertNotNil(config?["thinkingConfig"])
    }
}
