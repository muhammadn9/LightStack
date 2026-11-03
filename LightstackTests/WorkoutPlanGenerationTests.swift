import XCTest
import Supabase
@testable import Lightstack

/// A scripted AI provider: returns the canned result immediately.
private final class StubAIProvider: AIProvider {
    let name = "Stub"
    let rateLimitKey = "stub_rate_limit_\(UUID().uuidString)"
    var isAvailable: Bool { true }
    var nextAvailableTime: Date? { nil }
    var result: Result<String, Error>
    init(_ result: Result<String, Error>) { self.result = result }
    func markRateLimited(until: Date) {}
    func clearRateLimit() {}
    func generateChat(systemPrompt: String, messages: [ChatMessage], expectsJSON: Bool,
                      completion: @escaping (Result<String, Error>) -> Void) {
        let r = result
        DispatchQueue.main.async { completion(r) }
    }
}

/// Records the options of the plan request (output cap, thinking, response schema).
private final class CapturingAIProvider: AIProvider {
    let name = "Capture"
    let rateLimitKey = "capture_rate_limit_\(UUID().uuidString)"
    var isAvailable: Bool { true }
    var nextAvailableTime: Date? { nil }
    var reply: String
    var captured: AIRequestOptions?
    var capturedSystemPrompt: String?
    init(reply: String) { self.reply = reply }
    func markRateLimited(until: Date) {}
    func clearRateLimit() {}
    func generateChat(systemPrompt: String, messages: [ChatMessage], expectsJSON: Bool,
                      completion: @escaping (Result<String, Error>) -> Void) {
        generateChat(systemPrompt: systemPrompt, messages: messages, expectsJSON: expectsJSON, options: .default,
                     completion: completion)
    }
    func generateChat(systemPrompt: String, messages: [ChatMessage], expectsJSON: Bool, options: AIRequestOptions,
                      completion: @escaping (Result<String, Error>) -> Void) {
        captured = options
        capturedSystemPrompt = systemPrompt
        let r = reply
        DispatchQueue.main.async { completion(.success(r)) }
    }
}

private final class PlanDelegate: WorkoutSessionServiceDelegate {
    var onPlan: (([Exercise]) -> Void)?
    var onFail: ((Error) -> Void)?
    func sessionServiceDidGeneratePlan(_ service: WorkoutSessionService, exercises: [Exercise], setTargets: [UUID: [SetTarget]]) { onPlan?(exercises) }
    func sessionServiceDidReceiveProgressionNote(_ service: WorkoutSessionService, note: String) {}
    func sessionServiceDidSaveWorkout(_ service: WorkoutSessionService) {}
    func sessionServiceDidFail(_ service: WorkoutSessionService, error: Error) { onFail?(error) }
}

@MainActor
final class WorkoutPlanGenerationTests: XCTestCase {

    private var stack: OutboxTestStack!
    private let delegate = PlanDelegate()

    override func setUp() {
        super.setUp()
        stack = OutboxTestStack()
    }

    private func makeService(provider: AIProvider) -> WorkoutSessionService {
        let validation = ValidationService()
        let workouts = WorkoutRepository(localStorage: stack.storage, offlineQueueManager: stack.queue)
        let profiles = ProfileRepository(
            localStorage: stack.storage,
            supabaseService: SupabaseServiceFactory.unreachable(),
            offlineQueueManager: stack.queue
        )
        let months = MonthPlanRepository(
            localStorage: stack.storage,
            supabaseService: SupabaseServiceFactory.unreachable(),
            offlineQueueManager: stack.queue
        )
        let service = WorkoutSessionService(
            aiServiceManager: AIServiceManager(providers: [provider]),
            coachPromptService: CoachPromptService(validationService: validation),
            coachContextBuilder: CoachContextBuilder(
                profileRepository: profiles, workoutRepository: workouts,
                localStorage: stack.storage, validationService: validation
            ),
            workoutRepository: workouts,
            monthPlanRepository: months,
            localStorage: stack.storage,
            validationService: validation,
            offlineQueueManager: stack.queue
        )
        service.delegate = delegate
        return service
    }

    private func localWorkoutCount() -> Int {
        stack.storage.fetchRecentWorkouts(userId: stack.userId, limit: 100).count
    }

