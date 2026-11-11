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
        XCTAssertLessThan(service.buildSystemPrompt(profile: nil, task: .postWorkout).count, 2_800)
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
        let load = ["mid chest": MuscleLoad(thisWeekSets: 6, avgPrior3WeeksSets: 9, daysSince: 2),
                    "triceps": MuscleLoad(thisWeekSets: 5, avgPrior3WeeksSets: 7, daysSince: 4)]
        let block = try XCTUnwrap(service.briefBlock(briefs: [sampleBrief()], muscleLoad: load, usualMinutes: 58))
        XCTAssertTrue(block.contains("USUAL SESSION: 58 min"), block)
        XCTAssertFalse(block.contains("FUEL"), "fuel has its own block now")
        XCTAssertTrue(block.contains("mid chest 6/9 2d"), block)
        XCTAssertTrue(block.contains("triceps 5/7 4d"), block)
        XCTAssertTrue(block.contains("- Barbell Bench Press: heavy-low (5-7), last 205x5@1, avg RIR 1.5, e1RM 232>236>239, rest 2:50 (rx 2:00) | 1:30 (rx 1:30), mid chest+front delts+triceps"), block)
    }

    func testBriefBlockOmitsFuelWhenNilAndRestWithoutSamples() throws {
        var brief = sampleBrief()
        brief.rest = RestStats()
        let block = try XCTUnwrap(service.briefBlock(briefs: [brief], muscleLoad: [:], usualMinutes: nil))
        XCTAssertFalse(block.contains("FUEL"), block)
        XCTAssertFalse(block.contains("USUAL SESSION"), block)
        XCTAssertFalse(block.contains("MUSCLE LOAD"), block)
        XCTAssertFalse(block.contains("rest 2"), block)
        XCTAssertTrue(block.contains("BRIEF"), block)
        XCTAssertNil(service.briefBlock(briefs: [], muscleLoad: [:], usualMinutes: nil))
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

    // MARK: - Coach memory

    private func memoryWorkout(_ daysAgo: Int, name: String, muscle: String = "Chest", top: (Double, Int, Int),
                               reason: String = "e1RM up, +5", actual: String?, hit: Bool = true,
                               note: String? = nil) -> Workout {
        var doc = CoachReviewDocument()
        let outcome = actual.map { DecisionOutcome(hit: hit, actualTop: $0, rir: nil, shortBy: hit ? 0 : 1, result: hit ? .hold : .missed) }
        doc.decisions = [CoachDecision(
            name: name, muscle: muscle,
            target: PrescribedSet(role: .top, weight: top.0, reps: top.1, rir: top.2, restSeconds: 150),
            sets: nil, reason: reason, context: "last", source: "coach", outcome: outcome)]
        if let note {
            doc.review = SessionReview(
                exercises: [ExerciseReview(name: name, notes: "n", outcome: .hold, nextTarget: nil, missAnalysis: nil, memoryNote: note)],
                overallRead: "r", recurringFlags: [])
        }
        var w = Workout.create(userId: UUID(), workoutType: "Push", energyLevel: 6, timeAvailableMinutes: 45,
                               date: Date(timeIntervalSinceNow: -Double(daysAgo) * 86_400))
        w.aiProgressionNote = doc.encoded()
        return w
    }

    private func draftExercise(_ name: String, muscle: String = "Chest") throws -> DraftExercise {
        let history = [HistorySession(date: Date(timeIntervalSinceNow: -86_400 * 3),
                                      sets: [HistorySet(185, 6, rir: 1), HistorySet(185, 6, rir: 1)]),
                       HistorySession(date: Date(timeIntervalSinceNow: -86_400 * 10),
                                      sets: [HistorySet(180, 6, rir: 2), HistorySet(180, 6, rir: 1)])]
        let result = try XCTUnwrap(ProgressionEngine.plan(ProgressionInput(
            name: name, sessions: history, best: HistorySet(200, 3), allowWarmups: false)))
        return DraftExercise(name: name, muscleGroup: muscle, result: result)
    }

    func testMemoryReturnsTheSameLiftNewestFirstAndLimitsIt() {
        let workouts = [
            memoryWorkout(20, name: "Bench Press", top: (200, 5, 1), actual: "200x5@1"),
            memoryWorkout(3, name: "Bench Press", top: (210, 5, 1), actual: "210x4@0", hit: false, note: "grinds late"),
            memoryWorkout(10, name: "Bench Press", top: (205, 5, 1), actual: "205x6@1"),
            memoryWorkout(1, name: "Bench Press", top: (215, 5, 1), actual: nil),   // not finished: no outcome
            memoryWorkout(5, name: "Incline Dumbbell Press", top: (70, 8, 1), actual: "70x8@1")]
        let m = CoachReviewStore.memory(for: "Bench Press", muscle: "Chest", from: workouts, limit: 3)
        XCTAssertEqual(m.lines.map(\.decision.target.weight), [210, 205, 200])
        XCTAssertEqual(m.note, "grinds late")
        XCTAssertTrue(m.related.isEmpty, "3 hits on the lift itself: no muscle fallback")
        XCTAssertEqual(CoachReviewStore.memory(for: "Bench Press", muscle: "Chest", from: workouts, limit: 2).lines.count, 2)
    }

    func testMemoryFallsBackToTheSameMuscleWhenTheLiftHasFewerThanTwoHits() {
        let workouts = [
            memoryWorkout(3, name: "Bench Press", top: (210, 5, 1), actual: "210x4@0", hit: false),
            memoryWorkout(5, name: "Incline Dumbbell Press", top: (70, 8, 1), actual: "70x8@1"),
            memoryWorkout(9, name: "Incline Dumbbell Press", top: (65, 8, 1), actual: "65x8@1"),
            memoryWorkout(6, name: "Lat Pulldown", muscle: "Back", top: (140, 10, 1), actual: "140x10@1")]
        let m = CoachReviewStore.memory(for: "Bench Press", muscle: "Chest", from: workouts)
        XCTAssertEqual(m.lines.count, 1)
        XCTAssertEqual(m.related.count, 1, "one line per other lift, only the same muscle")
        XCTAssertEqual(m.related.first?.decision.target.weight, 70, "newest call of that lift")
        let none = CoachReviewStore.memory(for: "Squat", muscle: "Legs", from: workouts)
        XCTAssertTrue(none.isEmpty)
    }

    func testMemoryBlockRendersCallsOldestToNewestWithOutcomesAndNote() throws {
        let workouts = [
            memoryWorkout(8, name: "Bench Press", top: (210, 5, 1), actual: "210x4@0", hit: false),
            memoryWorkout(3, name: "Bench Press", top: (205, 5, 1), reason: "retry lighter", actual: "205x6@1", note: "grinds after rep 4")]
        let block = try XCTUnwrap(service.memoryBlock(CoachMemoryIndex(workouts: workouts),
                                                      draft: [try draftExercise("Bench Press")]))
        XCTAssertTrue(block.hasPrefix("COACH MEMORY (your past calls -> what happened; learn from misses):"), block)
        XCTAssertTrue(block.contains("- Bench Press: "), block)
        XCTAssertTrue(block.contains("210x5@1 \"e1RM up, +5\" -> 210x4@0 MISS | "), block)
        XCTAssertTrue(block.contains("205x5@1 \"retry lighter\" -> 205x6@1 HIT"), block)
        XCTAssertTrue(block.contains("\n  note: grinds after rep 4"), block)
        XCTAssertLessThan(try XCTUnwrap(block.range(of: "MISS")).lowerBound, try XCTUnwrap(block.range(of: "HIT")).lowerBound)
        XCTAssertNil(service.memoryBlock(CoachMemoryIndex(), draft: [try draftExercise("Bench Press")]))
    }

    func testMemoryBlockIsInTheV3PlanMessageAndRulesMentionIt() throws {
        let workouts = [memoryWorkout(3, name: "Bench Press", top: (205, 5, 1), actual: "205x6@1")]
        let extras = CoachPromptService.PlanPromptExtras(
            draft: [try draftExercise("Bench Press")], memory: CoachMemoryIndex(workouts: workouts))
        let v3 = service.buildWorkoutRequestMessage(workoutType: "Push", time: 45, energy: 6, notes: nil, coach: extras,
                                                    aiSetsWeights: true)
        XCTAssertTrue(v3.contains("COACH MEMORY"), v3)
        let v2 = service.buildWorkoutRequestMessage(workoutType: "Push", time: 45, energy: 6, notes: nil, coach: extras,
                                                    aiSetsWeights: false)
        XCTAssertFalse(v2.contains("COACH MEMORY"))
        XCTAssertTrue(service.buildSystemPrompt(profile: nil, task: .plan, aiSetsWeights: true)
            .contains("Use COACH MEMORY: repeat what worked, change what missed, and say so in the reason."))
        let post = service.buildSystemPrompt(profile: nil, task: .postWorkout)
        XCTAssertTrue(post.contains("\"memory_note\""))
    }

    // MARK: Goals and memory coverage

    private func goalItems(attempt: Bool) -> [GoalPlanItem] {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 12)) ?? Date()
        let deadline = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 12))
        let step = attempt
            ? CoachGoalStep(text: "attempt 225x1", weight: 225, reps: 1, attempt: true)
            : CoachGoalStep(text: "top single 215x1 @1, then 2 work sets", weight: 215, reps: 1)
        let goal = CoachGoal(exerciseName: "Bench Press", targetWeight: 225, targetReps: 1, deadline: deadline, steps: [step])
        let points = [GoalAssessor.Point(date: now.addingTimeInterval(-3 * 86_400), weight: 220, reps: 1)]
        return GoalPlanner.items(goals: [goal], history: { _ in points }, now: now)
    }

    func testGoalsBlockRendersNumbersDateAndTodaysStep() throws {
        let block = try XCTUnwrap(service.goalsBlock(goalItems(attempt: false)))
        XCTAssertTrue(block.hasPrefix("ACTIVE GOALS:"), block)
        XCTAssertTrue(block.contains("Bench Press 225x1 by 11/07 (e1RM 227 -> need 233)"), block)
        XCTAssertTrue(block.contains("Today's step: top single 215x1 @1, then 2 work sets."), block)
        XCTAssertTrue(block.contains("Build toward them within the rails."), block)
        XCTAssertFalse(block.contains("Attempt day"), block)
        XCTAssertNil(service.goalsBlock([]))
    }

    func testGoalsBlockListsTheLadderOnAnAttemptDay() throws {
        let block = try XCTUnwrap(service.goalsBlock(goalItems(attempt: true)))
        XCTAssertTrue(block.contains("Attempt day: warm-up ladder"), block)
        XCTAssertTrue(block.contains("225x1 (the last is the attempt; the rails allow up to 225)"), block)
    }

    func testGoalsAndOutOfBaselineMemoryAreInTheV3PlanMessageOnly() throws {
        let workouts = [memoryWorkout(3, name: "Cable Fly", top: (40, 12, 2), actual: "40x12@2")]
        let extras = CoachPromptService.PlanPromptExtras(
            draft: [try draftExercise("Bench Press")], memory: CoachMemoryIndex(workouts: workouts),
            memoryLifts: [CoachLiftRef(name: "Cable Fly", muscle: "Chest")],
            goalsBlock: service.goalsBlock(goalItems(attempt: false)))
        let v3 = service.buildWorkoutRequestMessage(workoutType: "Push", time: 45, energy: 6, notes: nil, coach: extras,
                                                    aiSetsWeights: true)
        XCTAssertTrue(v3.contains("ACTIVE GOALS:"), v3)
        XCTAssertTrue(v3.contains("- Cable Fly: "), v3)
        let v2 = service.buildWorkoutRequestMessage(workoutType: "Push", time: 45, energy: 6, notes: nil, coach: extras,
                                                    aiSetsWeights: false)
        XCTAssertFalse(v2.contains("ACTIVE GOALS:"))
        XCTAssertTrue(CoachPromptService.writeRules.contains("ACTIVE GOALS: move toward them; follow today's step when given."))
    }

    func testMemoryBlockCapsLiftsAndSkipsLiftsWithoutMemory() throws {
        var workouts: [Workout] = []
        let names = ["Barbell Row", "Cable Fly", "Goblet Squat", "Hip Thrust", "Lat Pulldown",
                     "Hammer Curl", "Face Pull", "Calf Raise", "Skull Crusher", "Overhead Press"]
        for (i, name) in names.enumerated() {
            workouts.append(memoryWorkout(i + 1, name: name, top: (100, 8, 2), actual: "100x8@2"))
        }
        let extra = [CoachLiftRef(name: "Never Done", muscle: "Chest")] + names.map { CoachLiftRef(name: $0, muscle: "Chest") }
        let block = try XCTUnwrap(service.memoryBlock(CoachMemoryIndex(workouts: workouts), draft: [], extra: extra))
        let own = block.components(separatedBy: "\n").filter { $0.hasPrefix("- ") && !$0.contains("same muscle") }
        XCTAssertEqual(own.count, 8, block)
        XCTAssertFalse(block.contains("Never Done"), block)
    }

    func testPostWorkoutMessageAsksToCongratulateAGoalHit() {
        let goal = CoachGoal(exerciseName: "Bench Press", targetWeight: 225, targetReps: 1)
        let message = service.buildPostWorkoutMessage(workoutType: "Push", exercises: [], sets: [:], achievedGoals: [goal])
        XCTAssertTrue(message.contains("GOAL HIT today: Bench Press 225x1. Congratulate the athlete in overall_read."), message)
        XCTAssertFalse(service.buildPostWorkoutMessage(workoutType: "Push", exercises: [], sets: [:]).contains("GOAL HIT"))
    }
}
