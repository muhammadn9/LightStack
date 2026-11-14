import XCTest
@testable import Lightstack

/// Builds the plan-decision context for the golden scenario (or a rested variant of it) and fake coach replies.
enum DecisionHarness {

    typealias G = GoldenScenario

    /// The same-day Push request of 11/12 by default (chest, shoulders and triceps trained 5 hours ago, deep deficit).
    /// `rested` moves to 11/14 morning with nothing held: the engine may progress.
    static func context(rested: Bool = false, withFuel: Bool = true, minutes: Int = 45,
                        goals: [GoalPlanItem] = [], memory: CoachMemoryIndex = CoachMemoryIndex(),
                        extraHistory: [ExerciseHistoryGroup] = [], lastExercises: [Exercise]? = nil,
                        now: Date? = nil) -> PlanDecisionContext {
        var coach = rested ? G.planContext(withFuel: false, now: G.date(11, 14, hour: 9)) : G.planContext(withFuel: withFuel)
        if rested { coach.recency = [:] }
        if let now { coach.now = now }
        let history = ExerciseHistoryIndex(groups: G.historyForPlanRequest.groups + extraHistory)
        let draft = PlanDraftBuilder.build(lastSessionExercises: lastExercises ?? G.lastSessionExercises(), history: history,
                                           energy: 6, feedback: nil, coach: coach, timeMinutes: nil)
        return PlanDecisionContext(workoutId: UUID(), draft: draft, history: history, coach: coach, energy: 6, timeMinutes: minutes,
                                   goalItems: goals, memory: memory,
                                   canonicalName: { ExerciseNameResolver.Canonical(name: $0, isPerArm: false) })
    }

    /// One reply entry as JSON.
    static func entry(_ name: String, _ decision: String? = nil, reason: String = "Last top set 185x5 on 11/12, repeat it.",
                      extra: String = "") -> String {
        var parts = ["\"name\":\"\(name)\""]
        if let decision { parts.append("\"decision\":\"\(decision)\"") }
        if !reason.isEmpty { parts.append("\"reason\":\"\(reason)\"") }
        if !extra.isEmpty { parts.append(extra) }
        return "{" + parts.joined(separator: ",") + "}"
    }

    static func reply(_ entries: [String], summary: String = "Steady day.", extra: String = "") -> CoachPlanReply? {
        CoachPlanReply.parse("{\"summary\":\"\(summary)\",\"exercises\":[\(entries.joined(separator: ","))]\(extra)}")
    }

    /// The engine's own sets for a draft lift.
    static func draftTargets(_ ctx: PlanDecisionContext, _ name: String) -> [SetTarget] {
        ctx.draft.first { $0.name == name }?.result.sets.map(\.setTarget) ?? []
    }

    static func targets(_ plan: AppliedPlan, _ name: String) -> [SetTarget] {
        guard let ex = plan.exercises.first(where: { $0.name == name }) else { return [] }
        return plan.setTargets[ex.id] ?? []
    }

    static func decision(_ plan: AppliedPlan, _ name: String) -> LiftDecision? { plan.review.decision(for: name) }

    static func top(_ targets: [SetTarget]) -> (weight: Double, reps: Int)? {
        guard let t = targets.first(where: { $0.resolvedRole == .top }) ?? targets.last(where: { $0.isWarmup != true }),
              let w = Double(t.prefillWeight), let r = Int(t.prefillReps) else { return nil }
        return (w, r)
    }

    /// A past session of a lift with history, for lifts outside the golden Push (swap / add targets).
    static func group(_ name: String, _ sessions: [HistorySession]) -> ExerciseHistoryGroup {
        ExerciseHistoryGroup(names: [name], sessions: sessions, best: ExerciseHistoryIndex.bestLogged(in: sessions),
                             latestSessionDate: G.date(11, 12, hour: G.lastSessionHour))
    }
}

final class CoachDecisionApplierTests: XCTestCase {

    typealias G = GoldenScenario
    typealias H = DecisionHarness

    private var allAsPlanned: [String] {
        G.order.map { H.entry($0, "as_planned") }
    }

    // MARK: as_planned and the golden scenario

    /// Prints the golden cases (a)-(d) so a reviewer can read them in the test log (GOLDEN-CASE lines).
    func testPrintGoldenCases() {
        let ctx = H.context()
        let v3 = "{\"summary\":\"Heavy day.\",\"exercises\":[{\"name\":\"\(G.bench)\",\"reason\":\"Go heavier.\",\"sets\":[{\"type\":\"work\",\"weight\":190,\"reps\":8,\"rir\":1,\"rest\":150}]}]}"
        let cases: [(String, CoachPlanReply?)] = [
            ("a all as_planned", H.reply(allAsPlanned)),
            ("b push bench generic", H.reply([H.entry(G.bench, "push", reason: "Progressing bench press strength")] + [G.fly, G.laterals, G.triceps].map { H.entry($0, "as_planned") })),
            ("c ease fly -10", H.reply([G.bench, G.laterals, G.triceps].map { H.entry($0, "as_planned") } + [H.entry(G.fly, "ease", reason: "165x7@1 then 150x5@1, shoulder tweaky.", extra: "\"percent\":-10")])),
            ("d v3 reply", CoachPlanReply.parse(v3))]
        for (name, reply) in cases {
            let plan = CoachDecisionApplier.apply(reply: reply, context: ctx)
            for ex in plan.exercises {
                let sets = (plan.setTargets[ex.id] ?? []).map { "\($0.resolvedRole.label) \($0.prefillWeight)x\($0.prefillReps)@\($0.prefillRir)" }.joined(separator: " | ")
                print("GOLDEN-CASE \(name) :: \(ex.name) :: \(sets) :: [\(plan.review.decision(for: ex.name)?.label ?? "")] \(plan.review.decision(for: ex.name)?.reason ?? "")")
            }
            print("GOLDEN-CASE \(name) :: \(plan.review.checksLine) :: " + plan.review.adjustedChecks.map { "\($0.title): \($0.adjustments.joined(separator: "; "))" }.joined(separator: " || "))
        }
    }

    func testAllAsPlannedIsExactlyTheEngineDraftWithAWarningAndEveryCheckPassing() throws {
        let ctx = H.context()
        let plan = CoachDecisionApplier.apply(reply: H.reply(allAsPlanned), context: ctx)
        XCTAssertEqual(plan.exercises.map(\.name), G.order)
        for name in G.order {
            XCTAssertEqual(H.targets(plan, name), H.draftTargets(ctx, name), "\(name) is the engine's draft")
            XCTAssertEqual(H.decision(plan, name)?.label, "As planned")
        }
        XCTAssertEqual(plan.review.recencyMessage,
                       "You trained chest, shoulders and arms about 5 hours ago, so today's targets are held or lighter.")
        XCTAssertEqual(plan.recencyWarning?.message, "You trained chest, shoulders and arms about 5 hours ago.")
        XCTAssertEqual(plan.review.checks.count, 6)
        XCTAssertTrue(plan.review.checks.allSatisfy(\.passed), "\(plan.review.checks)")
        XCTAssertEqual(plan.review.checksLine, "Checks: 6 of 6 passed")
        XCTAssertFalse(plan.review.engineOnly)
        XCTAssertEqual(plan.review.summary, "Steady day.")
    }

