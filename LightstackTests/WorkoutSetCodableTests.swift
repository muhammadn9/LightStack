import XCTest
@testable import Lightstack

final class WorkoutSetCodableTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Round-trip

    func testRoundTripFullyPopulatedWorkoutSet() throws {
        let id = UUID()
        let exerciseId = UUID()
        let recordedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2025-01-15T10:00:00Z"))
        let original = WorkoutSet(
            id: id,
            exerciseId: exerciseId,
            localId: "local-abc-123",
            setNumber: 2,
            weightLbs: 135.5,
            reps: 8,
            rir: 2,
            userFeedback: "felt strong",
            isPR: true,
            syncStatus: .synced,
            recordedAt: recordedAt
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(WorkoutSet.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.exerciseId, original.exerciseId)
        XCTAssertEqual(decoded.localId, original.localId)
        XCTAssertEqual(decoded.setNumber, original.setNumber)
        XCTAssertEqual(decoded.weightLbs, original.weightLbs)
        XCTAssertEqual(decoded.reps, original.reps)
        XCTAssertEqual(decoded.rir, original.rir)
        XCTAssertEqual(decoded.userFeedback, original.userFeedback)
        XCTAssertEqual(decoded.isPR, original.isPR)
        XCTAssertEqual(decoded.recordedAt.timeIntervalSince1970, original.recordedAt.timeIntervalSince1970, accuracy: 1.0)
    }

    // MARK: - Decoding from snake_case JSON

    func testDecodingFromSnakeCaseJSONProducesCorrectStruct() throws {
        let id = UUID()
        let exerciseId = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "exercise_id": "\(exerciseId.uuidString)",
            "local_id": "loc-001",
            "set_number": 3,
            "weight_lbs": 225.0,
            "reps": 5,
            "rir": 1,
            "user_feedback": "PR attempt",
            "is_pr": true,
            "recorded_at": "2025-03-10T08:30:00Z"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try decoder.decode(WorkoutSet.self, from: data)

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.exerciseId, exerciseId)
        XCTAssertEqual(decoded.localId, "loc-001")
        XCTAssertEqual(decoded.setNumber, 3)
        XCTAssertEqual(decoded.weightLbs, 225.0)
        XCTAssertEqual(decoded.reps, 5)
        XCTAssertEqual(decoded.rir, 1)
        XCTAssertEqual(decoded.userFeedback, "PR attempt")
        XCTAssertTrue(decoded.isPR)
    }

    // MARK: - Missing is_pr defaults to false

    func testDecodingMissingIsPRDefaultsFalse() throws {
        let id = UUID()
        let exerciseId = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "exercise_id": "\(exerciseId.uuidString)",
            "set_number": 1,
            "weight_lbs": 100.0,
            "reps": 10,
            "rir": 3,
            "recorded_at": "2025-01-01T12:00:00Z"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try decoder.decode(WorkoutSet.self, from: data)
        XCTAssertFalse(decoded.isPR)
    }

    // MARK: - Missing local_id becomes nil

    func testDecodingMissingLocalIdBecomesNil() throws {
        let id = UUID()
        let exerciseId = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "exercise_id": "\(exerciseId.uuidString)",
            "set_number": 1,
            "weight_lbs": 50.0,
            "reps": 12,
            "rir": 2,
            "recorded_at": "2025-02-20T09:00:00Z"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try decoder.decode(WorkoutSet.self, from: data)
        XCTAssertNil(decoded.localId)
    }
}
