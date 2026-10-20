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
        var firstCancelled = false
        runner.start {
            do {
                _ = try await AuthService.awaitCancellable { (_: @escaping (Result<Int, Error>) -> Void) in }
            } catch is CancellationError {
                firstCancelled = true
            } catch {}
        }
        await Task.yield()
        XCTAssertTrue(runner.isRunning)

        var secondRan = false
        runner.start { secondRan = true }
        await runner.waitUntilIdle()
        XCTAssertTrue(secondRan)
        XCTAssertFalse(runner.isRunning)
        await Task.yield()
        XCTAssertTrue(firstCancelled)
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
