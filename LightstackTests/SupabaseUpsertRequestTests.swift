import XCTest
import Supabase
@testable import Lightstack

/// Records requests instead of sending them.
private final class RecordingURLProtocol: URLProtocol {
    static let lock = NSLock()
    static var requests: [URLRequest] = []

    static func reset() { lock.lock(); requests = []; lock.unlock() }
    static var last: URLRequest? { lock.lock(); defer { lock.unlock() }; return requests.last }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.requests.append(request); Self.lock.unlock()
        let url = request.url ?? URL(fileURLWithPath: "/")
        let response = HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])
        if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
        client?.urlProtocol(self, didLoad: Data("[]".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// The cloud writes the queue replays must be idempotent: upserts keyed on the primary key.
final class SupabaseUpsertRequestTests: XCTestCase {

    private var service: SupabaseService!
    private let userId = UUID()

    override func setUp() {
        super.setUp()
        RecordingURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://example.invalid") ?? URL(fileURLWithPath: "/"),
            supabaseKey: "test",
            options: SupabaseClientOptions(global: .init(session: URLSession(configuration: config)))
        )
        service = SupabaseService(client: client)
    }

    private func assertUpsert(_ path: String, conflict: String, ignoreDuplicates: Bool = false,
                              file: StaticString = #filePath, line: UInt = #line) {
        guard let request = RecordingURLProtocol.last, let url = request.url else {
            return XCTFail("no request recorded", file: file, line: line)
        }
        XCTAssertEqual(request.httpMethod, "POST", file: file, line: line)
        XCTAssertTrue(url.path.hasSuffix(path), url.path, file: file, line: line)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "on_conflict" }?.value, conflict, file: file, line: line)
        let prefer = request.value(forHTTPHeaderField: "Prefer") ?? ""
        XCTAssertTrue(prefer.contains(ignoreDuplicates ? "resolution=ignore-duplicates" : "resolution=merge-duplicates"),
                      prefer, file: file, line: line)
    }

    func testInsertsAreUpsertsOnTheirKey() async throws {
        let w = Workout.create(userId: userId, workoutType: "Push", energyLevel: nil, timeAvailableMinutes: nil)
        let e = Exercise.create(workoutId: w.id, name: "Bench", muscleGroup: "Chest", orderIndex: 0,
                                targetSets: 3, targetReps: "5", targetRir: nil, restSeconds: 90, coachNote: nil)
        let s = WorkoutSet.create(exerciseId: e.id, setNumber: 1, weightLbs: 100, reps: 5, rir: nil)
        let pr = PersonalRecord.create(userId: userId, exerciseName: "Bench", weightLbs: 100, reps: 5, workoutId: nil)
        let plan = MonthPlan.create(userId: userId, title: nil, targetGoal: nil, startDate: Date(),
                                    endDate: Date(), aiOverview: nil)
        let session = PlannedSession.create(monthPlanId: plan.id, userId: userId, plannedDate: Date(),
                                            workoutType: "Push", focusNote: nil, isRestDay: false)

        try await service.insertWorkout(w);           assertUpsert("/workouts", conflict: "id")
        try await service.insertExercises([e]);       assertUpsert("/exercises", conflict: "id")
        try await service.insertSet(s);               assertUpsert("/sets", conflict: "id")
        try await service.insertPersonalRecord(pr);   assertUpsert("/personal_records", conflict: "id")
        try await service.insertMonthPlan(plan);      assertUpsert("/month_plans", conflict: "id")
        try await service.insertPlannedSessions([session]); assertUpsert("/planned_sessions", conflict: "id")
    }

    func testRestDayAndTombstoneUpserts() async throws {
        let rest = RestDay(id: UUID(), userId: userId, date: Date(), createdAt: Date())
        try await service.upsertRestDay(rest)
        assertUpsert("/rest_days", conflict: "user_id,date")
        try await service.insertTombstones(userId: userId, entity: "workout", recordIds: [UUID()], deletedAt: Date())
        assertUpsert("/sync_tombstones", conflict: "user_id,entity,record_id", ignoreDuplicates: true)
    }

    func testWorkoutRowCarriesSetupNote() async throws {
        var w = Workout.create(userId: userId, workoutType: "Push", energyLevel: nil, timeAvailableMinutes: nil)
        w.setupNote = "tight hamstring"
        try await service.insertWorkout(w)
        let body = RecordingURLProtocol.last.flatMap { request -> Data? in
            if let data = request.httpBody { return data }
            guard let stream = request.httpBodyStream else { return nil }
            stream.open(); defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            return data
        }
        let text = body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        XCTAssertTrue(text.contains("\"setup_note\":\"tight hamstring\""), text)
    }

    private func lastBodyText() -> String {
        guard let request = RecordingURLProtocol.last else { return "" }
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var collected = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                collected.append(buffer, count: n)
            }
            data = collected
        }
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// DATE columns are the device-local calendar day, never a timestamp (an evening workout west of
    /// UTC would otherwise be stored under the next day).
    func testDateColumnsAreSentAsTheLocalCalendarDay() async throws {
        let previous = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/Detroit") ?? previous
        defer { NSTimeZone.default = previous }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Detroit") ?? NSTimeZone.default
        // 21:00 on 15 Oct in Detroit is already 16 Oct in UTC.
        let evening = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 21)))

        var w = Workout.create(userId: userId, workoutType: "Push", energyLevel: nil, timeAvailableMinutes: nil)
        w.date = evening
        try await service.insertWorkout(w)
        XCTAssertTrue(lastBodyText().contains("\"date\":\"2026-10-15\""), lastBodyText())
        try await service.updateWorkout(w)
        XCTAssertTrue(lastBodyText().contains("\"date\":\"2026-10-15\""), lastBodyText())

        var pr = PersonalRecord.create(userId: userId, exerciseName: "Bench", weightLbs: 100, reps: 5, workoutId: nil)
        pr.dateAchieved = evening
        try await service.insertPersonalRecord(pr)
        XCTAssertTrue(lastBodyText().contains("\"date_achieved\":\"2026-10-15\""), lastBodyText())

        let plan = MonthPlan.create(userId: userId, title: nil, targetGoal: nil, startDate: evening,
                                    endDate: evening.addingTimeInterval(86_400 * 3), aiOverview: nil)
        try await service.insertMonthPlan(plan)
        XCTAssertTrue(lastBodyText().contains("\"start_date\":\"2026-10-15\""), lastBodyText())
        XCTAssertTrue(lastBodyText().contains("\"end_date\":\"2026-10-18\""), lastBodyText())

        let session = PlannedSession.create(monthPlanId: plan.id, userId: userId, plannedDate: evening,
                                            workoutType: "Push", focusNote: nil, isRestDay: false)
        try await service.insertPlannedSessions([session])
        XCTAssertTrue(lastBodyText().contains("\"planned_date\":\"2026-10-15\""), lastBodyText())
        try await service.updatePlannedSession(session)
        XCTAssertTrue(lastBodyText().contains("\"planned_date\":\"2026-10-15\""), lastBodyText())
    }
}
