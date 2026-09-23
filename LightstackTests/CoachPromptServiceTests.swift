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
        XCTAssertFalse(prompt.contains("\"target_weight\""))
        XCTAssertTrue(prompt.contains("NEVER EMIT A WORKOUT PLAN"))
    }

    func testBothVariantsKeepSharedCoachingSections() {
        for includePlan in [true, false] {
            let prompt = service.buildSystemPrompt(profile: nil, includeWorkoutPlanFormat: includePlan)
            XCTAssertTrue(prompt.contains("COACHING IDENTITY"))
            XCTAssertTrue(prompt.contains("TRAINING PRINCIPLES"))
            XCTAssertTrue(prompt.contains("PROGRESSION NOTE"))
        }
    }
}
