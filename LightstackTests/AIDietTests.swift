import XCTest
@testable import Lightstack

/// Covers the "AI diet": merged post-workout reply, per-task request bodies,
/// local chat commands and the chat history window.
final class AIDietTests: XCTestCase {

    // MARK: - Merged post-workout reply

    func testParsesNoteAndSummary() {
        let reply = PostWorkoutReply.parse(#"{"note": "Good push. Add 5 lbs.", "summary": "Bench 135x8."}"#)
        XCTAssertEqual(reply.note, "Good push. Add 5 lbs.")
        XCTAssertEqual(reply.summary, "Bench 135x8.")
    }

    func testParsesFencedJSON() {
        let reply = PostWorkoutReply.parse("```json\n{\"note\": \"Nice.\", \"summary\": \"S\"}\n```")
        XCTAssertEqual(reply.note, "Nice.")
        XCTAssertEqual(reply.summary, "S")
    }

    func testProseFallsBackToNoteOnly() {
        let reply = PostWorkoutReply.parse("Solid session. Add 5 lbs next time.")
        XCTAssertEqual(reply.note, "Solid session. Add 5 lbs next time.")
        XCTAssertNil(reply.summary)
    }

    func testTruncatedJSONGivesNoNoteAndNoSummary() {
        let reply = PostWorkoutReply.parse(#"{"note": "Good push. Ad"#)
        XCTAssertEqual(reply.note, "")
        XCTAssertNil(reply.summary)
    }

    func testEmptyAndMissingFields() {
        XCTAssertEqual(PostWorkoutReply.parse("").note, "")
        let noSummary = PostWorkoutReply.parse(#"{"note": "Only a note"}"#)
        XCTAssertEqual(noSummary.note, "Only a note")
        XCTAssertNil(noSummary.summary)
    }

    // MARK: - Per-task request bodies

    private let messages = [ChatMessage(role: .user, content: "hi")]

    private func config(model: String, options: AIRequestOptions, expectsJSON: Bool = false) -> [String: Any] {
        let body = GeminiService(model: model).buildChatRequestBody(
            systemPrompt: "s", messages: messages, expectsJSON: expectsJSON, options: options)
        return body["generationConfig"] as? [String: Any] ?? [:]
    }

    func testPerTaskOutputCaps() {
        var caps: [AITask: Int] = [:]
        for task in AITask.allCases {
            caps[task] = config(model: "gemini-2.5-flash", options: .forTask(task))["maxOutputTokens"] as? Int
        }
        XCTAssertEqual(caps[.plan], 3000)
        XCTAssertEqual(caps[.chat], 1000)
        XCTAssertEqual(caps[.postWorkout], 800)
        XCTAssertEqual(caps[.monthPlan], 4000)
        XCTAssertEqual(caps[.formFeedback], 600)
        XCTAssertEqual(caps[.other], 8192)
        for task in AITask.allCases { XCTAssertLessThanOrEqual(caps[task] ?? 0, 8192) }
    }

    func testThinkingConfigPerModel() {
        let flash25 = config(model: "gemini-2.5-flash", options: .forTask(.chat))["thinkingConfig"] as? [String: Any]
        XCTAssertEqual(flash25?["thinkingBudget"] as? Int, 0)
        let flash35 = config(model: "gemini-3.5-flash", options: .forTask(.chat))["thinkingConfig"] as? [String: Any]
        XCTAssertEqual(flash35?["thinkingLevel"] as? String, "minimal")
    }

    func testDefaultOptionsKeepOldBehaviour() {
        let c = config(model: "gemini-3.5-flash", options: .default)
        XCTAssertNil(c["thinkingConfig"])
        XCTAssertEqual(c["maxOutputTokens"] as? Int, 8192)
        XCTAssertEqual(c["temperature"] as? Double, 0.7)
    }

    func testJSONModeStillFollowsExpectsJSONWithOptions() {
        XCTAssertEqual(config(model: "gemini-2.5-flash", options: .forTask(.plan), expectsJSON: true)["responseMimeType"] as? String,
                       "application/json")
        XCTAssertNil(config(model: "gemini-2.5-flash", options: .forTask(.chat))["responseMimeType"])
    }

    func testThinkingRejectionDetection() {
        let thinking = Data(#"{"error": {"message": "Unknown name \"thinkingLevel\": Cannot find field.  thinking"}}"#.utf8)
        let other = Data(#"{"error": {"message": "API key not valid"}}"#.utf8)
        XCTAssertTrue(GeminiService.isThinkingRejection(thinking))
        XCTAssertFalse(GeminiService.isThinkingRejection(other))
    }

    private func response(finishReason: String) -> Data {
        let part: [String: Any] = ["text": "{\"exercises\": [{\"name\": \"Be"]
        let content: [String: Any] = ["parts": [part]]
        let candidate: [String: Any] = ["finishReason": finishReason, "content": content]
        let json: [String: Any] = ["candidates": [candidate]]
        return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
    }

    func testMaxTokensFailsJSONTasks() {
        let service = GeminiService()
        XCTAssertThrowsError(try service.parseResponse(response(finishReason: "MAX_TOKENS"), task: .plan, expectsJSON: true))
        XCTAssertNoThrow(try service.parseResponse(response(finishReason: "STOP"), task: .plan, expectsJSON: true))
        // Prose tasks keep what was written.
        XCTAssertNoThrow(try service.parseResponse(response(finishReason: "MAX_TOKENS"), task: .chat, expectsJSON: false))
    }

    func testUsageParsing() {
        let json: [String: Any] = ["usageMetadata": ["promptTokenCount": 10, "candidatesTokenCount": 5,
                                                     "thoughtsTokenCount": 2, "totalTokenCount": 17]]
        XCTAssertEqual(AIUsage.from(response: json), AIUsage(prompt: 10, candidates: 5, thoughts: 2, total: 17))
        XCTAssertNil(AIUsage.from(response: [:]))
    }

    // MARK: - History window

    func testHistoryWindowKeepsContextAndLastSix() {
        let all = (0..<20).map { ChatMessage(role: $0 % 2 == 0 ? .user : .coach, content: "m\($0)") }
        let windowed = CoachChatViewModel.windowedMessages(all)
        XCTAssertEqual(windowed.count, 7)
        XCTAssertEqual(windowed.first?.content, "m0")
        XCTAssertEqual(windowed.last?.content, "m19")
        XCTAssertEqual(windowed[1].content, "m14")
    }

    func testShortHistoryIsUntouched() {
        let all = (0..<5).map { ChatMessage(role: .user, content: "m\($0)") }
        XCTAssertEqual(CoachChatViewModel.windowedMessages(all).count, 5)
    }

    // MARK: - Local chat commands

    private func exercise(_ name: String, group: String = "Chest", sets: Int? = 3) -> Exercise {
        Exercise.create(workoutId: UUID(), name: name, muscleGroup: group, orderIndex: 0,
                        targetSets: sets, targetReps: "8", targetRir: "2", restSeconds: 90, coachNote: nil)
    }

    private lazy var workout = [
        exercise("Barbell Bench Press"),
        exercise("Incline Dumbbell Press"),
        exercise("Cable Triceps Pushdown", group: "Triceps"),
        exercise("Leg Press", group: "Legs")
    ]
    private let known = ["Hack Squat", "Leg Press", "Barbell Bench Press", "Dumbbell Bench Press", "Machine Chest Press"]

    private func parse(_ text: String) -> LocalChatCommand? {
        LocalChatCommandParser.parse(text, exercises: workout, knownNames: known)
    }

    func testRemove() {
        let cmd = parse("remove Cable Triceps Pushdown")
        guard case .removeExercise(let name)? = cmd?.modifications.first else { return XCTFail("no remove") }
        XCTAssertEqual(name, "Cable Triceps Pushdown")
        XCTAssertEqual(cmd?.reply, "Removing Cable Triceps Pushdown.")
        XCTAssertNotNil(parse("Please drop the leg press."))
    }

    func testRemoveUnknownOrAmbiguousFallsThrough() {
        XCTAssertNil(parse("remove squats"))
        XCTAssertNil(parse("remove press"))                 // matches several
        XCTAssertNil(parse("remove the last set of leg press"))
        XCTAssertNil(parse("remove leg press and add squats"))
    }

    func testAddSets() {
        guard case .modifyExercise(let name, let sets, _, _, _, _, _, _)? = parse("add a set to leg press")?.modifications.first
        else { return XCTFail("no modify") }
        XCTAssertEqual(name, "Leg Press")
        XCTAssertEqual(sets, 4)
        guard case .modifyExercise(_, let two, _, _, _, _, _, _)? = parse("add 2 sets to Leg Press")?.modifications.first
        else { return XCTFail("no modify") }
        XCTAssertEqual(two, 5)
        XCTAssertNil(parse("add 2 sets to squats"))
        XCTAssertNil(parse("add 20 sets to leg press"))
    }

    func testSwap() {
        let cmd = parse("swap leg press with hack squat")
        guard case .replaceExercise(let old, let new, _, let sets, _, _, _, _, _, _)? = cmd?.modifications.first
        else { return XCTFail("no replace") }
        XCTAssertEqual(old, "Leg Press")
        XCTAssertEqual(new, "Hack Squat")
        XCTAssertEqual(sets, 3)
        XCTAssertNotNil(parse("replace incline dumbbell press for machine chest press"))
    }

    func testSwapAmbiguousOrUnknownTargetFallsThrough() {
        XCTAssertNil(parse("swap leg press with bench"))          // two catalog matches
        XCTAssertNil(parse("swap leg press with floor press"))    // not a known name
        XCTAssertNil(parse("swap press with hack squat"))         // ambiguous source
    }

    func testRest() {
        guard case .modifyExercise(let name, _, _, _, let rest, _, _, _)? = parse("rest 2 min on leg press")?.modifications.first
        else { return XCTFail("no rest") }
        XCTAssertEqual(name, "Leg Press")
        XCTAssertEqual(rest, 120)
        guard case .modifyExercise(_, _, _, _, let secs, _, _, _)? = parse("rest 90 sec on leg press")?.modifications.first
        else { return XCTFail("no rest") }
        XCTAssertEqual(secs, 90)
    }

    func testSetRestForEverything() {
        let cmd = parse("set rest to 60 sec")
        XCTAssertEqual(cmd?.modifications.count, workout.count)
        XCTAssertEqual(parse("set rest to 2 min on leg press")?.modifications.count, 1)
        XCTAssertNil(parse("rest 2 min on squats"))
    }

    func testOrdinaryChatIsNotACommand() {
        for text in ["how was my bench today?", "can I go heavier on bench", "what should I remove to save time?",
                     "rest day tomorrow?", "swap bench for something easier on my shoulder"] {
            XCTAssertNil(parse(text), text)
        }
    }
}