    func testGenericPushOnBenchIsHeldAtTheHeldTargetWithEvidenceAppended() throws {
        let ctx = H.context()
        let entries = [H.entry(G.bench, "push", reason: "Progressing bench press strength")]
            + [G.fly, G.laterals, G.triceps].map { H.entry($0, "as_planned") }
        let plan = CoachDecisionApplier.apply(reply: H.reply(entries), context: ctx)

        XCTAssertEqual(H.targets(plan, G.bench), H.draftTargets(ctx, G.bench), "bench stays at the held/reduced target")
        let decision = try XCTUnwrap(H.decision(plan, G.bench))
        XCTAssertEqual(decision.move, .asPlanned)
        XCTAssertEqual(decision.requested, .push)
        XCTAssertEqual(decision.label, "Coach wanted to push; held: you trained chest about 5 hours ago")
        XCTAssertTrue(decision.reason.hasPrefix("Progressing bench press strength"), decision.reason)
        XCTAssertTrue(decision.reason.contains("Last: "), "the engine's evidence line was appended: \(decision.reason)")
        XCTAssertTrue(decision.reason.contains("→"), decision.reason)

        let noProgress = try XCTUnwrap(plan.review.checks.first { $0.id == PlanChecks.noProgressID })
        XCTAssertTrue(noProgress.adjusted)
        XCTAssertTrue(noProgress.adjustments.contains { $0.contains("Held the coach's push on \(G.bench)") && $0.contains("5 hours ago") }, "\(noProgress)")
        let evidence = try XCTUnwrap(plan.review.checks.first { $0.id == PlanChecks.evidenceID })
        XCTAssertTrue(evidence.adjusted)
        XCTAssertEqual(plan.review.checksLine, "Checks: 4 of 6 passed, 2 adjusted")
    }

    func testEasingThePecFlyTenPercentSnapsDownOnItsLadder() throws {
        let ctx = H.context()
        let entries = [G.bench, G.laterals, G.triceps].map { H.entry($0, "as_planned") }
            + [H.entry(G.fly, "ease", reason: "165x7@1 then 150x5@1 on 11/12, shoulder tweaky.", extra: "\"percent\":-10")]
        let plan = CoachDecisionApplier.apply(reply: H.reply(entries), context: ctx)
        let sets = H.targets(plan, G.fly)
        let ladder = WeightIncrements.learned(name: G.fly, group: ctx.history.group(for: G.fly))
        XCTAssertEqual(sets.map(\.prefillWeight), ["145", "145"], "165 less 10% is 148.5, down to the rung below")
        XCTAssertEqual(sets.map(\.prefillReps), ["6", "6"])
        for set in sets { XCTAssertTrue(ladder.isOnLadder(Double(set.prefillWeight) ?? 0)) }
        let decision = try XCTUnwrap(H.decision(plan, G.fly))
        XCTAssertEqual(decision.label, "Eased by coach \u{2212}10%")
        XCTAssertEqual(decision.draftTop, "165x7@2")
        XCTAssertEqual(decision.finalTop, "145x6@2", "reps follow the rep-jump rule at a weight 5 lb under the 150x5@1 of last time")
        XCTAssertTrue(plan.review.checks.allSatisfy(\.passed), "\(plan.review.checks)")
    }

    func testAnOldV3StyleReplyWithFullSetsIsToleratedAndTheNumbersAreIgnored() throws {
        let ctx = H.context()
        let v3 = """
        {"summary":"Heavy day.","coaching_notes":"x","exercises":[
         {"name":"\(G.bench)","muscle_group":"Chest","superset":null,"cue":null,"reason":"Last 185x5@1, so go heavier.",
          "sets":[{"type":"warmup","weight":95,"reps":8,"rir":4,"rest":60},{"type":"work","weight":190,"reps":8,"rir":1,"rest":150}]},
         {"name":"\(G.fly)","muscle_group":"Chest","reason":"165x7 last time.","sets":[{"type":"work","weight":170,"reps":10,"rir":1,"rest":90}]}]}
        """
        let plan = CoachDecisionApplier.apply(reply: CoachPlanReply.parse(v3), context: ctx)
        XCTAssertEqual(H.targets(plan, G.bench), H.draftTargets(ctx, G.bench), "numbers for a lift with history are ignored")
        XCTAssertEqual(H.targets(plan, G.fly), H.draftTargets(ctx, G.fly))
        XCTAssertEqual(H.decision(plan, G.bench)?.label, "As planned")
        XCTAssertEqual(plan.exercises.count, 4, "lifts the reply left out stay as planned")
    }

    func testWhenTheAIFailsTheEnginePlanIsShownAndLabelled() {
        let ctx = H.context()
        let plan = CoachDecisionApplier.apply(reply: nil, context: ctx)
        XCTAssertTrue(plan.review.engineOnly)
        XCTAssertEqual(plan.review.summary, "The coach was unavailable, so this plan comes straight from your log.")
        for name in G.order { XCTAssertEqual(H.targets(plan, name), H.draftTargets(ctx, name)) }
        XCTAssertFalse(plan.review.summary.lowercased().contains("sound"))
        XCTAssertEqual(plan.review.decisions.count, 4)
        XCTAssertNotNil(plan.review.recencyMessage)
    }

    func testUnknownDecisionAndOmittedAndDroppedLifts() throws {
        let ctx = H.context()
        let entries = [H.entry(G.laterals, "banana"), H.entry(G.bench)]
        let dropped = ",\"dropped\":[{\"name\":\"\(G.fly)\",\"reason\":\"Pec fly 165x7 twice this week, chest has 5 hard sets already.\"}]"
        let plan = CoachDecisionApplier.apply(reply: H.reply(entries, extra: dropped), context: ctx)
        XCTAssertEqual(H.decision(plan, G.laterals)?.move, .asPlanned, "unknown decision")
        XCTAssertFalse(plan.exercises.contains { $0.name == G.fly }, "dropped")
        XCTAssertTrue(plan.exercises.contains { $0.name == G.triceps }, "omitted and not dropped: stays as planned")
        // The omitted triceps lift keeps its place after its draft neighbour (laterals).
        XCTAssertEqual(plan.exercises.map(\.name), [G.laterals, G.bench, G.triceps].sorted { a, b in
            plan.exercises.map(\.name).firstIndex(of: a) ?? 0 < plan.exercises.map(\.name).firstIndex(of: b) ?? 0 })
        XCTAssertTrue(plan.review.decisions.contains { $0.name == G.fly && $0.move == .drop })
        XCTAssertEqual(plan.exercises.map(\.orderIndex), Array(plan.exercises.indices))
    }

    // MARK: push

    func testPushIsAppliedWhenRestedAndTheEngineAllowsIt() throws {
        let ctx = H.context(rested: true)
        let draftTop = try XCTUnwrap(ctx.draft.first { $0.name == G.laterals }?.result.topSet)
        // Laterals: 25x9@2 twice last time, nothing forbids more.
        let entries = [G.bench, G.fly, G.triceps].map { H.entry($0, "as_planned") }
            + [H.entry(G.laterals, "push", reason: "25x9@2 both sets on 11/12, ready for 10.")]
        let plan = CoachDecisionApplier.apply(reply: H.reply(entries), context: ctx)
        let decision = try XCTUnwrap(H.decision(plan, G.laterals))
        XCTAssertEqual(decision.move, .push, decision.label)
        XCTAssertEqual(decision.label, "Pushed by coach")
        let top = try XCTUnwrap(H.top(H.targets(plan, G.laterals)))
        XCTAssertTrue(top.weight > draftTop.weight || (top.weight == draftTop.weight && top.reps > draftTop.reps),
                      "one step past the draft: \(top) vs \(draftTop.weight)x\(draftTop.reps)")
        XCTAssertTrue(plan.review.checks.allSatisfy(\.passed), "\(plan.review.checks)")
    }

