import XCTest
import Supabase
@testable import Lightstack

final class SyncErrorClassifierTests: XCTestCase {

    private func http(_ status: Int) throws -> HTTPError {
        let url = try XCTUnwrap(URL(string: "https://example.invalid"))
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        return HTTPError(data: Data(), response: response)
    }

    func testURLErrorsAreTransient() {
        for code: URLError.Code in [.notConnectedToInternet, .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed] {
            XCTAssertEqual(SyncErrorClassifier.classify(URLError(code), opType: .insertWorkout), .transient)
        }
    }

    func testHTTPStatuses() throws {
        XCTAssertEqual(SyncErrorClassifier.classify(try http(503), opType: .insertSet), .transient)
        XCTAssertEqual(SyncErrorClassifier.classify(try http(500), opType: .insertSet), .transient)
        XCTAssertEqual(SyncErrorClassifier.classify(try http(408), opType: .insertSet), .transient)
        XCTAssertEqual(SyncErrorClassifier.classify(try http(429), opType: .insertSet), .transient)
        XCTAssertEqual(SyncErrorClassifier.classify(try http(401), opType: .insertSet), .auth)
        XCTAssertEqual(SyncErrorClassifier.classify(try http(400), opType: .insertSet), .permanent)
        XCTAssertEqual(SyncErrorClassifier.classify(try http(404), opType: .insertSet), .permanent)
    }

    func testForeignKeyViolationIsDependency() {
        XCTAssertEqual(SyncErrorClassifier.classify(QueueTestError.postgres("23503"), opType: .insertSet), .dependency)
    }

    func testUniqueViolationIsAlreadyAppliedOnlyForInserts() {
        let err = QueueTestError.postgres("23505")
        for t: QueuedOperationType in [.insertWorkout, .insertExercises, .insertSet, .insertPersonalRecord, .insertMonthPlan, .insertPlannedSessions] {
            XCTAssertEqual(SyncErrorClassifier.classify(err, opType: t), .alreadyApplied, "\(t)")
        }
        XCTAssertEqual(SyncErrorClassifier.classify(err, opType: .updateWorkout), .permanent)
    }

    func testAuthErrors() {
        XCTAssertEqual(SyncErrorClassifier.classify(QueueTestError.postgres("PGRST301"), opType: .insertSet), .auth)
        XCTAssertEqual(SyncErrorClassifier.classify(AuthError.sessionMissing, opType: .insertSet), .auth)
    }

    func testPermanentErrors() {
        for code in ["22P02", "23502", "23514", "42P01", "PGRST100"] {
            XCTAssertEqual(SyncErrorClassifier.classify(QueueTestError.postgres(code), opType: .insertSet), .permanent, code)
        }
        let decodeError = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "x"))
        XCTAssertEqual(SyncErrorClassifier.classify(decodeError, opType: .insertSet), .permanent)
    }

    func testRLSRefusalIsADependencyForChildRowsButPermanentForOwnRowTables() {
        let rls = QueueTestError.postgres("42501")
        for t: QueuedOperationType in [.insertExercises, .insertSet, .renameExercises, .deleteExercise, .deleteExercises, .deleteSet] {
            XCTAssertEqual(SyncErrorClassifier.classify(rls, opType: t), .dependency, "\(t)")
        }
        for t: QueuedOperationType in [.insertWorkout, .updateWorkout, .upsertProfile, .insertPersonalRecord, .insertMonthPlan,
                                       .insertPlannedSessions, .upsertRestDay, .insertTombstone] {
            XCTAssertEqual(SyncErrorClassifier.classify(rls, opType: t), .permanent, "\(t)")
        }
    }

    func testRevivalDelaysGrowAndCap() {
        XCTAssertEqual(OfflineQueueManager.revivalDelay(deadLetterCount: 1), 60)
        XCTAssertEqual(OfflineQueueManager.revivalDelay(deadLetterCount: 2), 3600)
        XCTAssertEqual(OfflineQueueManager.revivalDelay(deadLetterCount: 3), 86_400)
        XCTAssertEqual(OfflineQueueManager.revivalDelay(deadLetterCount: 40), 86_400)
    }

    func testUnknownErrorsAreTransient() {
        struct Weird: Error {}
        XCTAssertEqual(SyncErrorClassifier.classify(Weird(), opType: .insertSet), .transient)
        XCTAssertEqual(SyncErrorClassifier.classify(QueueTestError.postgres("08006"), opType: .insertSet), .transient)
        XCTAssertEqual(SyncErrorClassifier.classify(PostgrestError(code: nil, message: "x"), opType: .insertSet), .transient)
    }

    func testBackoffGrowsAndCaps() {
        XCTAssertEqual(OfflineQueueManager.backoff(attempts: 1), 10)
        XCTAssertEqual(OfflineQueueManager.backoff(attempts: 2), 20)
        XCTAssertEqual(OfflineQueueManager.backoff(attempts: 3), 40)
        XCTAssertEqual(OfflineQueueManager.backoff(attempts: 50), 3600)
    }
}