    func testFailedGenerationLeavesNoWorkoutLocallyOrInQueue() async {
        let service = makeService(provider: StubAIProvider(.failure(URLError(.notConnectedToInternet))))
        let failed = expectation(description: "failed")
        delegate.onFail = { _ in failed.fulfill() }
        service.generatePlan(userId: stack.userId, workoutType: "Push", time: 45, energy: 3, notes: "note")
        await fulfillment(of: [failed], timeout: 5)

        XCTAssertEqual(localWorkoutCount(), 0)
        XCTAssertNil(service.currentWorkoutId)
        await stack.queue.waitForSubmissions()
        let queued = await stack.queue.pendingCount
        XCTAssertEqual(queued, 0)
    }

    func testUnparseablePlanLeavesNoWorkout() async {
        let service = makeService(provider: StubAIProvider(.success("Sorry, no plan today")))
        let failed = expectation(description: "failed")
        delegate.onFail = { _ in failed.fulfill() }
        service.generatePlan(userId: stack.userId, workoutType: "Push", time: 45, energy: 3, notes: nil)
        await fulfillment(of: [failed], timeout: 5)
        XCTAssertEqual(localWorkoutCount(), 0)
        let queued = await stack.queue.pendingCount
        XCTAssertEqual(queued, 0)
    }

    func testSuccessfulGenerationSavesWorkoutThenExercisesInOrder() async {
        let plan = """
        {"exercises": [{"name": "Barbell Bench Press", "muscle_group": "Chest", "sets": 3, "reps": "8"}]}
        """
        let service = makeService(provider: StubAIProvider(.success(plan)))
        let done = expectation(description: "plan")
        delegate.onPlan = { _ in done.fulfill() }
        service.generatePlan(userId: stack.userId, workoutType: "Push", time: 45, energy: 3, notes: "tweaky shoulder")
        await fulfillment(of: [done], timeout: 5)

        XCTAssertEqual(localWorkoutCount(), 1)
        XCTAssertEqual(service.currentWorkout?.setupNote, "tweaky shoulder")
        await stack.queue.waitForSubmissions()
        let ops = OfflineQueueManager.fkOrdered(await stack.queue.queuedOperations())
        XCTAssertEqual(ops.map(\.type), [.insertWorkout, .insertExercises])
        XCTAssertTrue(stack.remote.calls.isEmpty)
        await stack.flushAll()
        XCTAssertEqual(stack.remote.workouts.count, 1)
        XCTAssertEqual(stack.remote.exercises.count, 1)
        XCTAssertEqual(stack.remote.workouts.values.first?.setupNote, "tweaky shoulder")
    }

