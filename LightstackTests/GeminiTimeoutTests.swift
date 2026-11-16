import XCTest
@testable import Lightstack

/// A server that accepts the request and then never finishes: it trickles one byte of body now and then, so the
/// URLSession idle timeout would never fire.
private final class TrickleURLProtocol: URLProtocol {
    private var timer: Timer?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url ?? URL(fileURLWithPath: "/"), statusCode: 200,
                                       httpVersion: nil, headerFields: nil)
        if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
        DispatchQueue.main.async { [weak self] in
            self?.timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.client?.urlProtocol(self, didLoad: Data("x".utf8))
            }
        }
    }
    override func stopLoading() { timer?.invalidate(); timer = nil }
}

final class GeminiTimeoutTests: XCTestCase {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TrickleURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func options(timeout: TimeInterval) -> AIRequestOptions {
        var options = AIRequestOptions.default
        options.retryPolicy = AIRetryPolicy(attemptTimeout: timeout, sameModel503Retries: 0,
                                            failoverImmediately: true, totalBudget: 60)
        return options
    }

    private func run(service: GeminiService, timeout: TimeInterval) -> (Result<String, Error>?, TimeInterval, Int) {
        let done = expectation(description: "completion")
        var fired = 0
        var outcome: Result<String, Error>?
        let started = Date()
        service.generateChatAsync(systemPrompt: "s", messages: [ChatMessage(role: .user, content: "hi")],
                                  expectsJSON: false, options: options(timeout: timeout)) { result in
            fired += 1
            outcome = result
            done.fulfill()
        }
        wait(for: [done], timeout: timeout + 3)
        let elapsed = Date().timeIntervalSince(started)
        // Give a late duplicate completion time to show up.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        return (outcome, elapsed, fired)
    }

    func testTricklingResponseFailsWithTimedOutAtTheDeadline() {
        let service = GeminiService(proxyURL: URL(string: "https://example.test/ai-proxy"), anonKey: "k",
                                    accessToken: { "token" }, session: makeSession())
        let (outcome, elapsed, fired) = run(service: service, timeout: 1)
        XCTAssertEqual(fired, 1, "completion must fire exactly once")
        guard case .failure(let error)? = outcome else { return XCTFail("expected failure, got \(String(describing: outcome))") }
        XCTAssertEqual(AITransientError.from(error)?.cause, .timedOut)
        XCTAssertLessThan(elapsed, 2.5)
    }

    func testHangingTokenFetchFailsWithTimedOutAtTheDeadline() {
        let service = GeminiService(proxyURL: URL(string: "https://example.test/ai-proxy"), anonKey: "k",
                                    accessToken: {
                                        try? await Task.sleep(nanoseconds: 60_000_000_000)
                                        return "token"
                                    }, session: makeSession())
        let (outcome, elapsed, fired) = run(service: service, timeout: 1)
        XCTAssertEqual(fired, 1)
        guard case .failure(let error)? = outcome else { return XCTFail("expected failure") }
        XCTAssertEqual(AITransientError.from(error)?.cause, .timedOut)
        XCTAssertLessThan(elapsed, 2.5)
    }
}
