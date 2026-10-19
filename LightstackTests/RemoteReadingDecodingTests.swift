import XCTest
import Supabase
@testable import Lightstack

/// Serves canned PostgREST responses, so the reads can be checked against realistic JSON
/// (DATE columns, microsecond timestamps, numerics, nulls) and the exact requests they send.
private final class CannedURLProtocol: URLProtocol {
    static let lock = NSLock()
    static var body = "[]"
    static var requests: [URLRequest] = []

    static func reset(body: String) { lock.lock(); self.body = body; requests = []; lock.unlock() }
    static var last: URLRequest? { lock.lock(); defer { lock.unlock() }; return requests.last }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.requests.append(request); let body = Self.body; Self.lock.unlock()
        let url = request.url ?? URL(fileURLWithPath: "/")
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])
        if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class RemoteReadingDecodingTests: XCTestCase {

    private var service: SupabaseService!
    private let userId = UUID()

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CannedURLProtocol.self]
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://example.invalid") ?? URL(fileURLWithPath: "/"),
            supabaseKey: "test",
            options: SupabaseClientOptions(global: .init(session: URLSession(configuration: config)))
        )
        service = SupabaseService(client: client)
    }

    private func queryItems() -> [String: String] {
        guard let url = CannedURLProtocol.last?.url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Workouts with embedded exercises and sets

    private func workoutJSON(id: UUID, date: String, createdAt: String, exerciseId: UUID, setId: UUID) -> String {
        """
        {"id":"\(id)","user_id":"\(userId)","local_id":null,"date":"\(date)","workout_type":"Push",
         "duration_minutes":52,"energy_level":7,"time_available_minutes":60,"user_note":null,
         "ai_progression_note":"Add 5 lbs","planned_session_id":null,"setup_note":"tight hamstring",
         "synced":true,"created_at":"\(createdAt)","updated_at":"2026-10-15T15:00:00.5+00:00",
         "exercises":[
           {"id":"\(exerciseId)","workout_id":"\(id)","local_id":null,"name":"Bench Press","muscle_group":"Chest",
            "order_index":0,"target_sets":3,"target_reps":"8","target_rir":"2","rest_seconds":90,"coach_note":null,
            "superset_group_id":null,"created_at":"2026-10-15T14:03:23.000001+00:00",
            "sets":[
              {"id":"\(setId)","exercise_id":"\(exerciseId)","local_id":null,"set_number":2,"weight_lbs":135.5,
               "reps":8,"rir":null,"user_feedback":null,"is_pr":true,"recorded_at":"2026-10-15T14:10:00.250000+00:00",
               "duration_seconds":null,"distance_miles":null,"incline_level":null,"created_at":"2026-10-15T14:10:01+00:00"},
              {"id":"\(UUID())","exercise_id":"\(exerciseId)","local_id":null,"set_number":1,"weight_lbs":135,
               "reps":10,"rir":2,"user_feedback":"easy","is_pr":false,"recorded_at":"2026-10-15T14:05:00+00:00",
               "duration_seconds":600,"distance_miles":1.25,"incline_level":2.5,"created_at":"2026-10-15T14:10:01+00:00"}
            ]}
         ]}
        """
    }

    func testHistoryPageDecodesDateColumnsAndEmbeddedChildren() async throws {
        let id = UUID(), exerciseId = UUID(), setId = UUID()
        // Created on the same UTC day as the stored DATE: the original instant is recovered.
        CannedURLProtocol.reset(body: "[" + workoutJSON(
            id: id, date: "2026-10-15", createdAt: "2026-10-15T14:03:22.123456+00:00",
            exerciseId: exerciseId, setId: setId) + "]")

        let page = try await service.fetchWorkoutHistoryPage(userId: userId, offset: 0, limit: 100)

        XCTAssertEqual(page.count, 1)
        let record = try XCTUnwrap(page.first)
        XCTAssertEqual(record.workout.id, id)
        XCTAssertEqual(record.workout.workoutType, "Push")
        XCTAssertEqual(record.workout.setupNote, "tight hamstring")
        XCTAssertEqual(record.workout.durationMinutes, 52)
        XCTAssertEqual(record.workout.date, record.workout.createdAt)
        XCTAssertEqual(DateFormatter.dateOnly.string(from: record.workout.date), "2026-10-15")

        let exercise = try XCTUnwrap(record.exercises.first)
        XCTAssertEqual(exercise.exercise.name, "Bench Press")
        XCTAssertEqual(exercise.sets.map(\.setNumber), [1, 2], "sets are ordered by set number")
        XCTAssertEqual(exercise.sets[1].weightLbs, 135.5)
        XCTAssertNil(exercise.sets[1].rir)
        XCTAssertTrue(exercise.sets[1].isPR)
        XCTAssertEqual(exercise.sets[0].durationSeconds, 600)
        XCTAssertEqual(exercise.sets[0].distanceMiles, 1.25)
    }

    func testHistoryPageSendsOneEmbeddedPagedRequest() async throws {
        CannedURLProtocol.reset(body: "[]")
        _ = try await service.fetchWorkoutHistoryPage(userId: userId, offset: 200, limit: 100)

        XCTAssertEqual(CannedURLProtocol.requests.count, 1, "one embedded select, not a request per workout")
        let request = try XCTUnwrap(CannedURLProtocol.last)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertTrue(request.url?.path.hasSuffix("/workouts") ?? false)
        let items = queryItems()
        XCTAssertEqual(items["select"], "*,exercises(*,sets(*))")
        XCTAssertEqual(items["user_id"], "eq.\(userId.uuidString)")
        XCTAssertEqual(items["order"], "date.desc.nullslast,id.asc.nullslast")
        XCTAssertEqual(items["limit"], "100")
        XCTAssertEqual(items["offset"], "200")
    }

    func testWorkoutDateOfAnImportedPastWorkoutLandsOnThatLocalDay() async throws {
        // created_at (import day) is not on the stored day, so the stored day wins, at local noon.
        CannedURLProtocol.reset(body: "[" + workoutJSON(
            id: UUID(), date: "2026-09-01", createdAt: "2026-10-15T14:03:22+00:00",
            exerciseId: UUID(), setId: UUID()) + "]")
        let page = try await service.fetchWorkoutHistoryPage(userId: userId, offset: 0, limit: 100)
        let date = try XCTUnwrap(page.first?.workout.date)
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour], from: date)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour], [2026, 9, 1, 12])
    }

    func testWorkoutWithoutChildrenDecodesAsEmpty() async throws {
        CannedURLProtocol.reset(body: """
        [{"id":"\(UUID())","user_id":"\(userId)","date":"2026-10-15","workout_type":"Pull",
          "created_at":"2026-10-15T09:00:00+00:00","exercises":[]}]
        """)
        let page = try await service.fetchWorkoutHistoryPage(userId: userId, offset: 0, limit: 100)
        XCTAssertEqual(page.first?.exercises.count, 0)
    }

    // MARK: - Other reads

    func testActiveMonthPlanAndSessionsDecodeTheirDateColumns() async throws {
        let planId = UUID()
        CannedURLProtocol.reset(body: """
        [{"id":"\(planId)","user_id":"\(userId)","title":"Block","target_goal":null,
          "start_date":"2026-10-01","end_date":"2026-10-31","ai_overview":null,
          "created_at":"2026-10-01T08:00:00.123456+00:00"}]
        """)
        let plan = try await service.fetchActiveMonthPlan(userId: userId)
        XCTAssertEqual(plan?.id, planId)
        let start = try XCTUnwrap(plan?.startDate)
        XCTAssertEqual(Calendar.current.dateComponents([.month, .day], from: start).day, 1)

        CannedURLProtocol.reset(body: """
        [{"id":"\(UUID())","month_plan_id":"\(planId)","user_id":"\(userId)","planned_date":"2026-10-05",
          "workout_type":"Push","focus_note":null,"is_rest_day":false,"completed":true,"workout_id":null}]
        """)
        let sessions = try await service.fetchPlannedSessions(monthPlanId: planId)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertTrue(sessions[0].completed)
    }

    func testRestDaysTombstonesAndSummariesDecode() async throws {
        CannedURLProtocol.reset(body: """
        [{"id":"\(UUID())","user_id":"\(userId)","date":"2026-10-14","created_at":"2026-10-14T20:00:00.5+00:00"}]
        """)
        let days = try await service.fetchRestDays(userId: userId)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(RestDay.dayString(days[0].date), "2026-10-14")

        let deleted = UUID()
        CannedURLProtocol.reset(body: """
        [{"entity":"workout","record_id":"\(deleted)","deleted_at":"2026-10-10T12:00:00.123456+00:00"}]
        """)
        let tombstones = try await service.fetchTombstones(userId: userId)
        XCTAssertEqual(tombstones, [RemoteTombstone(entity: "workout", recordId: deleted,
                                                     deletedAt: tombstones.first?.deletedAt)])
        XCTAssertEqual(queryItems()["user_id"], "eq.\(userId.uuidString)")

        CannedURLProtocol.reset(body: """
        [{"id":"\(UUID())","user_id":"\(userId)","workout_type":"Push","summary_text":"Steady",
          "sessions_covered":4,"last_updated":"2026-10-15T10:00:00.5+00:00"}]
        """)
        let summaries = try await service.fetchContextSummaries(userId: userId)
        XCTAssertEqual(summaries.first?.sessionsCovered, 4)
    }

    func testProfileDecodes() async throws {
        CannedURLProtocol.reset(body: """
        [{"id":"\(UUID())","user_id":"\(userId)","display_name":"Sam","age":31,"height_inches":70.5,"weight_lbs":182.5,
          "training_age_months":36,"primary_goals":["Strength"],"split_days":["Push","Pull"],
          "avoid_exercises":["Upright Row"],"equipment":{"Barbell":true,"Cables":false},"custom_equipment":"Sled",
          "notes_to_coach":"Left shoulder","created_at":"2026-01-01T08:00:00.123456+00:00",
          "updated_at":"2026-10-01T08:00:00+00:00"}]
        """)
        let profile = try await service.fetchProfile(userId: userId)
        XCTAssertEqual(profile?.avoidExercises, ["Upright Row"])
        XCTAssertEqual(profile?.notesToCoach, "Left shoulder")
        XCTAssertEqual(profile?.equipment["Barbell"], true)
    }

    // MARK: - Workout day, legacy and current rows

    private func restoredWorkoutDate(storedDate: String, createdAt: String) async throws -> Date {
        CannedURLProtocol.reset(body: "[" + workoutJSON(id: UUID(), date: storedDate, createdAt: createdAt,
                                                         exerciseId: UUID(), setId: UUID()) + "]")
        let page = try await service.fetchWorkoutHistoryPage(userId: userId, offset: 0, limit: 100)
        return try XCTUnwrap(page.first?.workout.date)
    }

    func testEveningWorkoutRoundTripsToTheSameLocalDay() async throws {
        let previous = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/Detroit") ?? previous
        defer { NSTimeZone.default = previous }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Detroit") ?? .current
        let evening = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 21)))

        // Upload side: stored day is the local day.
        var workout = Workout.create(userId: userId, workoutType: "Push", energyLevel: nil, timeAvailableMinutes: nil)
        workout.date = evening
        workout.createdAt = evening
        let stored = workout.toSupabase().date
        XCTAssertEqual(stored, "2026-10-15")

        // Restore side: 21:00 Detroit is 01:00Z on the 16th, so created_at is not on the stored day.
        let restored = try await restoredWorkoutDate(storedDate: stored, createdAt: "2026-10-16T01:00:00+00:00")
        let parts = calendar.dateComponents([.year, .month, .day], from: restored)
        XCTAssertEqual([parts.year, parts.month, parts.day], [2026, 10, 15])
    }

    func testLegacyRowStoredAsTheNextUTCDayRestoresToTheLocalEvening() async throws {
        let previous = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/Detroit") ?? previous
        defer { NSTimeZone.default = previous }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Detroit") ?? .current

        // Old build: the instant was uploaded, so Postgres kept the UTC day (16th).
        let restored = try await restoredWorkoutDate(storedDate: "2026-10-16", createdAt: "2026-10-16T01:00:00+00:00")
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: restored)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour], [2026, 10, 15, 21])
    }

    func testMorningWorkoutOfEitherKindKeepsItsLocalDay() async throws {
        let previous = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/Detroit") ?? previous
        defer { NSTimeZone.default = previous }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Detroit") ?? .current
        // 09:00 Detroit = 13:00Z the same day: legacy and current rows both say the 15th.
        let restored = try await restoredWorkoutDate(storedDate: "2026-10-15", createdAt: "2026-10-15T13:00:00+00:00")
        XCTAssertEqual(calendar.component(.day, from: restored), 15)
    }
}