    func testResultAfterCancelIsIgnored() async {
        let provider = StubAIProvider(.success(#"{"exercises": [{"name": "Squat", "muscle_group": "Legs", "sets": 3}]}"#))
        let service = makeService(provider: provider)
        var planned = false
        delegate.onPlan = { _ in planned = true }
        service.generatePlan(userId: stack.userId, workoutType: "Legs", time: 45, energy: 3, notes: nil)
        service.clearCurrentWorkout()   // user backed out while the AI was thinking
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(planned)
        XCTAssertEqual(localWorkoutCount(), 0)
    }

    // MARK: - Coach v3 (the coach sets the weights)

    private let v3Reply = """
    {"summary":"Heavy day.","coaching_notes":"x","exercises":[
     {"name":"Barbell Bench Press","muscle_group":"Chest","superset":null,"cue":null,"reason":"No history yet: start moderate.",
      "sets":[{"type":"warmup","weight":65,"reps":8,"rir":4,"rest":60},{"type":"work","weight":115,"reps":8,"rir":2,"rest":120},
              {"type":"work","weight":135,"reps":6,"rir":1,"rest":150}]}]}
    """

    func testPlanRequestCarriesTheSchemaAndTheV3Prompt() async {
        let previous = CoachPreferences.aiSetsWeights
        CoachPreferences.aiSetsWeights = true
        defer { CoachPreferences.aiSetsWeights = previous }
        let provider = CapturingAIProvider(reply: v3Reply)
        let service = makeService(provider: provider)
        let done = expectation(description: "plan")
        delegate.onPlan = { _ in done.fulfill() }
        service.generatePlan(userId: stack.userId, workoutType: "Push", time: 45, energy: 6, notes: nil)
        await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(provider.captured?.task, .plan)
        XCTAssertEqual(provider.captured?.schema, CoachPromptService.planResponseSchema)
        XCTAssertEqual(provider.captured?.thinking, .medium)
        XCTAssertTrue(provider.capturedSystemPrompt?.contains("WRITE TODAY'S PLAN") ?? false)
    }

    func testRollbackSwitchSendsTheV2PromptWithoutASchema() async {
        let previous = CoachPreferences.aiSetsWeights
        CoachPreferences.aiSetsWeights = false
        defer { CoachPreferences.aiSetsWeights = previous }
        let provider = CapturingAIProvider(reply: v3Reply)
        let service = makeService(provider: provider)
        let done = expectation(description: "plan")
        delegate.onPlan = { _ in done.fulfill() }
        service.generatePlan(userId: stack.userId, workoutType: "Push", time: 45, energy: 6, notes: nil)
        await fulfillment(of: [done], timeout: 5)
        XCTAssertNil(provider.captured?.schema)
        XCTAssertTrue(provider.capturedSystemPrompt?.contains("REVIEW THE DRAFT") ?? false)
    }

    func testNumericSetsParseWithWeightsRepsRirRestAndReason() throws {
        let plan = try XCTUnwrap(WorkoutSessionService.plan(fromPlanJSON: v3Reply, workoutId: UUID(), sanitizeLabel: { $0 }))
        let bench = try XCTUnwrap(plan.exercises.first)
        let targets = try XCTUnwrap(plan.setTargets[bench.id])
        XCTAssertEqual(targets.map(\.prefillWeight), ["65", "115", "135"])
        XCTAssertEqual(targets.map(\.prefillReps), ["8", "8", "6"])
        XCTAssertEqual(targets.map(\.prefillRir), ["4", "2", "1"])
        XCTAssertEqual(targets.compactMap(\.restSeconds), [60, 120, 150])
        XCTAssertEqual(plan.reasons[bench.id], "No history yet: start moderate.")
        XCTAssertEqual(plan.summary, "Heavy day.")
        XCTAssertEqual(bench.targetSets, 3)
    }

    private func derivedRoles(_ name: String, _ sets: [String]) throws -> [SetRole] {
        let json = #"{"exercises":[{"name":"\#(name)","muscle_group":"Chest","reason":"r","sets":[\#(sets.joined(separator: ","))]}]}"#
        let plan = try XCTUnwrap(WorkoutSessionService.plan(fromPlanJSON: json, workoutId: UUID(), sanitizeLabel: { $0 }))
        let id = try XCTUnwrap(plan.exercises.first?.id)
        return try XCTUnwrap(plan.setTargets[id]).map(\.resolvedRole)
    }

    private func workJSON(_ weight: Double) -> String {
        #"{"type":"work","weight":\#(weight),"reps":8,"rir":2,"rest":90}"#
    }

    func testRolesAreDerivedFromTheNumbers() throws {
        let warm = #"{"type":"warmup","weight":45,"reps":10,"rir":5,"rest":60}"#
        // The heaviest work set is the top set; Set 1 only when it is more than 10% lighter.
        XCTAssertEqual(try derivedRoles("Barbell Bench Press", [warm, workJSON(100), workJSON(135), workJSON(125)]),
                       [.warmup, .ramp, .top, .straight])
        XCTAssertEqual(try derivedRoles("Barbell Bench Press", [workJSON(125), workJSON(135), workJSON(130)]),
                       [.straight, .top, .straight])
        XCTAssertEqual(try derivedRoles("Barbell Bench Press", [workJSON(135), workJSON(135), workJSON(135)]),
                       [.top, .straight, .straight])
        // Isolation work is all straight sets; weight 0 is bodyweight.
        XCTAssertEqual(try derivedRoles("Cable Fly", [workJSON(30), workJSON(30)]), [.straight, .straight])
        XCTAssertEqual(try derivedRoles("Pull Up", [workJSON(0), workJSON(0)]), [.straight, .straight])
    }

    func testBodyweightSetsKeepBW() throws {
        let json = #"{"exercises":[{"name":"Pull Up","muscle_group":"Back","reason":"r","sets":[{"type":"work","weight":0,"reps":8,"rir":2,"rest":90}]}]}"#
        let plan = try XCTUnwrap(WorkoutSessionService.plan(fromPlanJSON: json, workoutId: UUID(), sanitizeLabel: { $0 }))
        let id = try XCTUnwrap(plan.exercises.first?.id)
        XCTAssertEqual(plan.setTargets[id]?.first?.prefillWeight, "BW")
    }
}