    func testPushIsHeldWhenMusclesWereTrainedHoursAgoOrFuelIsLow() throws {
        // Same-day: held for the recent session.
        let ctx = H.context()
        let plan = CoachDecisionApplier.apply(reply: H.reply([H.entry(G.laterals, "push")]), context: ctx)
        XCTAssertEqual(H.decision(plan, G.laterals)?.held, "you trained shoulders about 5 hours ago")

        // Next morning, rested, but a deep deficit: held for fuel.
        var fuelCtx = H.context(rested: true)
        fuelCtx.coach.fuelHold = G.deficitAssessment
        fuelCtx.draft = PlanDraftBuilder.build(lastSessionExercises: G.lastSessionExercises(), history: fuelCtx.history, energy: 6,
                                               feedback: nil, coach: fuelCtx.coach, timeMinutes: nil)
        let fueled = CoachDecisionApplier.apply(reply: H.reply([H.entry(G.laterals, "push")]), context: fuelCtx)
        let held = try XCTUnwrap(H.decision(fueled, G.laterals)?.held)
        XCTAssertTrue(held.contains("fuel"), held)
        XCTAssertEqual(H.targets(fueled, G.laterals), H.draftTargets(fuelCtx, G.laterals))
    }

    func testPushIsHeldAfterALayoffAndAfterAMiss() throws {
        let layoff = H.context(rested: true, now: G.date(12, 2, hour: 9))
        let plan = CoachDecisionApplier.apply(reply: H.reply([H.entry(G.bench, "push")]), context: layoff)
        XCTAssertEqual(H.decision(plan, G.bench)?.held, "last done 20 days ago")

        // The last call on bench missed.
        var doc = CoachReviewDocument()
        doc.decisions = [CoachDecision(
            name: G.bench, muscle: "Chest", target: PrescribedSet(role: .top, weight: 185, reps: 6, rir: 1, restSeconds: 120), sets: nil,
            reason: "r", context: "c", source: "engine",
            outcome: DecisionOutcome(hit: false, actualTop: "185x3@0", rir: 0, shortBy: 3, result: .missed))]
        var workout = Workout.create(userId: UUID(), workoutType: "Push", energyLevel: 6, timeAvailableMinutes: 45, date: G.date(11, 12))
        workout.aiProgressionNote = doc.encoded()
        let missed = H.context(rested: true, memory: CoachMemoryIndex(workouts: [workout]))
        let after = CoachDecisionApplier.apply(reply: H.reply([H.entry(G.bench, "push")]), context: missed)
        XCTAssertEqual(H.decision(after, G.bench)?.held, "the last session missed this lift")
    }

    func testPushIsHeldWhenTheRepJumpRuleWouldCapIt() throws {
        // Rested bench: last 185x5@1 means at most 185x6; the draft already asks for it, so one more rep is refused.
        let ctx = H.context(rested: true)
        let draftTop = try XCTUnwrap(ctx.draft.first { $0.name == G.bench }?.result.topSet)
        XCTAssertEqual(draftTop.weight, 185)
        let plan = CoachDecisionApplier.apply(reply: H.reply([H.entry(G.bench, "push")]), context: ctx)
        let decision = try XCTUnwrap(H.decision(plan, G.bench))
        XCTAssertEqual(decision.move, .asPlanned, decision.label)
        XCTAssertTrue(decision.held?.contains("rep-jump") == true || decision.held?.contains("already the next step") == true,
                      decision.held ?? "none")
        XCTAssertEqual(H.targets(plan, G.bench), H.draftTargets(ctx, G.bench))
    }

    func testPushIsHeldWhenItWouldBreakTheOneRepMaxCap() throws {
        // A lift whose best e1RM is far below what one more step needs.
        let name = "Cable Crossover"
        let sessions = [HistorySession(date: G.date(11, 6), sets: [HistorySet(40, 12, rir: 3), HistorySet(40, 12, rir: 3)]),
                        HistorySession(date: G.date(11, 2), sets: [HistorySet(35, 12, rir: 3), HistorySet(35, 12, rir: 3)]),
                        HistorySession(date: G.date(10, 28), sets: [HistorySet(30, 12, rir: 3), HistorySet(30, 12, rir: 3)])]
        let crossover = H.group(name, sessions)
        var ctx = H.context(rested: true, extraHistory: [crossover],
                            lastExercises: G.lastSessionExercises() + [Exercise.create(
                                workoutId: UUID(), name: name, muscleGroup: "Chest", orderIndex: 4, targetSets: 2,
                                targetReps: nil, targetRir: nil, restSeconds: 60, coachNote: nil)])
        XCTAssertNotNil(ctx.draft.first { $0.name == name })
        // Pretend the recent best is much lower than the draft.
        ctx.history = ExerciseHistoryIndex(groups: ctx.history.groups.map { g in
            guard g.names == [name] else { return g }
            var copy = g
            copy.sessions = [HistorySession(date: G.date(11, 6), sets: [HistorySet(20, 12, rir: 3), HistorySet(20, 12, rir: 3)])]
            return copy
        })
        let plan = CoachDecisionApplier.apply(reply: H.reply([H.entry(name, "push")]), context: ctx)
        // Either way the lift is not above what its history supports.
        let top = try XCTUnwrap(H.top(H.targets(plan, name)))
        XCTAssertLessThanOrEqual(top.weight, 40)
    }

    // MARK: goal_step

    private func benchGoal(step weight: Double = 190, reps: Int = 5) -> [GoalPlanItem] {
        let goal = CoachGoal(exerciseName: G.bench, targetWeight: 205, targetReps: 3, deadline: G.date(12, 20),
                             steps: [CoachGoalStep(text: "190x5 clean", weight: weight, reps: reps)])
        return [GoalPlanItem(goal: goal, assessment: nil, step: goal.steps.first, stepIsToday: true)]
    }

    func testGoalStepIsAppliedWhenAPushWouldBeAllowed() throws {
        let ctx = H.context(rested: true, goals: benchGoal())
        let plan = CoachDecisionApplier.apply(
            reply: H.reply([H.entry(G.bench, "goal_step", reason: "Goal 205x3, today's step is 190x5 after 185x5@1 on 11/12.")]), context: ctx)
        let decision = try XCTUnwrap(H.decision(plan, G.bench))
        XCTAssertEqual(decision.move, .goalStep, decision.label)
        XCTAssertEqual(decision.label, "Goal step")
        let top = try XCTUnwrap(H.top(H.targets(plan, G.bench)))
        XCTAssertEqual(top.weight, 190)
        XCTAssertEqual(top.reps, 5)
        XCTAssertTrue(plan.review.checks.allSatisfy(\.passed), "\(plan.review.checks)")
    }

    func testGoalStepIsHeldSameDayAndWithoutAStepAndAboveTheRails() throws {
        let same = H.context(goals: benchGoal())
        let held = CoachDecisionApplier.apply(reply: H.reply([H.entry(G.bench, "goal_step")]), context: same)
        XCTAssertEqual(H.decision(held, G.bench)?.label, "Coach wanted to take the goal step; held: you trained chest about 5 hours ago")
        XCTAssertEqual(H.targets(held, G.bench), H.draftTargets(same, G.bench))

        let none = H.context(rested: true)
        let noStep = CoachDecisionApplier.apply(reply: H.reply([H.entry(G.bench, "goal_step")]), context: none)
        XCTAssertEqual(H.decision(noStep, G.bench)?.held, "no goal step is due for this lift today")

        // A step 25 lb above the last top set is far past +10%.
        let wild = H.context(rested: true, goals: benchGoal(step: 215, reps: 3))
        let refused = CoachDecisionApplier.apply(reply: H.reply([H.entry(G.bench, "goal_step")]), context: wild)
        XCTAssertNotNil(H.decision(refused, G.bench)?.held)
        XCTAssertEqual(H.targets(refused, G.bench), H.draftTargets(wild, G.bench))
    }

