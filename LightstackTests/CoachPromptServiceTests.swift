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

    // MARK: - Decision prompt

    func testPlanPromptAsksTheCoachForDecisionsNotNumbers() {
        let prompt = service.buildSystemPrompt(profile: nil, task: .plan)
        for needle in ["YOUR JOB: DECIDE ON THE APP'S DRAFT",
                       "The app computes every weight and rep from the athlete's log, so never write numbers for a lift that has history",
                       "COACH MEMORY", "ACTIVE GOALS", "ONE decision per lift",
                       "as_planned", "push", "ease", "goal_step", "swap", "add", "dropped",
                       "do not push (the app will refuse) and say so in the summary in one plain sentence",
                       "at most 18 words", "cites specific evidence", "\"progressing strength\"", "no hype, no em dashes",
                       "FUEL AND MEALS", "WORKOUT PLAN FORMAT", "\"decision\": \"as_planned|push|ease|goal_step|swap|add\"",
                       "\"starting_sets\"", "\"coaching_notes\""] {
            XCTAssertTrue(prompt.contains(needle), "missing \(needle)")
        }
        for gone in ["WRITE TODAY'S PLAN", "REVIEW THE DRAFT", "set_targets", "safety rails", "APP BASELINE", "\"verdict\""] {
            XCTAssertFalse(prompt.contains(gone), "still has \(gone)")
        }
        XCTAssertLessThan(prompt.count, 6_000)
    }

    func testPlanSchemaIsCompactAndHasEveryDecision() throws {
        let schema = CoachPromptService.planResponseSchema.definition
        let data = try JSONSerialization.data(withJSONObject: schema)
        XCTAssertLessThan(data.count, 6_000, "the ai-proxy drops schemas over 6000 characters")
        let text = String(decoding: data, as: UTF8.self)
        for needle in ["as_planned", "goal_step", "starting_sets", "replaces", "percent", "dropped", "coaching_notes"] {
            XCTAssertTrue(text.contains(needle), needle)
        }
        XCTAssertFalse(text.contains("nullable"))
    }

    func testPlanMessageLeadsWithTheRecencyNoteAndAsksForDecisions() {
        let extras = CoachPromptService.PlanPromptExtras(recencyNote: "NOTE: chest was trained about 5 hours ago; the app has already held or reduced those lifts.")
        let message = service.buildWorkoutRequestMessage(workoutType: "Push", time: 45, energy: 6, notes: nil, coach: extras)
        XCTAssertTrue(message.hasPrefix("NOTE: chest was trained about 5 hours ago"), message)
        XCTAssertTrue(message.contains("one decision per lift (default as_planned)"), message)
        XCTAssertTrue(message.contains("DRAFT PLAN: none"), "no draft: the coach builds the plan with starting sets")
        XCTAssertFalse(message.contains("APP BASELINE"))
    }

    func testPlanMessageHasNoNoteWhenNothingWasTrainedRecently() {
        let message = service.buildWorkoutRequestMessage(
            workoutType: "Push", time: 45, energy: 6, notes: "left shoulder tweaky",
            coach: CoachPromptService.PlanPromptExtras(constraints: "no smith machine"))
        XCTAssertFalse(message.contains("NOTE:"), message)
        XCTAssertTrue(message.contains("Notes: left shoulder tweaky"))
        XCTAssertTrue(message.contains("Constraints: no smith machine"))
    }

    // MARK: - Coach memory

    private func memoryWorkout(_ daysAgo: Int, name: String, muscle: String = "Chest", top: (Double, Int, Int),
                               reason: String = "e1RM up, +5", actual: String?, hit: Bool = true,
                               note: String? = nil, move: String? = nil) -> Workout {
        var doc = CoachReviewDocument()
        let outcome = actual.map { DecisionOutcome(hit: hit, actualTop: $0, rir: nil, shortBy: hit ? 0 : 1, result: hit ? .hold : .missed) }
        doc.decisions = [CoachDecision(
            name: name, muscle: muscle,
            target: PrescribedSet(role: .top, weight: top.0, reps: top.1, rir: top.2, restSeconds: 150),
            sets: nil, reason: reason, context: "last", source: "coach", outcome: outcome, draftTop: nil, move: move)]
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

    func testDraftLiftsShowTheirMemoryInsideTheirOwnBlock() throws {
        let workouts = [
            memoryWorkout(8, name: "Bench Press", top: (210, 5, 1), actual: "210x4@0", hit: false),
            memoryWorkout(3, name: "Bench Press", top: (205, 5, 1), reason: "retry lighter", actual: "205x6@1", note: "grinds after rep 4",
                          move: "ease")]
        let extras = CoachPromptService.PlanPromptExtras(
            draft: [try draftExercise("Bench Press")], memory: CoachMemoryIndex(workouts: workouts))
        let message = service.buildWorkoutRequestMessage(workoutType: "Push", time: 45, energy: 6, notes: nil, coach: extras)
        XCTAssertTrue(message.contains("memory: "), message)
        XCTAssertTrue(message.contains("210x5@1 -> 210x4@0 MISS | "), message)
        XCTAssertTrue(message.contains("205x5@1 [ease] \"retry lighter\" -> 205x6@1 HIT"), "the newest call keeps its reason: \(message)")
        XCTAssertTrue(message.contains("\n   note: grinds after rep 4"), message)
        XCTAssertFalse(message.contains("COACH MEMORY"), "a draft lift's memory is not a block of its own")
        XCTAssertLessThan(try XCTUnwrap(message.range(of: "MISS")).lowerBound, try XCTUnwrap(message.range(of: "HIT")).lowerBound)
    }

    func testOtherLiftsMemoryBlockSkipsDraftLiftsAndRepeats() throws {
        let workouts = [
            memoryWorkout(3, name: "Cable Fly", top: (40, 12, 2), actual: "40x12@2"),
            memoryWorkout(4, name: "Bench Press", top: (205, 5, 1), actual: "205x6@1")]
        let memory = CoachMemoryIndex(workouts: workouts)
        let block = try XCTUnwrap(service.memoryBlock(
            memory, draft: [try draftExercise("Bench Press")],
            extra: [CoachLiftRef(name: "Cable Fly", muscle: "Chest"), CoachLiftRef(name: "Bench Press", muscle: "Chest")]))
        XCTAssertTrue(block.hasPrefix("COACH MEMORY, other lifts"), block)
        XCTAssertTrue(block.contains("- Cable Fly: "), block)
        XCTAssertFalse(block.contains("- Bench Press"), "a draft lift is shown in its own block")
        XCTAssertFalse(block.contains("same muscle"), "the same-muscle line would repeat the bench entry")
        XCTAssertNil(service.memoryBlock(CoachMemoryIndex(), draft: [], extra: [CoachLiftRef(name: "Cable Fly", muscle: "Chest")]))
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
        XCTAssertEqual(own.count, 6, block)
        XCTAssertFalse(block.contains("Never Done"), block)
    }

    // MARK: Goals

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
        XCTAssertTrue(block.contains("Bench Press 225x1 by 11/07 (now ~227 e1RM, goal needs ~233)"), block)
        XCTAssertTrue(block.contains("Today's step: top single 215x1 @1, then 2 work sets."), block)
        XCTAssertFalse(block.contains("Attempt day"), block)
        XCTAssertNil(service.goalsBlock([]))
    }

    func testGoalsBlockListsTheLadderOnAnAttemptDay() throws {
        let block = try XCTUnwrap(service.goalsBlock(goalItems(attempt: true)))
        XCTAssertTrue(block.contains("Attempt day: warm-up ladder"), block)
        XCTAssertTrue(block.contains("225x1 (the last is the attempt"), block)
    }

    func testGoalsAndLiftBlocksAreInThePlanMessage() throws {
        let extras = CoachPromptService.PlanPromptExtras(
            draft: [try draftExercise("Bench Press")], goalsBlock: service.goalsBlock(goalItems(attempt: false)))
        let message = service.buildWorkoutRequestMessage(workoutType: "Push", time: 45, energy: 6, notes: nil, coach: extras)
        XCTAssertTrue(message.contains("ACTIVE GOALS:"), message)
        XCTAssertTrue(message.contains("DRAFT PLAN (the app's numbers are final for every lift with history"), message)
        XCTAssertTrue(message.contains("1. Bench Press (Chest): "), message)
        XCTAssertTrue(service.buildSystemPrompt(profile: nil, task: .plan).contains("ACTIVE GOALS"))
        XCTAssertTrue(service.buildSystemPrompt(profile: nil, task: .postWorkout).contains("\"memory_note\""))
    }

    func testPostWorkoutMessageAsksToCongratulateAGoalHit() {
        let goal = CoachGoal(exerciseName: "Bench Press", targetWeight: 225, targetReps: 1)
        let message = service.buildPostWorkoutMessage(workoutType: "Push", exercises: [], sets: [:], achievedGoals: [goal])
        XCTAssertTrue(message.contains("GOAL HIT today: Bench Press 225x1. Congratulate the athlete in overall_read."), message)
        XCTAssertFalse(service.buildPostWorkoutMessage(workoutType: "Push", exercises: [], sets: [:]).contains("GOAL HIT"))
    }
}
