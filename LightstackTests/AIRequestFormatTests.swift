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

    // MARK: - Task + request id

    func testBodyCarriesTaskAndRequestID() {
        let options = AIRequestOptions.forTask(.chat)
        let body = GeminiService().buildChatRequestBody(
            systemPrompt: "s", messages: messages, expectsJSON: false, options: options)
        XCTAssertEqual(body["task"] as? String, "chat")
        XCTAssertEqual(body["request_id"] as? String, options.requestID)
    }

    func testEachLogicalRequestGetsItsOwnRequestID() {
        XCTAssertNotEqual(AIRequestOptions.forTask(.chat).requestID, AIRequestOptions.forTask(.chat).requestID)
        XCTAssertNotEqual(AIRequestOptions.default.requestID, AIRequestOptions.default.requestID)
    }

    func testFallbackModelReusesTheSameRequestID() {
        let first = RecordingProvider(name: "first", key: "ai_fmt_test_first",
                                      result: .failure(NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "503 unavailable"])))
        let second = RecordingProvider(name: "second", key: "ai_fmt_test_second", result: .success("ok"))
        let manager = AIServiceManager(providers: [first, second])
        let done = expectation(description: "completion")
        manager.generateChat(systemPrompt: "s", messages: [], expectsJSON: false, options: .forTask(.chat)) { _ in
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(first.requestIDs.count, 1)
        XCTAssertEqual(second.requestIDs.count, 1)
        XCTAssertEqual(first.requestIDs, second.requestIDs)
        UserDefaults.standard.removeObject(forKey: "ai_fmt_test_first")
    }

    func testBudgetRefusalDoesNotFallBackToSecondModel() {
        let refusing = RecordingProvider(
            name: "first", key: "ai_fmt_test_budget_first",
            result: .failure(GeminiService.proxyError(429, "Daily AI limit reached, resets tomorrow.", code: "budget_user_daily")))
        let backup = RecordingProvider(name: "second", key: "ai_fmt_test_budget_second", result: .success("no"))
        let manager = AIServiceManager(providers: [refusing, backup])
        let done = expectation(description: "completion")
        manager.generateChat(systemPrompt: "s", messages: [], expectsJSON: false, options: .forTask(.chat)) { result in
            if case .failure(let error) = result {
                XCTAssertEqual(error.localizedDescription, "Daily AI limit reached, resets tomorrow.")
            } else {
                XCTFail("Expected failure")
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(backup.requestIDs.count, 0)
    }

    // MARK: - Proxy error mapping

    func testProxyCodesMapToUserMessages() {
        XCTAssertEqual(GeminiService.userMessage(forProxyCode: "budget_user_daily", serverMessage: "x"),
                       "Daily AI limit reached, resets tomorrow.")
        XCTAssertEqual(GeminiService.userMessage(forProxyCode: "budget_user_monthly", serverMessage: "x"),
                       "Monthly AI limit reached, resets next month.")
        for code in ["ai_disabled", "budget_global", "budget_unavailable"] {
            XCTAssertEqual(GeminiService.userMessage(forProxyCode: code, serverMessage: "x"),
                           "Coach temporarily unavailable. Please try again later.")
        }
        XCTAssertEqual(GeminiService.userMessage(forProxyCode: "1", serverMessage: "Server says hi"), "Server says hi")
        XCTAssertEqual(GeminiService.userMessage(forProxyCode: nil, serverMessage: nil),
                       "The AI coach is unavailable right now.")
    }

    func testBudgetCodesAreRecognised() {
        for code in ["budget_user_daily", "budget_user_monthly", "budget_global", "ai_disabled", "too_many_in_flight"] {
            XCTAssertTrue(GeminiService.isBudgetCode(code), code)
        }
        XCTAssertFalse(GeminiService.isBudgetCode("rate_limit_minute"))
        XCTAssertFalse(GeminiService.isBudgetCode(nil))
    }

    func testProxyErrorKeepsCode() {
        let error = GeminiService.proxyError(429, "m", code: "budget_user_daily")
        XCTAssertEqual(error.userInfo[GeminiService.proxyErrorCodeKey] as? String, "budget_user_daily")
    }
}

/// Records the request id each call carried. Own type and defaults key so it never clashes with other test stubs.
private final class RecordingProvider: AIProvider {
    let name: String
    let rateLimitKey: String
    let result: Result<String, Error>
    private(set) var requestIDs: [String] = []

    init(name: String, key: String, result: Result<String, Error>) {
        self.name = name
        self.rateLimitKey = key
        self.result = result
    }

    func generateChat(systemPrompt: String, messages: [ChatMessage], expectsJSON: Bool,
                      completion: @escaping (Result<String, Error>) -> Void) {
        completion(result)
    }

    func generateChat(systemPrompt: String, messages: [ChatMessage], expectsJSON: Bool,
                      options: AIRequestOptions, completion: @escaping (Result<String, Error>) -> Void) {
        requestIDs.append(options.requestID)
        completion(result)
    }
}
