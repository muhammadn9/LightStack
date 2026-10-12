import XCTest
@testable import Lightstack

final class CoachPromptServiceTests: XCTestCase {

    private let service = CoachPromptService(validationService: ValidationService())

    /// Generation paths (today's workout, month plan) depend on the bare-JSON
    /// plan schema being present.
    func testGenerationPromptIncludesWorkoutPlanSchema() {
        let prompt = service.buildSystemPrompt(profile: nil)
        XCTAssertTrue(prompt.contains("WORKOUT PLAN FORMAT"))
        XCTAssertTrue(prompt.contains("\"coaching_notes\""))
    }

    /// Coach chat must not carry the plan schema: it instructs the model to
    /// answer with bare JSON, which then lands in a chat bubble.
    func testChatPromptOmitsWorkoutPlanSchema() {
        let prompt = service.buildSystemPrompt(profile: nil, includeWorkoutPlanFormat: false)
        XCTAssertFalse(prompt.contains("WORKOUT PLAN FORMAT"))
        XCTAssertFalse(prompt.contains("\"coaching_notes\""))
        XCTAssertFalse(prompt.contains("\"exercises\": [{"))
        XCTAssertTrue(prompt.contains("CONVERSATION FORMAT"))
    }

    /// "Respond with a workout table" outcompetes the modifications block in chat,
    /// and contradicts the JSON schema in generation. It is in neither prompt.
    func testNoPromptAsksForAWorkoutTable() {
        for task in [CoachPromptService.PromptTask.plan, .chat, .postWorkout, .monthPlan] {
            XCTAssertFalse(service.buildSystemPrompt(profile: nil, task: task).contains("respond with a workout table"))
        }
    }

    func testChatPromptCarriesModificationRulesAndPlanPromptDoesNot() {
        let chat = service.buildSystemPrompt(profile: nil, task: .chat)
        XCTAssertTrue(chat.contains("WORKOUT MODIFICATIONS"))
        XCTAssertTrue(chat.contains("\"modifications\""))
        XCTAssertFalse(service.buildSystemPrompt(profile: nil, task: .plan).contains("WORKOUT MODIFICATIONS"))
    }

    func testPostWorkoutPromptHasOnlyNoteAndSummaryRules() {
        let prompt = service.buildSystemPrompt(profile: nil, task: .postWorkout)
        XCTAssertTrue(prompt.contains("POST-WORKOUT OUTPUT"))
        XCTAssertTrue(prompt.contains("\"summary\""))
        XCTAssertFalse(prompt.contains("WORKOUT PLAN FORMAT"))
        XCTAssertFalse(prompt.contains("WORKOUT MODIFICATIONS"))
        XCTAssertFalse(prompt.contains("TRAINING PRINCIPLES"))
    }

    func testPlanPromptKeepsTheCoachingRulesThatMatter() {
        let prompt = service.buildSystemPrompt(profile: nil, task: .plan)
        for needle in ["RIR", "Progressive overload", "Energy", "Time:", "Cardio"] {
            XCTAssertTrue(prompt.contains(needle), "missing \(needle)")
        }
    }

    func testPromptsAreMuchSmallerThanTheOldSingleSizeFitsAll() {
        // The old prompt was roughly 9,000 characters for every call.
        XCTAssertLessThan(service.buildSystemPrompt(profile: nil, task: .plan).count, 3_000)
        XCTAssertLessThan(service.buildSystemPrompt(profile: nil, task: .postWorkout).count, 1_800)
        XCTAssertLessThan(service.buildSystemPrompt(profile: nil, task: .chat).count, 4_500)
    }

    func testPostWorkoutMessageIsCompact() {
        let ex = Exercise.create(workoutId: UUID(), name: "Bench Press", muscleGroup: "Chest", orderIndex: 0,
                                 targetSets: 2, targetReps: nil, targetRir: nil, restSeconds: nil, coachNote: nil)
        let sets = [ex.id: [
            WorkoutSet.create(exerciseId: ex.id, setNumber: 1, weightLbs: 135, reps: 8, rir: 2),
            WorkoutSet.create(exerciseId: ex.id, setNumber: 2, weightLbs: 135, reps: 7, rir: nil)
        ]]
        let message = service.buildPostWorkoutMessage(workoutType: "Push", exercises: [ex], sets: sets)
        XCTAssertTrue(message.contains("Bench Press: 135x8@2; 135x7"))
        XCTAssertTrue(message.contains("completed sets"))
    }

    /// The chat prompt forbids plan JSON but must still permit the one fenced
    /// block that actually applies changes — otherwise the two rules contradict.
    func testChatPromptPermitsTheModificationsBlock() {
        let prompt = service.buildSystemPrompt(profile: nil, includeWorkoutPlanFormat: false)
        XCTAssertTrue(prompt.contains("single exception"))
        XCTAssertTrue(prompt.contains("markdown table"))
    }

    func testPlanAndChatKeepTheIdentity() {
        for includePlan in [true, false] {
            let prompt = service.buildSystemPrompt(profile: nil, includeWorkoutPlanFormat: includePlan)
            XCTAssertTrue(prompt.contains("COACHING IDENTITY"))
        }
        XCTAssertTrue(service.buildSystemPrompt(profile: nil).contains("TRAINING PRINCIPLES"))
    }
}