    // MARK: ease

    func testEaseSnapsDownOnTheLiftsOwnRungs() throws {
        // 25 lb laterals on a 2.5 lb ladder: 25 less 5% is 23.75, down to 22.5.
        let ctx = H.context(rested: true)
        let plan = CoachDecisionApplier.apply(
            reply: H.reply([H.entry(G.laterals, "ease", reason: "25x9@2 on 11/12, elbow note.", extra: "\"percent\":-5")]), context: ctx)
        let top = try XCTUnwrap(H.top(H.targets(plan, G.laterals)))
        XCTAssertEqual(top.weight, 22.5)
        XCTAssertEqual(H.decision(plan, G.laterals)?.label, "Eased by coach \u{2212}5%")
    }

    func testEaseFallsBackToFewerRepsWhenTheNextRungDownIsTooFar() throws {
        // A machine that moves in tens: 110 less 2.5% is 107.25, and the rung below is 100 (a 9% cut).
        let name = "Seated Row Machine"
        let sessions = [HistorySession(date: G.date(11, 6), sets: [HistorySet(110, 10, rir: 2), HistorySet(110, 10, rir: 2)]),
                        HistorySession(date: G.date(11, 2), sets: [HistorySet(100, 10, rir: 2), HistorySet(100, 10, rir: 2)]),
                        HistorySession(date: G.date(10, 28), sets: [HistorySet(120, 8, rir: 2), HistorySet(120, 8, rir: 2)])]
        let last = Exercise.create(workoutId: UUID(), name: name, muscleGroup: "Back", orderIndex: 0, targetSets: 2, targetReps: nil,
                                   targetRir: nil, restSeconds: nil, coachNote: nil)
        var ctx = H.context(rested: true, extraHistory: [H.group(name, sessions)], lastExercises: [last])
        ctx.draft = PlanDraftBuilder.build(lastSessionExercises: [last], history: ctx.history, energy: 6, feedback: nil,
                                           coach: ctx.coach, timeMinutes: nil)
        let draftTop = try XCTUnwrap(ctx.draft.first?.result.topSet)
        let plan = CoachDecisionApplier.apply(
            reply: H.reply([H.entry(name, "ease", reason: "110x10@2 on 11/6, light fatigue.", extra: "\"percent\":-2.5")]), context: ctx)
        let top = try XCTUnwrap(H.top(H.targets(plan, name)))
        XCTAssertEqual(top.weight, draftTop.weight, "the weight stays on the rung it has")
        XCTAssertEqual(top.reps, draftTop.reps - 1, "one rep fewer instead")
        XCTAssertEqual(H.decision(plan, name)?.label, "Eased by coach \u{2212}2.5%")
    }

    func testEasePercentIsClampedAndDefaultsToFive() throws {
        let ctx = H.context(rested: true)
        let big = CoachDecisionApplier.apply(
            reply: H.reply([H.entry(G.fly, "ease", extra: "\"percent\":-40")]), context: ctx)
        XCTAssertEqual(H.decision(big, G.fly)?.label, "Eased by coach \u{2212}15%")
        let none = CoachDecisionApplier.apply(reply: H.reply([H.entry(G.fly, "ease")]), context: ctx)
        XCTAssertEqual(H.decision(none, G.fly)?.percent, -5)
    }

    func testEaseNeverAddsSets() throws {
        let sessions = [HistorySession(date: G.date(11, 2), sets: [HistorySet(100, 3, rir: 1), HistorySet(100, 3, rir: 1)])]
        let name = "Cable Row"
        let group = H.group(name, sessions)
        let last = Exercise.create(workoutId: UUID(), name: name, muscleGroup: "Back", orderIndex: 0, targetSets: 2, targetReps: nil,
                                   targetRir: nil, restSeconds: nil, coachNote: nil)
        var ctx = H.context(rested: true, extraHistory: [group], lastExercises: [last])
        ctx.draft = PlanDraftBuilder.build(lastSessionExercises: [last], history: ctx.history, energy: 6, feedback: nil,
                                           coach: ctx.coach, timeMinutes: nil)
        let draftWorking = ctx.draft.first?.result.workingSets.count ?? 0
        XCTAssertGreaterThanOrEqual(draftWorking, 2)
        let plan = CoachDecisionApplier.apply(reply: H.reply([H.entry(name, "ease", extra: "\"percent\":-2.5")]), context: ctx)
        let decision = try XCTUnwrap(H.decision(plan, name))
        XCTAssertNotNil(decision.finalTop)
        XCTAssertLessThanOrEqual(H.targets(plan, name).filter { $0.isWarmup != true }.count, draftWorking)
    }

    // MARK: swap, add

    private var crossoverHistory: ExerciseHistoryGroup {
        H.group("Cable Crossover", [HistorySession(date: G.date(11, 6), sets: [HistorySet(30, 12, rir: 2), HistorySet(30, 12, rir: 2)]),
                                     HistorySession(date: G.date(11, 2), sets: [HistorySet(25, 12, rir: 2), HistorySet(25, 12, rir: 2)]),
                                     HistorySession(date: G.date(10, 28), sets: [HistorySet(25, 11, rir: 2), HistorySet(25, 11, rir: 2)])])
    }

    func testSwapToALiftWithHistoryUsesTheEnginesNumbersNotTheAIs() throws {
        let ctx = H.context(rested: true, extraHistory: [crossoverHistory])
        let entries = [H.entry(G.bench, "as_planned"),
                       H.entry("Cable Crossover", "swap", reason: "Pec fly 165x7@1 hurts the shoulder, crossover 30x12 on 11/6.",
                               extra: "\"replaces\":\"\(G.fly)\",\"starting_sets\":[{\"type\":\"work\",\"weight\":90,\"reps\":12,\"rir\":2,\"rest\":60}]"),
                       H.entry(G.laterals, "as_planned"), H.entry(G.triceps, "as_planned")]
        let plan = CoachDecisionApplier.apply(reply: H.reply(entries), context: ctx)
        XCTAssertFalse(plan.exercises.contains { $0.name == G.fly })
        let decision = try XCTUnwrap(H.decision(plan, "Cable Crossover"))
        XCTAssertEqual(decision.move, .swap)
        XCTAssertEqual(decision.label, "Swapped in for \(G.fly)")
        let top = try XCTUnwrap(H.top(H.targets(plan, "Cable Crossover")))
        XCTAssertLessThanOrEqual(top.weight, 35, "the AI's 90 lb is ignored: the lift has history")
        XCTAssertEqual(plan.exercises.map(\.name), [G.bench, "Cable Crossover", G.laterals, G.triceps])
    }

