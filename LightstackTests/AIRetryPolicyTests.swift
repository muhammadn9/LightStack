import XCTest
@testable import Lightstack

/// Per-task retry policy in AIServiceManager: immediate model failover for interactive tasks, one hop after a
/// timeout/504 for the rest, and never retrying the proxy's own refusals on another model.
final class AIRetryPolicyTests: XCTestCase {

    /// A provider that plays back scripted results and records every call it receives.
    private final class Scripted: AIProvider {
        let name: String
        let rateLimitKey = "scripted_rate_limit_\(UUID().uuidString)"
        var isAvailable: Bool { true }
        var nextAvailableTime: Date? { nil }
        var script: [Result<String, Error>]
        private(set) var calls = 0
        var onCall: (() -> Void)?
        private(set) var rateLimitedUntil: Date?
        init(_ name: String, _ script: [Result<String, Error>]) { self.name = name; self.script = script }
        func markRateLimited(until: Date) { rateLimitedUntil = until }
        func clearRateLimit() {}
        func generateChat(systemPrompt: String, messages: [ChatMessage], expectsJSON: Bool,
                          completion: @escaping (Result<String, Error>) -> Void) {
            calls += 1
            onCall?()
            completion(script.isEmpty ? .failure(AITransientError(cause: .busy(503))) : script.removeFirst())
        }
    }

    private let busy503 = Result<String, Error>.failure(AITransientError(cause: .busy(503)))
    private let busy504 = Result<String, Error>.failure(AITransientError(cause: .busy(504)))
    private let timedOut = Result<String, Error>.failure(URLError(.timedOut))
    private let lost = Result<String, Error>.failure(URLError(.networkConnectionLost))
    private let ok = Result<String, Error>.success("ok")

    private func run(_ manager: AIServiceManager, task: AITask = .formFeedback) -> Result<String, Error> {
        var out: Result<String, Error>?
        manager.generateChat(systemPrompt: "s", messages: [ChatMessage(role: .user, content: "m")], expectsJSON: false,
                             options: AIRequestOptions.forTask(task)) { out = $0 }
        return out ?? .failure(NSError(domain: "test", code: 0, userInfo: [NSLocalizedDescriptionKey: "no completion"]))
    }

    // MARK: Form feedback: immediate failover

    func testFormFeedback503OnModelAFailsOverImmediatelyToModelB() throws {
        let a = Scripted("A", [busy503]), b = Scripted("B", [ok])
        let result = run(AIServiceManager(providers: [a, b]))
        XCTAssertEqual(try result.get(), "ok")
        XCTAssertEqual(a.calls, 1)
        XCTAssertEqual(b.calls, 1)
    }

    func testFormFeedback504AndTimeoutAndLostConnectionAllFailOver() throws {
        for failure in [busy504, timedOut, lost] {
            let a = Scripted("A", [failure]), b = Scripted("B", [ok])
            XCTAssertEqual(try run(AIServiceManager(providers: [a, b])).get(), "ok", "\(failure)")
            XCTAssertEqual([a.calls, b.calls], [1, 1])
        }
    }

    func testFormFeedbackTriesTheOriginalModelOnceMoreAfterBothFail() throws {
        let a = Scripted("A", [busy503, ok]), b = Scripted("B", [busy503])
        XCTAssertEqual(try run(AIServiceManager(providers: [a, b])).get(), "ok")
        XCTAssertEqual([a.calls, b.calls], [2, 1])
    }

    func testFormFeedbackGivesUpAfterThreeAttemptsWithBusy() {
        let a = Scripted("A", [busy503, busy503, busy503]), b = Scripted("B", [busy503, busy503])
        let result = run(AIServiceManager(providers: [a, b]))
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual([a.calls, b.calls], [2, 1], "A, B, A and then stop")
        XCTAssertEqual(AIFailureReason.classify(error), .busy)
    }

    func testFormFeedbackSingleModelRetriesOnceThenGivesUp() {
        let a = Scripted("A", [timedOut, timedOut, ok])
        let result = run(AIServiceManager(providers: [a]))
        XCTAssertEqual(a.calls, 2)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(AIFailureReason.classify(error), .busy)
    }

    func testFormFeedbackStopsWhenTheTimeBudgetIsSpent() {
        // Two 26 s attempts leave no room for a third inside ~60 s.
        var clock = Date(timeIntervalSince1970: 1_000)
        let a = Scripted("A", [timedOut, ok]), b = Scripted("B", [timedOut])
        for p in [a, b] { p.onCall = { clock = clock.addingTimeInterval(26) } }
        let result = run(AIServiceManager(providers: [a, b], now: { clock }))
        XCTAssertEqual([a.calls, b.calls], [1, 1])
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(AIFailureReason.classify(error), .busy)
    }

