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
        XCTAssertTrue(prompt.contains("CONVERSATION FORMAT"))
    }

    /// "Always respond with a workout table" belongs to generation. Left in the
    /// chat prompt it outcompetes the modifications block and the coach answers
    /// with a table, which changes nothing in the app.
    func testChatPromptDoesNotAskForAWorkoutTable() {
        let chat = service.buildSystemPrompt(profile: nil, includeWorkoutPlanFormat: false)
        XCTAssertFalse(chat.contains("Always respond with a workout table"))
        XCTAssertTrue(service.buildSystemPrompt(profile: nil).contains("Always respond with a workout table"))
    }

    /// The chat prompt forbids plan JSON but must still permit the one fenced
    /// block that actually applies changes — otherwise the two rules contradict.
    func testChatPromptPermitsTheModificationsBlock() {
        let prompt = service.buildSystemPrompt(profile: nil, includeWorkoutPlanFormat: false)
        XCTAssertTrue(prompt.contains("single exception"))
        XCTAssertTrue(prompt.contains("markdown table"))
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