    func testAddWithoutHistoryUsesValidStartingSetsAndClampsTheSmallStuff() throws {
        let ctx = H.context(rested: true)
        let sets = "[{\"type\":\"work\",\"weight\":50,\"reps\":18,\"rir\":0,\"rest\":75},{\"type\":\"work\",\"weight\":50,\"reps\":10,\"rir\":1},"
            + "{\"type\":\"work\",\"weight\":45,\"reps\":12,\"rir\":2},{\"type\":\"work\",\"weight\":45,\"reps\":12,\"rir\":2}]"
        let entries = G.order.map { H.entry($0, "as_planned") }
            + [H.entry("Incline Dumbbell Press", "add", reason: "No upper-chest work this week, 4 hard chest sets so far.", extra: "\"starting_sets\":\(sets)")]
        let plan = CoachDecisionApplier.apply(reply: H.reply(entries), context: ctx)
        let added = H.targets(plan, "Incline Dumbbell Press")
        let work = added.filter { $0.isWarmup != true }
        XCTAssertEqual(work.count, 3, "at most 3 work sets")
        XCTAssertTrue(work.allSatisfy { (Int($0.prefillReps) ?? 0) >= 5 && (Int($0.prefillReps) ?? 99) <= 15 }, "\(work)")
        XCTAssertTrue(work.allSatisfy { (Int($0.prefillRir) ?? 0) >= 2 }, "RIR at least 2: \(work)")
        XCTAssertEqual(H.decision(plan, "Incline Dumbbell Press")?.label, "Added")
        XCTAssertEqual(work.first?.prefillWeight, "50")
    }

    func testInvalidStartingSetsFallBackToTheAppsDefault() throws {
        let ctx = H.context(rested: true)
        // Far above the athlete's similar chest lifts, and no weight at all.
        for bad in ["[{\"type\":\"work\",\"weight\":400,\"reps\":8,\"rir\":2}]", "[{\"type\":\"work\",\"reps\":8,\"rir\":2}]", "[]"] {
            let entries = G.order.map { H.entry($0, "as_planned") }
                + [H.entry("Dumbbell Bench Press", "add", reason: "Chest has 5 hard sets, add a press.", extra: "\"starting_sets\":\(bad)")]
            let plan = CoachDecisionApplier.apply(reply: H.reply(entries), context: ctx)
            let work = H.targets(plan, "Dumbbell Bench Press").filter { $0.isWarmup != true }
            XCTAssertEqual(work.count, 3, "main lift default is 3 sets: \(bad)")
            XCTAssertTrue(work.allSatisfy { $0.prefillReps == "10" && $0.prefillRir == "2" }, "\(work)")
            XCTAssertTrue(work.allSatisfy { (Double($0.prefillWeight) ?? 0) < 400 }, "\(bad): \(work)")
            XCTAssertTrue(plan.adjustments.contains { $0.contains("default was used") }, "\(plan.adjustments)")
        }
    }

    func testANameNotInTheDraftIsAnAddEvenWhenTheCoachCalledItSomethingElse() throws {
        let ctx = H.context(rested: true)
        let plan = CoachDecisionApplier.apply(
            reply: H.reply(G.order.map { H.entry($0, "as_planned") } + [H.entry("Face Pull", "push", reason: "Rear delts 0 sets this week.")]),
            context: ctx)
        XCTAssertEqual(H.decision(plan, "Face Pull")?.move, .add)
    }

    func testSetsRequestsAreClampedToTheEnginesLimits() throws {
        let ctx = H.context(rested: true)
        let big = CoachDecisionApplier.apply(reply: H.reply([H.entry(G.laterals, "as_planned", extra: "\"sets\":9")]), context: ctx)
        XCTAssertEqual(H.targets(big, G.laterals).count, 3, "isolation: at most 3")
        let bench = CoachDecisionApplier.apply(reply: H.reply([H.entry(G.bench, "as_planned", extra: "\"sets\":6")]), context: ctx)
        XCTAssertEqual(H.targets(bench, G.bench).filter { $0.isWarmup != true }.count,
                       H.draftTargets(ctx, G.bench).filter { $0.isWarmup != true }.count, "no heavy sets are added to a main lift")
        let small = CoachDecisionApplier.apply(reply: H.reply([H.entry(G.fly, "as_planned", extra: "\"sets\":1")]), context: ctx)
        XCTAssertEqual(H.targets(small, G.fly).count, 2, "never below 2 working sets")
    }

    func testSupersetLabelsBecomeGroups() throws {
        let ctx = H.context(rested: true)
        let entries = [H.entry(G.bench, "as_planned"), H.entry(G.fly, "as_planned", extra: "\"superset\":\"A\""),
                       H.entry(G.laterals, "as_planned"), H.entry(G.triceps, "as_planned", extra: "\"superset\":\"A\"")]
        let plan = CoachDecisionApplier.apply(reply: H.reply(entries), context: ctx)
        let fly = try XCTUnwrap(plan.exercises.first { $0.name == G.fly })
        let triceps = try XCTUnwrap(plan.exercises.first { $0.name == G.triceps })
        XCTAssertNotNil(fly.supersetGroupId)
        XCTAssertEqual(fly.supersetGroupId, triceps.supersetGroupId)
        XCTAssertEqual(plan.exercises.map(\.orderIndex), Array(plan.exercises.indices))
        let adjacent = abs((plan.exercises.firstIndex { $0.id == fly.id } ?? 0) - (plan.exercises.firstIndex { $0.id == triceps.id } ?? 9))
        XCTAssertEqual(adjacent, 1)
    }

    func testTheExerciseNoteCarriesTheTargetWeightAndTheCue() throws {
        let ctx = H.context(rested: true)
        let plan = CoachDecisionApplier.apply(
            reply: H.reply([H.entry(G.bench, "as_planned", extra: "\"cue\":\"Elbows at 45 degrees.\"")]), context: ctx)
        let bench = try XCTUnwrap(plan.exercises.first { $0.name == G.bench })
        XCTAssertEqual(bench.coachNoteParts.message, "Cue: Elbows at 45 degrees.")
        XCTAssertNotNil(bench.coachNoteParts.weight)
        let evidence = try XCTUnwrap(plan.evidence[bench.id])
        XCTAssertEqual(evidence.decisionLabel, "As planned")
        XCTAssertEqual(evidence.source, .engine)
        XCTAssertFalse(evidence.reason.isEmpty)
    }

    func testHeavyCompoundsAreMovedAheadOfIsolation() throws {
        let ctx = H.context(rested: true)
        let plan = CoachDecisionApplier.apply(
            reply: H.reply([H.entry(G.laterals, "as_planned"), H.entry(G.bench, "as_planned"), H.entry(G.fly, "as_planned")]), context: ctx)
        XCTAssertEqual(plan.exercises.first?.name, G.bench)
        XCTAssertTrue(plan.adjustments.contains { $0.contains("heavy compounds go first") }, "\(plan.adjustments)")
    }

    func testWarmupsStayOnTheFirstHeavyCompoundOnly() throws {
        let ctx = H.context(rested: true)
        let plan = CoachDecisionApplier.apply(reply: H.reply(allAsPlanned), context: ctx)
        for ex in plan.exercises {
            let warm = (plan.setTargets[ex.id] ?? []).filter { $0.isWarmup == true }.count
            XCTAssertEqual(warm > 0, ex.name == G.bench, "\(ex.name): \(warm)")
        }
    }
}

// MARK: - Plan checks

final class PlanChecksTests: XCTestCase {

    typealias G = GoldenScenario
    typealias H = DecisionHarness

