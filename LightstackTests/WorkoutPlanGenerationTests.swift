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

    // MARK: - Coach decides, the engine sets the numbers

    private let decisionReply = """
    {"summary":"Steady day.","coaching_notes":"x","exercises":[
     {"name":"Cable Crossover","decision":"add","reason":"No log yet: start light with RIR 3 on the first set.",
      "starting_sets":[{"type":"work","weight":30,"reps":12,"rir":3,"rest":75},{"type":"work","weight":30,"reps":10,"rir":2,"rest":75}]}]}
    """

    func testPlanRequestCarriesTheSchemaLowThinkingAndTheDecisionPrompt() async {
        let provider = CapturingAIProvider(reply: decisionReply)
        let service = makeService(provider: provider)
        let done = expectation(description: "plan")
        delegate.onPlan = { _ in done.fulfill() }
        service.generatePlan(userId: stack.userId, workoutType: "Push", time: 45, energy: 6, notes: nil)
        await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(provider.captured?.task, .plan)
        XCTAssertEqual(provider.captured?.schema, CoachPromptService.planResponseSchema)
        XCTAssertEqual(provider.captured?.thinking, .low)
        XCTAssertEqual(provider.captured?.temperature, 0.2)
        XCTAssertEqual(provider.captured?.maxOutputTokens, 3000)
        XCTAssertTrue(provider.capturedSystemPrompt?.contains("DECIDE ON THE APP'S DRAFT") ?? false)
        XCTAssertFalse(provider.capturedSystemPrompt?.contains("WRITE TODAY'S PLAN") ?? true)
    }

    func testStartingSetsOfANewLiftBecomeThePlan() async throws {
        let service = makeService(provider: StubAIProvider(.success(decisionReply)))
        var planned: [Exercise] = []
        let done = expectation(description: "plan")
        delegate.onPlan = { planned = $0; done.fulfill() }
        service.generatePlan(userId: stack.userId, workoutType: "Push", time: 45, energy: 6, notes: nil)
        await fulfillment(of: [done], timeout: 5)
        let crossover = try XCTUnwrap(planned.first)
        XCTAssertEqual(crossover.name, "Cable Crossover")
        XCTAssertEqual(crossover.targetSets, 2)
        XCTAssertTrue(crossover.coachNoteParts.weight?.hasPrefix("30") ?? false, crossover.coachNote ?? "")
    }

    func testAnUnreadableReplyWithNothingToFallBackOnFailsInsteadOfSavingAnEmptyWorkout() async {
        let service = makeService(provider: StubAIProvider(.success("Here is a plan: bench 3x8")))
        let failed = expectation(description: "failed")
        delegate.onFail = { _ in failed.fulfill() }
        service.generatePlan(userId: stack.userId, workoutType: "Push", time: 45, energy: 6, notes: nil)
        await fulfillment(of: [failed], timeout: 5)
        XCTAssertEqual(localWorkoutCount(), 0)
    }
}
