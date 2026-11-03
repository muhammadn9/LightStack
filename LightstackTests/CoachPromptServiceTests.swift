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

    func testPostWorkoutPromptHasOnlyTheReviewRules() {
        let prompt = service.buildSystemPrompt(profile: nil, task: .postWorkout)
        XCTAssertTrue(prompt.contains("POST-WORKOUT REVIEW"))
        XCTAssertTrue(prompt.contains("\"overall_read\""))
        XCTAssertTrue(prompt.contains("\"next_target\""))
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
        XCTAssertLessThan(service.buildSystemPrompt(profile: nil, task: .plan).count, 6_000)
        XCTAssertLessThan(service.buildSystemPrompt(profile: nil, task: .postWorkout).count, 2_300)
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

    // MARK: - Brief block

    private func sampleBrief() -> ExerciseBrief {
        ExerciseBrief(
            name: "Barbell Bench Press", primaryMuscles: ["mid chest"], secondaryMuscles: ["front delts", "triceps"],
            style: .heavyLow, repLow: 5, repHigh: 7, lastTop: HistorySet(205, 5, rir: 1), avgRIR: 1.5,
            e1RMTrend: [232, 236, 239],
            rest: RestStats(heavyActual: 170, heavyPrescribed: 120, lightActual: 90, lightPrescribed: 90, samples: 6))
    }

    func testBriefBlockRendersEveryPart() throws {
        let fuel = CoachFuelSummary(yesterdayKcal: 2450, targetKcal: 2600, proteinG: 150, targetProteinG: 180,
                                    goal: "lose", weeklyRate: 0.5)
        let load = ["mid chest": MuscleLoad(thisWeekSets: 6, avgPrior3WeeksSets: 9, daysSince: 2),
                    "triceps": MuscleLoad(thisWeekSets: 5, avgPrior3WeeksSets: 7, daysSince: 4)]
        let block = try XCTUnwrap(service.briefBlock(briefs: [sampleBrief()], muscleLoad: load, fuel: fuel, usualMinutes: 58))
        XCTAssertTrue(block.contains("USUAL SESSION: 58 min"), block)
        XCTAssertTrue(block.contains("FUEL: yesterday 2450/2600 kcal, protein 150/180 g; goal lose 0.5 lb/wk."), block)
        XCTAssertTrue(block.contains("mid chest 6/9 2d"), block)
        XCTAssertTrue(block.contains("triceps 5/7 4d"), block)
        XCTAssertTrue(block.contains("- Barbell Bench Press: heavy-low (5-7), last 205x5@1, avg RIR 1.5, e1RM 232>236>239, rest 2:50 (rx 2:00) | 1:30 (rx 1:30), mid chest+front delts+triceps"), block)
    }

    func testBriefBlockOmitsFuelWhenNilAndRestWithoutSamples() throws {
        var brief = sampleBrief()
        brief.rest = RestStats()
        let block = try XCTUnwrap(service.briefBlock(briefs: [brief], muscleLoad: [:], fuel: nil, usualMinutes: nil))
        XCTAssertFalse(block.contains("FUEL"), block)
        XCTAssertFalse(block.contains("USUAL SESSION"), block)
        XCTAssertFalse(block.contains("MUSCLE LOAD"), block)
        XCTAssertFalse(block.contains("rest 2"), block)
        XCTAssertTrue(block.contains("BRIEF"), block)
        XCTAssertNil(service.briefBlock(briefs: [], muscleLoad: [:], fuel: nil, usualMinutes: nil))
    }

    func testBriefBlockIsAppendedToThePlanMessageAndPromptMentionsIt() {
        let extras = CoachPromptService.PlanPromptExtras(briefBlock: "BRIEF-MARKER-LINE")
        let message = service.buildWorkoutRequestMessage(
            workoutType: "Push", time: 45, energy: 6, notes: nil, coach: extras)
        XCTAssertTrue(message.contains("BRIEF-MARKER-LINE"))
        XCTAssertTrue(message.contains("APP BASELINE"), "existing sections stay")
        XCTAssertTrue(service.buildSystemPrompt(profile: nil, task: .plan).contains("BRIEF"))
    }

    // MARK: - Coach v3 prompt

    func testPlanPromptAsksTheCoachToWriteTheSets() {
        let prompt = service.buildSystemPrompt(profile: nil, task: .plan, aiSetsWeights: true)
        for needle in ["YOUR JOB: WRITE TODAY'S PLAN",
                       "You choose every exercise, set, weight (lb), rep, RIR and rest",
                       "replaced by the app's rule-based baseline, so stay inside",
                       "+10% over that lift's last top set (small lifts: one increment)",
                       "estimated 1RM above the recent best +5%",
                       "More than 14 days since the lift: no increase; more than 28 days: start 5-10% lighter",
                       "RIR 0 on at most one set per exercise; most working sets RIR 1-2",
                       "warm-ups (type \"warmup\") only where you judge the working weight needs them",
                       "2-4 working sets. No back-off unless it serves today's goal. Isolation 2-3 sets. Never pad sets.",
                       "Use the BRIEF", "rest actually taken", "\"reason\" (max 15 words)",
                       "Heavy compounds first", "at most 10 hard sets per muscle",
                       "WORKOUT PLAN FORMAT", "\"type\": \"warmup|work\"", "\"weight\": number (0 = bodyweight)",
                       "\"rir\": int", "\"rest\": int", "\"coaching_notes\""] {
            XCTAssertTrue(prompt.contains(needle), "missing \(needle)")
        }
        XCTAssertFalse(prompt.contains("REVIEW THE DRAFT"))
        XCTAssertFalse(prompt.contains("set_targets"))
        XCTAssertLessThan(prompt.count, 6_000)
    }

    func testRollbackPromptKeepsTheV2ReviewRules() {
        let prompt = service.buildSystemPrompt(profile: nil, task: .plan, aiSetsWeights: false)
        XCTAssertTrue(prompt.contains("REVIEW THE DRAFT"))
        XCTAssertTrue(prompt.contains("set_targets"))
        XCTAssertFalse(prompt.contains("WRITE TODAY'S PLAN"))
    }

    func testV3MessageLabelsTheDraftAsABaselineAndKeepsTheBrief() {
        let extras = CoachPromptService.PlanPromptExtras(briefBlock: "BRIEF-MARKER-LINE")
        let message = service.buildWorkoutRequestMessage(
            workoutType: "Push", time: 45, energy: 6, notes: nil, coach: extras, aiSetsWeights: true)
        XCTAssertTrue(message.contains("APP BASELINE (rule-based; use as a reference)"), message)
        XCTAssertTrue(message.contains("BRIEF-MARKER-LINE"))
        XCTAssertTrue(message.contains("Write today's plan"))
        XCTAssertFalse(message.contains("DRAFT PLAN"))
        XCTAssertFalse(message.contains("Review the DRAFT PLAN"))

        let v2 = service.buildWorkoutRequestMessage(
            workoutType: "Push", time: 45, energy: 6, notes: nil, coach: extras, aiSetsWeights: false)
        XCTAssertTrue(v2.contains("DRAFT PLAN"))
        XCTAssertTrue(v2.contains("Review the DRAFT PLAN"))
    }
}