    private func lift(_ ctx: PlanDecisionContext, _ name: String, targets: [SetTarget]? = nil, reason: String = "Last 185x5@1 on 11/12.") -> PlanLift {
        let draft = ctx.draft.first { $0.name == name }
        let ex = Exercise.create(workoutId: ctx.workoutId, name: name, muscleGroup: G.muscleGroups[name] ?? "", orderIndex: 0,
                                 targetSets: 2, targetReps: nil, targetRir: nil, restSeconds: 90, coachNote: nil)
        return PlanLift(exercise: ex, targets: targets ?? draft?.result.sets.map(\.setTarget) ?? [], draft: draft,
                        decision: LiftDecision(name: name, move: .asPlanned, reason: reason), cue: nil, superset: nil,
                        evidenceLine: draft?.result.evidenceLine ?? "", rationale: "")
    }

    private func run(_ lifts: inout [PlanLift], _ ctx: PlanDecisionContext) -> [PlanCheck] {
        var adjustments: [String] = []
        return PlanChecks.run(&lifts, context: ctx, adjustments: &adjustments)
    }

    func testAPlanThatIsAlreadyFineFailsNothing() {
        let ctx = H.context()
        var lifts = G.order.map { lift(ctx, $0) }
        let checks = run(&lifts, ctx)
        XCTAssertEqual(checks.map(\.id), ["ladder", "noProgress", "repJump", "volume", "time", "evidence"])
        XCTAssertTrue(checks.allSatisfy(\.passed), "\(checks)")
    }

    func testAWeightTheLiftDoesNotHaveIsRepairedOntoItsLadder() throws {
        let ctx = H.context()
        let triceps = SetTarget(weight: "52.5", reps: "12", rir: "2", role: .straight, restSeconds: 90)
        var lifts = [lift(ctx, G.triceps, targets: [triceps, triceps])]
        let checks = run(&lifts, ctx)
        let ladder = try XCTUnwrap(checks.first { $0.id == PlanChecks.ladderID })
        XCTAssertTrue(ladder.adjusted)
        XCTAssertEqual(lifts[0].targets.map(\.prefillWeight), ["50", "50"], "52.5 is not on the 50 / 57.5 stack")
        XCTAssertTrue(ladder.adjustments[0].contains("52.5") && ladder.adjustments[0].contains("50"), "\(ladder)")
    }

    func testAProgressionTheRulesForbidIsRepairedBackToTheDraft() throws {
        let ctx = H.context()
        let bench = G.bench
        let heavier = SetTarget(weight: "190", reps: "6", rir: "1", role: .top, restSeconds: 120)
        var lifts = [lift(ctx, bench, targets: [heavier])]
        lifts[0].decision.move = .push
        let checks = run(&lifts, ctx)
        let check = try XCTUnwrap(checks.first { $0.id == PlanChecks.noProgressID })
        XCTAssertTrue(check.adjusted)
        XCTAssertEqual(lifts[0].targets, H.draftTargets(ctx, bench))
        XCTAssertEqual(lifts[0].decision.move, .asPlanned)
        XCTAssertEqual(lifts[0].decision.requested, .push)
        XCTAssertTrue(lifts[0].decision.label.hasPrefix("Coach wanted to push; held: "), lifts[0].decision.label)
    }

    func testARepJumpAtAWeightJustDoneIsCapped() throws {
        let ctx = H.context(rested: true)
        let jump = SetTarget(weight: "50", reps: "16", rir: "2", role: .straight, restSeconds: 90)
        var lifts = [lift(ctx, G.triceps, targets: [jump])]
        let checks = run(&lifts, ctx)
        let rep = try XCTUnwrap(checks.first { $0.id == PlanChecks.repJumpID })
        XCTAssertTrue(rep.adjusted)
        XCTAssertLessThan(Int(lifts[0].targets[0].prefillReps) ?? 99, 16)
    }

    func testMuscleVolumeOverTheCapIsTrimmedAndReported() throws {
        let ctx = H.context(rested: true)
        let names = ["Cable Fly", "Pec Deck Fly", "Incline Fly", "Decline Fly", "Machine Fly", "Dumbbell Fly"]
        var lifts = names.map { name -> PlanLift in
            let iso = SetTarget(weight: "30", reps: "12", rir: "2", role: .straight, restSeconds: 60)
            var l = lift(ctx, name, targets: [iso, iso, iso])
            l.exercise.muscleGroup = "Chest"
            return l
        }
        let checks = run(&lifts, ctx)
        let volume = try XCTUnwrap(checks.first { $0.id == PlanChecks.volumeID })
        XCTAssertTrue(volume.adjusted)
        let total = lifts.reduce(0) { $0 + $1.workingCount }
        XCTAssertLessThanOrEqual(total, PlanGuardrails.maxHardSetsPerMuscle)
    }

    func testAPlanOverTheTimeLosesItsLowestPriorityIsolationWork() throws {
        var ctx = H.context(rested: true, minutes: 15)
        ctx.timeMinutes = 15
        var lifts = G.order.map { lift(ctx, $0) }
        let before = PlanChecks.estimatedMinutes(lifts)
        XCTAssertGreaterThan(before, 15 * 1.1)
        let checks = run(&lifts, ctx)
        let time = try XCTUnwrap(checks.first { $0.id == PlanChecks.timeID })
        XCTAssertTrue(time.adjusted)
        XCTAssertLessThan(PlanChecks.estimatedMinutes(lifts), before)
        XCTAssertGreaterThanOrEqual(lifts.count, 2, "the first two lifts always stay")
        XCTAssertEqual(lifts.first?.exercise.name, G.bench)
        XCTAssertTrue(time.adjustments.contains { $0.contains("15 minutes") }, "\(time)")
    }

    func testReasonsWithoutEvidenceGetTheEnginesLineAndGoodOnesAreLeftAlone() throws {
        let ctx = H.context(rested: true)
        var lifts = [lift(ctx, G.bench, reason: "Driving hypertrophy with progressive loading"),
                     lift(ctx, G.fly, reason: "165x7@1 on 11/12, repeat it."),
                     lift(ctx, G.laterals, reason: ""),
                     lift(ctx, G.triceps, reason: "Fuel is low, so no jump.")]
        let checks = run(&lifts, ctx)
        let evidence = try XCTUnwrap(checks.first { $0.id == PlanChecks.evidenceID })
        XCTAssertTrue(lifts[0].decision.reason.hasPrefix("Driving hypertrophy with progressive loading."), lifts[0].decision.reason)
        XCTAssertTrue(lifts[0].decision.reason.contains("Last: "), lifts[0].decision.reason)
        XCTAssertEqual(lifts[1].decision.reason, "165x7@1 on 11/12, repeat it.")
        XCTAssertTrue(lifts[2].decision.reason.hasPrefix("Last: "), "no reason at all: the engine line is the reason")
        XCTAssertEqual(lifts[3].decision.reason, "Fuel is low, so no jump.", "'fuel' is evidence")
        XCTAssertEqual(evidence.adjustments.count, 1, "only the generic reason counts as adjusted: \(evidence)")
    }

    func testWhatCountsAsNamingEvidence() {
        for good in ["185x5@1 on 11/12", "Held after the RIR 0 miss", "Pain in the left elbow", "New PR last week", "Eating under target: fuel low",
                     "Goal step today", "Trained 5 hours ago", "Missed the top set"] {
            XCTAssertTrue(PlanChecks.namesEvidence(good), good)
        }
        for generic in ["Progressing bench press strength", "Driving hypertrophy", "Good for chest development", "Keep building"] {
            XCTAssertFalse(PlanChecks.namesEvidence(generic), generic)
        }
    }

