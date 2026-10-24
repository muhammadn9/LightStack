import XCTest
@testable import Lightstack

/// State machine behind the Google button: cancel, retry, and a flow that never reports back.
@MainActor
final class GoogleAttemptStateTests: XCTestCase {

    func testCancelledFlowReturnsToIdleAndNextAttemptRuns() async {
        let runner = LatestAttemptRunner()
        runner.start {
            do {
                _ = try await AuthService.awaitCancellable { (finish: (Result<Int, Error>) -> Void) in
                    finish(.failure(NSError(domain: "cancel", code: 1)))
                }
            } catch {}
        }
        await runner.waitUntilIdle()
        XCTAssertFalse(runner.isRunning)

        var ranSecond = false
        runner.start { ranSecond = true }
        await runner.waitUntilIdle()
        XCTAssertTrue(ranSecond)
        XCTAssertFalse(runner.isRunning)
    }

    /// The reported bug: the SDK never calls back. A new tap must still start a fresh attempt.
    func testHungAttemptIsSupersededByNewTap() async {
        let runner = LatestAttemptRunner()
        let firstCancelled = expectation(description: "hung attempt is cancelled")
        let firstStarted = expectation(description: "hung attempt is waiting on the SDK")
        runner.start {
            do {
                _ = try await AuthService.awaitCancellable { (_: @escaping (Result<Int, Error>) -> Void) in
                    firstStarted.fulfill()
                }
            } catch is CancellationError {
                firstCancelled.fulfill()
            } catch {}
        }
        await fulfillment(of: [firstStarted], timeout: 5)
        XCTAssertTrue(runner.isRunning)

        var secondRan = false
        runner.start { secondRan = true }
        await runner.waitUntilIdle()
        XCTAssertTrue(secondRan)
        XCTAssertFalse(runner.isRunning)
        await fulfillment(of: [firstCancelled], timeout: 5)
    }

    func testCancelClearsRunningAttempt() async {
        let runner = LatestAttemptRunner()
        runner.start {
            _ = try? await AuthService.awaitCancellable { (_: @escaping (Result<Int, Error>) -> Void) in }
        }
        await Task.yield()
        XCTAssertTrue(runner.isRunning)
        runner.cancel()
        XCTAssertFalse(runner.isRunning)
    }

    func testCallbackAfterCancellationIsIgnored() async {
        var late: ((Result<Int, Error>) -> Void)?
        let task = Task {
            try await AuthService.awaitCancellable { (finish: @escaping (Result<Int, Error>) -> Void) in late = finish }
        }
        await Task.yield()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("should throw")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        late?(.success(1))   // must not crash (double resume)
    }

    func testResetPasswordMessageForNetworkAndGenericErrors() {
        XCTAssertTrue(AuthService.resetPasswordMessage(for: URLError(.notConnectedToInternet)).contains("connection"))
        let generic = NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        XCTAssertEqual(AuthService.resetPasswordMessage(for: generic), "boom")
    }

    func testSuccessfulAttemptClearsState() async {
        let runner = LatestAttemptRunner()
        runner.start {
            _ = try? await AuthService.awaitCancellable { (finish: (Result<Int, Error>) -> Void) in finish(.success(1)) }
        }
        await runner.waitUntilIdle()
        XCTAssertFalse(runner.isRunning)
    }
}