    func testProxyRefusalsAreNeverRetriedOnAnotherModel() {
        for status in [429, 401] {
            let refusal = Result<String, Error>.failure(GeminiService.proxyError(status, "refused"))
            let a = Scripted("A", [refusal]), b = Scripted("B", [ok])
            let result = run(AIServiceManager(providers: [a, b]))
            XCTAssertEqual([a.calls, b.calls], [1, 0], "status \(status)")
            guard case .failure(let error) = result else { return XCTFail("expected failure") }
            XCTAssertEqual(AIFailureReason.classify(error), status == 429 ? .limit : .signedOut)
        }
    }

    func testOtherErrorsAreNotRetried() {
        let a = Scripted("A", [.failure(NSError(domain: "x", code: 3))]), b = Scripted("B", [ok])
        _ = run(AIServiceManager(providers: [a, b]))
        XCTAssertEqual([a.calls, b.calls], [1, 0])
    }

    // MARK: Other tasks keep their behaviour, with timeout/504 now falling back once

    func testPlanTaskFallsBackAfter504() throws {
        let a = Scripted("A", [busy504]), b = Scripted("B", [ok])
        XCTAssertEqual(try run(AIServiceManager(providers: [a, b]), task: .plan).get(), "ok")
        XCTAssertEqual([a.calls, b.calls], [1, 1])
    }

    func testPlanTaskFallsBackAfterTimeoutButOnlyOneHop() {
        let a = Scripted("A", [timedOut]), b = Scripted("B", [timedOut]), c = Scripted("C", [ok])
        let result = run(AIServiceManager(providers: [a, b, c]), task: .plan)
        XCTAssertEqual([a.calls, b.calls, c.calls], [1, 1, 0], "one fallback hop, never doubling the wait twice")
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(AIFailureReason.classify(error), .busy)
    }

    func testPlanTaskTimeoutWithASingleModelFailsWithoutRetrying() {
        let a = Scripted("A", [timedOut, ok])
        _ = run(AIServiceManager(providers: [a]), task: .plan)
        XCTAssertEqual(a.calls, 1)
    }

    func testPlanTask503StillMarksTheModelBusyAndFallsBack() throws {
        let a = Scripted("A", [busy503]), b = Scripted("B", [ok])
        XCTAssertEqual(try run(AIServiceManager(providers: [a, b]), task: .plan).get(), "ok")
        XCTAssertNotNil(a.rateLimitedUntil, "a 503 still marks the model rate limited like before")
    }

    func testPlanTaskTimeoutDoesNotMarkTheModelRateLimited() {
        let a = Scripted("A", [timedOut]), b = Scripted("B", [ok])
        _ = run(AIServiceManager(providers: [a, b]), task: .plan)
        XCTAssertNil(a.rateLimitedUntil)
    }

    func testPlanTaskProxyRefusalStillShownAsIs() {
        let a = Scripted("A", [.failure(GeminiService.proxyError(429, "limit"))]), b = Scripted("B", [ok])
        _ = run(AIServiceManager(providers: [a, b]), task: .plan)
        XCTAssertEqual([a.calls, b.calls], [1, 0])
    }

    // MARK: Policy values and error classes

    func testPolicyValues() {
        XCTAssertEqual(AIRetryPolicy.fastFailover.attemptTimeout, 25)
        XCTAssertEqual(AIRetryPolicy.fastFailover.sameModel503Retries, 0)
        XCTAssertTrue(AIRetryPolicy.fastFailover.failoverImmediately)
        XCTAssertEqual(AIRetryPolicy.fastFailover.totalBudget, 60)
        XCTAssertEqual(AIRetryPolicy.standard.attemptTimeout, 58)
        XCTAssertEqual(AIRetryPolicy.standard.sameModel503Retries, 3)
        XCTAssertFalse(AIRetryPolicy.standard.failoverImmediately)
        XCTAssertEqual(AIRequestOptions.forTask(.plan).retryPolicy, .standard)
        XCTAssertEqual(AIRequestOptions.forTask(.formFeedback).retryPolicy, .fastFailover)
    }

    func testTransientClassification() {
        XCTAssertNotNil(AITransientError.from(URLError(.timedOut)))
        XCTAssertNotNil(AITransientError.from(URLError(.networkConnectionLost)))
        XCTAssertNil(AITransientError.from(URLError(.notConnectedToInternet)))
        XCTAssertNil(AITransientError.from(NSError(domain: "x", code: 1)))
        XCTAssertEqual(AIFailureReason.classify(AIProviderError.allProvidersUnavailable), .busy)
        XCTAssertEqual(AIFailureReason.classify(URLError(.notConnectedToInternet)), .offline)
    }
}