    func testTheCheckSummaryLine() {
        let review = CoachPlanReview(checks: [PlanCheck(id: "a", title: "A"), PlanCheck(id: "b", title: "B", adjustments: ["x"]),
                                              PlanCheck(id: "c", title: "C")])
        XCTAssertEqual(review.checksLine, "Checks: 2 of 3 passed, 1 adjusted")
        XCTAssertEqual(CoachPlanReview(checks: [PlanCheck(id: "a", title: "A")]).checksLine, "Checks: 1 of 1 passed")
        XCTAssertEqual(CoachPlanReview().checksLine, "")
    }
}

// MARK: - Reply parsing, labels, stored documents

final class CoachReplyAndLabelTests: XCTestCase {

    func testParserToleratesFencesExtraKeysAndMissingOptionals() throws {
        let text = """
        ```json
        {"summary":"Fine.","mood":"great","exercises":[
          {"name":"Bench","decision":"PUSH","reason":"185x5","percent":"-7.5","sets":"3","debug":true},
          {"name":"Row"},
          {"decision":"add"},
          {"name":"Face Pull","decision":"add","starting_sets":[{"type":"work","weight":"40","reps":"15","rir":"3"}]}],
         "dropped":[{"name":"Dips","reason":"shoulder"},{"reason":"no name"}]}
        ```
        """
        let reply = try XCTUnwrap(CoachPlanReply.parse(text))
        XCTAssertEqual(reply.summary, "Fine.")
        XCTAssertEqual(reply.entries.map(\.name), ["Bench", "Row", "Face Pull"], "an entry without a name is skipped")
        XCTAssertEqual(reply.entries[0].move, .push)
        XCTAssertEqual(reply.entries[0].percent, -7.5)
        XCTAssertEqual(reply.entries[0].sets, 3)
        XCTAssertNil(reply.entries[1].move)
        XCTAssertNil(reply.entries[1].reason)
        XCTAssertEqual(reply.entries[2].startingSets.first?.weight, 40)
        XCTAssertEqual(reply.entries[2].startingSets.first?.reps, 15)
        XCTAssertEqual(reply.dropped, [CoachReplyDrop(name: "Dips", reason: "shoulder")])
        XCTAssertNil(CoachPlanReply.parse("Here is a plan: bench 3x8"))
        XCTAssertNil(CoachPlanReply.parse(#"{"summary":"x"}"#))
        XCTAssertEqual(CoachPlanReply.parse(#"{"exercises":[]}"#)?.entries.count, 0)
    }

    func testMoveWordsAreForgiving() {
        XCTAssertEqual(CoachMove.parse("as_planned"), .asPlanned)
        XCTAssertEqual(CoachMove.parse("As Planned"), .asPlanned)
        XCTAssertEqual(CoachMove.parse("goal-step"), .goalStep)
        XCTAssertEqual(CoachMove.parse("Goal_Step"), .goalStep)
        XCTAssertNil(CoachMove.parse("banana"))
        XCTAssertNil(CoachMove.parse(nil))
    }

    func testEveryDecisionHasItsLabel() {
        func label(_ move: CoachMove, percent: Double? = nil, replaces: String? = nil, requested: CoachMove? = nil, held: String? = nil) -> String {
            LiftDecision(name: "X", move: move, requested: requested, percent: percent, replaces: replaces, held: held,
                         reason: "").label
        }
        XCTAssertEqual(label(.asPlanned), "As planned")
        XCTAssertEqual(label(.push), "Pushed by coach")
        XCTAssertEqual(label(.ease, percent: -5), "Eased by coach \u{2212}5%")
        XCTAssertEqual(label(.ease, percent: -7.5), "Eased by coach \u{2212}7.5%")
        XCTAssertEqual(label(.goalStep), "Goal step")
        XCTAssertEqual(label(.swap, replaces: "Pec Fly"), "Swapped in for Pec Fly")
        XCTAssertEqual(label(.add), "Added")
        XCTAssertEqual(label(.asPlanned, requested: .push, held: "you trained chest about 5 hours ago"),
                       "Coach wanted to push; held: you trained chest about 5 hours ago")
    }

    func testPlanReviewsStoredByOlderBuildsStillDecode() throws {
        let old = #"{"verdict":"sound","summary":"Looks right.","changes":[{"type":"drop","exercise":"x","detail":"d","reason":"r","applied":true}],"safeguards":["s"]}"#
        let review = try JSONDecoder().decode(CoachPlanReview.self, from: Data(old.utf8))
        XCTAssertEqual(review.summary, "Looks right.")
        XCTAssertTrue(review.decisions.isEmpty)
        XCTAssertTrue(review.checks.isEmpty)
        XCTAssertFalse(review.engineOnly)
        // And the new one round-trips without the old keys.
        var fresh = CoachPlanReview(summary: "ok", decisions: [LiftDecision(name: "Bench", move: .push, reason: "185x5")],
                                    checks: [PlanCheck(id: "ladder", title: "t", adjustments: ["a"])], recencyMessage: "m")
        fresh.notes = "n"
        let back = try JSONDecoder().decode(CoachPlanReview.self, from: JSONEncoder().encode(fresh))
        XCTAssertEqual(back, fresh)
        let text = String(decoding: try JSONEncoder().encode(fresh), as: UTF8.self)
        XCTAssertFalse(text.contains("verdict"))
        XCTAssertFalse(text.lowercased().contains("sound"))
    }

    func testDecisionsRecordTheDraftTopTheMoveAndTheFinalTop() throws {
        let ctx = DecisionHarness.context(rested: true)
        let plan = CoachDecisionApplier.apply(
            reply: DecisionHarness.reply([DecisionHarness.entry(GoldenScenario.fly, "ease", extra: "\"percent\":-10")]), context: ctx)
        let prescription = CoachReviewStore.prescription(exercises: plan.exercises, targets: plan.setTargets)
        let decisions = CoachReviewStore.decisions(prescription: prescription, exercises: plan.exercises, lifts: plan.review.decisions,
                                                   evidence: plan.evidence, energy: 6)
        let fly = try XCTUnwrap(decisions.first { $0.name == GoldenScenario.fly })
        XCTAssertEqual(fly.move, "ease")
        XCTAssertEqual(fly.draftTop, "165x8@2")
        XCTAssertEqual(fly.target.weight, 145)
        XCTAssertEqual(fly.source, "coach")
        let bench = try XCTUnwrap(decisions.first { $0.name == GoldenScenario.bench })
        XCTAssertEqual(bench.move, "as_planned")
        XCTAssertEqual(bench.source, "engine")

        // Stored with the document and read back; an older decision without the new keys still decodes.
        var doc = CoachReviewDocument()
        doc.decisions = decisions
        let back = try XCTUnwrap(CoachReviewDocument.parse(doc.encoded()))
        XCTAssertEqual(back.decisions.map(\.move), decisions.map(\.move))
        let legacy = #"{"name":"Bench","muscle":"Chest","target":{"role":"top","weight":185,"reps":6,"rir":2,"restSeconds":120},"reason":"r","context":"c","source":"coach"}"#
        let old = try JSONDecoder().decode(CoachDecision.self, from: Data(legacy.utf8))
        XCTAssertNil(old.move)
        XCTAssertNil(old.draftTop)
    }

    func testRecencyWarningTextsForTheAthleteAndForThePrompt() throws {
        let ctx = DecisionHarness.context()
        let warning = try XCTUnwrap(PlanDraftBuilder.recencyWarning(for: ctx.draft, coach: ctx.coach))
        XCTAssertEqual(warning.promptNote,
                       "NOTE: chest, shoulders and arms were trained about 5 hours ago; the app has already held or reduced those lifts.")
        XCTAssertEqual(warning.athleteText,
                       "You trained chest, shoulders and arms about 5 hours ago, so today's targets are held or lighter.")
    }
}

// MARK: - Scorecard

final class CoachScorecardTests: XCTestCase {

    private func decision(_ move: String?, hit: Bool?, result: ExerciseOutcome = .hold) -> CoachDecision {
        CoachDecision(
            name: "Bench", muscle: "Chest", target: PrescribedSet(role: .top, weight: 185, reps: 6, rir: 2, restSeconds: 120), sets: nil,
            reason: "r", context: "c", source: "coach",
            outcome: hit.map { DecisionOutcome(hit: $0, actualTop: "185x6@1", rir: 1, shortBy: $0 ? 0 : 2, result: $0 ? result : .missed) },
            draftTop: nil, move: move)
    }

    func testCountsChangesAgainstAsPlannedWithCloseCountingAsOnTarget() {
        let sessions: [[CoachDecision]] = [
            [decision("push", hit: true), decision("ease", hit: false), decision("as_planned", hit: true, result: .close)],
            [decision("goal_step", hit: true), decision("swap", hit: false), decision("as_planned", hit: false)],
            [decision("as_planned", hit: true), decision("as_planned", hit: true)]]
        let card = CoachScorecard.compute(decisionsPerSession: sessions)
        XCTAssertEqual(card.changed, CoachScorecard.Tally(onTarget: 2, missed: 2))
        XCTAssertEqual(card.asPlanned, CoachScorecard.Tally(onTarget: 3, missed: 1))
        XCTAssertEqual(card.sessions, 3)
        XCTAssertEqual(card.line, "Coach changes: 4 (2 on target, 2 missed) · As planned: 4 (3 on target, 1 missed)")
    }

    func testOlderEntriesAndUnscoredOnesAreIgnored() {
        let sessions: [[CoachDecision]] = [
            [decision(nil, hit: true), decision("push", hit: nil), decision("add", hit: true)],
            [decision("push", hit: true)]]
        let card = CoachScorecard.compute(decisionsPerSession: sessions)
        XCTAssertEqual(card.changed.total, 1)
        XCTAssertEqual(card.asPlanned.total, 0)
        XCTAssertEqual(card.sessions, 1)
        XCTAssertTrue(CoachScorecard.compute(decisionsPerSession: [[decision(nil, hit: true)]]).isEmpty)
        XCTAssertEqual(CoachScorecard().line, "Coach scorecard: no scored decisions yet")
    }

    func testOnlyTheLastNSessionsCount() {
        let sessions = (0..<30).map { _ in [decision("push", hit: true)] }
        XCTAssertEqual(CoachScorecard.compute(decisionsPerSession: sessions, lastSessions: 5).changed.total, 5)
        XCTAssertEqual(CoachScorecard.compute(decisionsPerSession: sessions).changed.total, CoachScorecard.defaultSessions)
    }

    func testTheScorecardReadsStoredDocumentsAndOutcomesAreFilledAfterTheSession() throws {
        var doc = CoachReviewDocument()
        doc.decisions = [decision("push", hit: nil)]
        var workout = Workout.create(userId: UUID(), workoutType: "Push", energyLevel: 6, timeAvailableMinutes: 45)
        workout.aiProgressionNote = doc.encoded()
        XCTAssertTrue(CoachScorecard.compute(memory: CoachMemoryIndex(workouts: [workout])).isEmpty, "no outcome yet")

        // After the session the outcome is written next to the decision.
        let analysis = SessionAnalysis(
            exercises: [ExerciseAnalysis(name: "Bench", prescription: nil, actual: [HistorySet(185, 5, rir: 1)], prescribedTop: nil,
                                         actualTop: HistorySet(185, 5, rir: 1), shortBy: 1, loadDropped: false, rirDelta: nil,
                                         outcome: .close, repeatedMiss: false, inSessionReason: nil, painOrFormSignal: false,
                                         miss: nil, target: nil, note: "")],
            skipped: [], energy: 6, userNote: nil)
        let filled = CoachReviewStore.applyOutcomes(analysis, to: doc.decisions)
        XCTAssertEqual(filled.first?.outcome?.result, .close)
        doc.decisions = filled
        workout.aiProgressionNote = doc.encoded()
        let card = CoachScorecard.compute(memory: CoachMemoryIndex(workouts: [workout]))
        XCTAssertEqual(card.changed, CoachScorecard.Tally(onTarget: 1, missed: 0), "close is on target")
    }
}

// MARK: - Weight steps on a stack

final class StackLadderTests: XCTestCase {

    private func sessions(_ weights: [[Double]]) -> [HistorySession] {
        weights.enumerated().map { i, w in
            HistorySession(date: GoldenScenario.date(11, 10 - i), sets: w.map { HistorySet($0, 12, rir: 2) })
        }
    }

    func testTwoWeightsOnACableAcrossFiveSessionsAreALadder() {
        let history = sessions([[50, 57.5], [50], [50, 50], [50], [50]])
        let ladder = WeightIncrements(name: "EZ Bar Tricep cable overhead press", sessions: history)
        XCTAssertTrue(ladder.isConfident)
        XCTAssertEqual(ladder.step, 7.5)
        XCTAssertFalse(ladder.isOnLadder(52.5), "52.5 is not on a 50 / 57.5 stack")
        XCTAssertTrue(ladder.isOnLadder(57.5))
        XCTAssertEqual(ladder.snap(52.5, direction: .down), 50)
        XCTAssertEqual(ladder.stepUp(from: 50), 57.5)
    }

    func testTheEngineNeverEmitsFiftyTwoPointFive() throws {
        // The real triceps history before 11/12: only 50 and 57.5, five sessions.
        let history = sessions([[50, 57.5], [50], [50, 50], [50], [50]])
        for hours in [5.0, 60, 100] {
            let now = history[0].date.addingTimeInterval(hours * 3600)
            let input = ProgressionInput(name: "EZ Bar Tricep cable overhead press", sessions: history, now: now)
            let result = try XCTUnwrap(ProgressionEngine.plan(input))
            for set in result.sets { XCTAssertNotEqual(set.weight, 52.5, "after \(hours) h") }
        }
    }

    func testNotEnoughEvidenceFallsBackToTheClassDefault() {
        // Three sessions only.
        XCTAssertFalse(WeightIncrements(name: "Cable Triceps Pushdown", sessions: sessions([[50, 57.5], [50], [50]])).isConfident)
        // A gap that is not a stack step.
        XCTAssertFalse(WeightIncrements(name: "Cable Triceps Pushdown", sessions: sessions([[50, 53], [50], [50], [50]])).isConfident)
        // Not selectorised: dumbbells and plates are not a pin stack.
        XCTAssertFalse(WeightIncrements(name: "Dumbbell Lateral Raises", sessions: sessions([[25, 30], [25], [25], [25]])).isConfident)
        XCTAssertFalse(WeightIncrements(name: "Smith Machine Flat Bench Press", sessions: sessions([[185, 190], [185], [185], [185]])).isConfident)
        // A gap no wider than the class default is no news.
        XCTAssertFalse(WeightIncrements(name: "Cable Triceps Pushdown", sessions: sessions([[50, 52.5], [50], [50], [50]])).isConfident)
        // A pec fly machine with a 10 lb gap is believed.
        XCTAssertEqual(WeightIncrements(name: "Pec Fly Machine", sessions: sessions([[100, 110], [100], [100], [110]])).step, 10)
    }
}
