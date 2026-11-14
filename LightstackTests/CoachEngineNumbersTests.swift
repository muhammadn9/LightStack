import XCTest
@testable import Lightstack

/// The engine as the source of truth: weight ladders, the "close" outcome, rep-jump and recency rules, one e1RM,
/// whole-sentence reasons. The real 11/12 case lives in CoachGoldenScenarioTests.
final class WeightIncrementsTests: XCTestCase {

    private func ladder(_ weights: [Double], fallback: Double, plate: Bool = false) -> WeightIncrements {
        WeightIncrements(weights: weights, fallbackStep: fallback, plateLoaded: plate)
    }

    func testCableStackWithAStepOfSevenAndAHalfNeverHas52Point5() {
        let l = ladder([42.5, 50, 50, 57.5, 50], fallback: 2.5)
        XCTAssertEqual(l.inferredStep, 7.5)
        XCTAssertFalse(l.isOnLadder(52.5))
        XCTAssertEqual(l.snap(52.5, direction: .down), 50)
        XCTAssertEqual(l.snap(52.5, direction: .up), 57.5)
        XCTAssertEqual(l.snap(54, direction: .nearest), 57.5)
        XCTAssertEqual(l.snap(50, direction: .down), 50, "already on the ladder stays")
        XCTAssertEqual(l.snap(50, direction: .up), 50)
        XCTAssertEqual(l.stepUp(from: 50), 57.5)
        XCTAssertEqual(l.stepDown(from: 50), 42.5)
        XCTAssertEqual(l.snap(65.2), 65)
    }

    func testPlateLoadedLiftStillMovesInFives() {
        let l = ladder([175, 180, 185, 185, 150], fallback: 5, plate: true)
        XCTAssertEqual(l.step, 5)
        XCTAssertEqual(l.stepUp(from: 185), 190)
        let input = ProgressionInput(name: "Smith Machine Flat Bench Press",
                                     sessions: [GoldenScenario.session(11, 3, "175x10@2, 180x10@1, 185x10@1")], energy: 7)
        XCTAssertEqual(ProgressionEngine.plan(input)?.topSet?.weight, 190, "185x10 at the top of the range goes to 190")
    }

    func testPlateLoadedIgnoresAWiderInferredStep() {
        // 135, 155, 175 on a barbell: the athlete chose 20-lb jumps, the plates still allow fives.
        let l = ladder([135, 155, 175], fallback: 5, plate: true)
        XCTAssertNil(l.inferredStep)
        XCTAssertEqual(l.step, 5)
    }

    func testDumbbellsMoveInTwoAndAHalfUnlessHistoryContradicts() {
        XCTAssertEqual(WeightIncrements.fallback(for: "Dumbbell Lateral Raises").stepUp(from: 25), 27.5)
        let fives = ladder([20, 25, 30, 35], fallback: 2.5)
        XCTAssertEqual(fives.inferredStep, 5)
        XCTAssertEqual(fives.stepUp(from: 25), 30)
        let withHalf = ladder([22.5, 25, 27.5, 30], fallback: 2.5)
        XCTAssertEqual(withHalf.stepUp(from: 25), 27.5)
    }

    func testSparseHistoryFallsBackToTheClassStep() {
        let two = ladder([50, 57.5], fallback: 2.5)
        XCTAssertNil(two.inferredStep, "two weights prove nothing")
        XCTAssertEqual(two.snap(52.5), 52.5)
        let one = ladder([25], fallback: 2.5)
        XCTAssertEqual(one.snap(26), 25)
        XCTAssertEqual(WeightIncrements.fallback(for: "Barbell Squat").step, 5)
        XCTAssertEqual(WeightIncrements.fallback(for: "Barbell Squat").snap(183, direction: .up), 185)
    }

    func testNoiseAndOneOffOutliersAreTolerated() {
        let noisy = ladder([57.5, 57, 50, 50.4, 42.5], fallback: 2.5)
        XCTAssertEqual(noisy.inferredStep, 7.5)
        let outlier = ladder([40, 45, 50, 55, 60, 52], fallback: 5)
        XCTAssertEqual(outlier.inferredStep, 5, "a stray 52 does not drag the step down")
    }

    func testStepsMuchWiderThanTheClassAreNotTrusted() {
        // 140, 160, 180 on a cable stack that moves in fives (a coincidence of the loads picked).
        let l = ladder([140, 160, 180], fallback: 5)
        XCTAssertNil(l.inferredStep)
        XCTAssertEqual(l.step, 5)
    }

    func testHalvesRoundUpOnBothSidesOfTheAnchor() {
        let l = ladder([110, 160, 180, 200, 220, 230], fallback: 5, plate: true)
        XCTAssertEqual(l.snap(92.5), 95)
        XCTAssertEqual(l.snap(102.5), 105)
    }
}

final class CoachEngineOutcomeTests: XCTestCase {

    private func analysis(_ logged: String, planned: (Double, Int), name: String = GoldenScenario.bench, group: String = "Chest",
                          history: [HistorySession], now: Date, previous: [CoachReviewEntry] = []) throws -> ExerciseAnalysis {
        let rx = ExercisePrescription(name: name, muscleGroup: group,
                                      sets: [PrescribedSet(role: .top, weight: planned.0, reps: planned.1, rir: 2, restSeconds: 120)])
        let index = ExerciseHistoryIndex(groups: [ExerciseHistoryGroup(names: [name], sessions: history,
                                                                       best: ExerciseHistoryIndex.bestLogged(in: history))])
        let a = SessionAnalyzer.analyze(logged: [LoggedExercise(name: name, muscleGroup: group, sets: GoldenScenario.sets(logged))],
                                        prescription: [rx], energy: 7, userNote: nil, reasons: [:], previous: previous,
                                        history: index, focus: .hypertrophy, now: now)
        return try XCTUnwrap(a.exercises.first)
    }

    private let recentBench = [GoldenScenario.session(11, 6, "175x6, 185x6, 180x5"), GoldenScenario.session(11, 2, "175x6, 185x5, 180x5")]
    private let today = GoldenScenario.date(11, 8)

    func testOneRepShortAtThePlannedWeightIsCloseNotAMiss() throws {
        let a = try analysis("185x5@1", planned: (185, 6), history: recentBench, now: today)
        XCTAssertEqual(a.outcome, .close)
        XCTAssertNil(a.miss)
        XCTAssertEqual(a.target?.weight, 185)
        XCTAssertEqual(a.target?.reps, 6)
        XCTAssertFalse(a.isMiss)
        XCTAssertTrue(a.promptLine.contains("CLOSE"), a.promptLine)
        XCTAssertFalse(a.promptLine.contains("MISSED"), a.promptLine)
    }

    func testTwoRepsShortOrOneShortOnAPlanUnderFiveIsStillAMiss() throws {
        XCTAssertEqual(try analysis("185x4@1", planned: (185, 6), history: recentBench, now: today).outcome, .missed)
        XCTAssertEqual(try analysis("185x3@0", planned: (185, 4), history: recentBench, now: today).outcome, .missed,
                       "one short of a 4-rep plan is a real miss")
    }

    func testALighterWeightThatIsAChoiceWithFewerRepsIsAMiss() throws {
        let a = try analysis("175x5@1", planned: (185, 6), history: recentBench, now: today)
        XCTAssertEqual(a.outcome, .missed)
        XCTAssertTrue(a.loadDropped)
        XCTAssertFalse(a.plannedWeightUnavailable)
        XCTAssertTrue(a.promptLine.contains("did 175×5@1; planned 185x6@2"), a.promptLine)
        XCTAssertFalse(a.promptLine.contains("by 1 rep"), a.promptLine)
    }

    func testUnavailablePlannedWeightWithThePlannedRepsIsOnTargetAndSaysSo() throws {
        let a = try analysis("50x12@2, 50x12@2", planned: (52.5, 12), name: GoldenScenario.triceps, group: "Triceps",
                             history: GoldenScenario.before1112[GoldenScenario.triceps] ?? [], now: today)
        XCTAssertTrue(a.plannedWeightUnavailable)
        XCTAssertNil(a.miss)
        XCTAssertNotEqual(a.outcome, .missed)
        XCTAssertEqual(a.shortBy, 0)
        XCTAssertTrue(a.promptLine.contains("did 50×12@2; planned 52.5x12@2"), a.promptLine)
        XCTAssertFalse(a.note.contains("short by"), a.note)
        // The same logging with fewer reps than planned is a shortfall again.
        let fewer = try analysis("50x10@1", planned: (52.5, 12), name: GoldenScenario.triceps, group: "Triceps",
                                 history: GoldenScenario.before1112[GoldenScenario.triceps] ?? [], now: today)
        XCTAssertFalse(fewer.plannedWeightUnavailable)
        XCTAssertNotEqual(fewer.outcome, .hold)
    }

    func testHeavierThanPlannedWithFewerRepsIsNotAShortfallByRepsAlone() throws {
        // 190x6 is worth about 185x7 by e1RM: judged at the planned weight it is not short.
        let a = try analysis("190x6@1", planned: (185, 6), history: recentBench, now: today)
        XCTAssertEqual(a.shortBy, 0)
        XCTAssertNil(a.miss)
    }

    func testAShortfallAfterMoreThanFourteenDaysIsAReturnFromALayoffAndNotARepeatedMiss() throws {
        let old = [GoldenScenario.session(10, 20, "175x6, 185x6, 180x5")]
        var doc = CoachReviewDocument()
        doc.review = SessionReview(exercises: [ExerciseReview(name: GoldenScenario.bench, notes: "", outcome: .missed)],
                                   overallRead: "r", recurringFlags: [])
        let missedBefore = [CoachReviewEntry(workoutId: UUID(), date: GoldenScenario.date(10, 20), workoutType: "Push", document: doc)]
        let a = try analysis("185x3@0", planned: (185, 6), history: old, now: GoldenScenario.date(11, 8), previous: missedBefore)
        XCTAssertEqual(a.outcome, .missed)
        XCTAssertEqual(a.layoffDays, 19)
        XCTAssertFalse(a.repeatedMiss)
        XCTAssertEqual(a.miss?.cause, .afterBreak)
        XCTAssertNotEqual(a.miss?.cause, .strengthLoss)
        XCTAssertTrue(a.miss?.reason.contains("First session back after 19 days") == true, a.miss?.reason ?? "")
        XCTAssertFalse(SessionAnalyzer.mandatoryFlags(SessionAnalysis(exercises: [a], skipped: [], energy: 7, userNote: nil))
                        .contains { $0.contains("two sessions in a row") })
        // Exactly 14 days is not a layoff.
        let edge = try analysis("185x3@0", planned: (185, 6), history: old, now: GoldenScenario.date(11, 3))
        XCTAssertNil(edge.layoffDays)
    }

    func testCloseCountsAsOnTargetEverywhere() throws {
        let a = try analysis("185x5@1", planned: (185, 6), history: recentBench, now: today)
        let s = SessionAnalysis(exercises: [a], skipped: [], energy: 7, userNote: nil)
        XCTAssertEqual(s.missedCount, 0)
        XCTAssertEqual(s.onTargetCount, 1)
        let read = SessionAnalyzer.deterministicOverallRead(s, workoutType: "Push")
        XCTAssertTrue(read.contains("1 of 1 lifts on target"), read)
        XCTAssertFalse(read.lowercased().contains("missed"), read)
        // Memory: a close call is a hit that reads as CLOSE.
        let top = PrescribedSet(role: .top, weight: 185, reps: 6, rir: 2, restSeconds: 120)
        let decision = CoachDecision(name: GoldenScenario.bench, muscle: "Chest", target: top, sets: nil, reason: "r",
                                     context: "c", source: "engine", outcome: nil)
        let joined = CoachReviewStore.applyOutcomes(s, to: [decision])
        XCTAssertEqual(joined.first?.outcome?.hit, true)
        XCTAssertEqual(joined.first?.outcome?.result, .close)
        // The model cannot turn a close into something else, nor invent one.
        let model = try XCTUnwrap(ModelReview.parse(#"{"exercises":[{"name":"\#(GoldenScenario.bench)","outcome":"pr"}]}"#))
        XCTAssertEqual(SessionAnalyzer.merge(s, model: model, workoutType: "Push").exercises.first?.outcome, .close)
    }

    func testOutcomeIsBackwardCompatibleWhenStored() throws {
        let decoder = JSONDecoder()
        for old in ["pr", "hold", "regression", "missed", "new"] {
            XCTAssertEqual(try decoder.decode(ExerciseOutcome.self, from: Data("\"\(old)\"".utf8)).rawValue, old)
        }
        XCTAssertEqual(try decoder.decode(ExerciseOutcome.self, from: Data("\"close\"".utf8)), .close)
        XCTAssertEqual(try decoder.decode(ExerciseOutcome.self, from: Data("\"someFutureCase\"".utf8)), .hold,
                       "an unknown value from a newer build must not fail the document")
        // A whole stored document with a close round-trips, and one with an unknown outcome still loads.
        var doc = CoachReviewDocument()
        doc.review = SessionReview(exercises: [ExerciseReview(name: "Bench", notes: "n", outcome: .close)], overallRead: "r", recurringFlags: [])
        let text = try XCTUnwrap(doc.encoded())
        XCTAssertEqual(CoachReviewDocument.parse(text)?.review?.exercises.first?.outcome, .close)
        let future = text.replacingOccurrences(of: "\"close\"", with: "\"nextYear\"")
        XCTAssertEqual(CoachReviewDocument.parse(future)?.review?.exercises.first?.outcome, .hold)
    }
}

final class CoachEngineRulesTests: XCTestCase {

    private let bench = GoldenScenario.bench

    func testBackoffNeverJumpsInRepsAtAWeightJustDone() {
        // 11/12: 170x5@1. Planned 170x7@2 (+2) is too much after a hard set: at most 170x6@2.
        XCTAssertEqual(RepJumpRule.maxReps(weight: 170, rir: 2, last: GoldenScenario.sets("185x5@1, 170x5@1"),
                                           ladder: WeightIncrements.fallback(for: bench))?.reps, 6)
        // Last set was easy (RIR 3) and the target is no easier: +2.
        XCTAssertEqual(RepJumpRule.maxReps(weight: 170, rir: 2, last: GoldenScenario.sets("170x5@3"),
                                           ladder: WeightIncrements.fallback(for: bench))?.reps, 7)
        // Higher RIR asked than last time: +1 even though last RIR was 2.
        XCTAssertEqual(RepJumpRule.maxReps(weight: 170, rir: 3, last: GoldenScenario.sets("170x5@2"),
                                           ladder: WeightIncrements.fallback(for: bench))?.reps, 6)
        // Nothing near that weight last time: no cap.
        XCTAssertNil(RepJumpRule.maxReps(weight: 120, rir: 2, last: GoldenScenario.sets("185x5@1"),
                                         ladder: WeightIncrements.fallback(for: bench)))
    }

    func testEngineAppliesTheRepJumpRuleToEverySet() throws {
        // Last: 185x6@1, 170x5@1 (back-off). Free to progress, but the back-off still may not jump.
        let history = [GoldenScenario.session(11, 12, "95x10@5, 150x10@2, 185x6@1, 170x5@1"),
                       GoldenScenario.session(10, 28, "150x10, 185x6, 170x8")]
        var input = ProgressionInput(name: bench, sessions: history, best: HistorySet(185, 6), energy: 7, allowWarmups: true)
        input.now = GoldenScenario.date(11, 15)
        let result = try XCTUnwrap(ProgressionEngine.plan(input))
        for set in result.workingSets where abs(set.weight - 170) <= 5 { XCTAssertLessThanOrEqual(set.reps, 6, set.text) }
        XCTAssertFalse(result.repCaps.isEmpty)
    }

    func testIsolationRepsAreCappedToo() throws {
        let history = [GoldenScenario.session(11, 12, "25x9@1, 25x9@1")]
        var input = ProgressionInput(name: GoldenScenario.laterals, sessions: history, energy: 7)
        input.now = GoldenScenario.date(11, 15)
        let result = try XCTUnwrap(ProgressionEngine.plan(input))
        for set in result.workingSets where set.weight == 25 { XCTAssertLessThanOrEqual(set.reps, 10) }
    }

    func testSameLiftWithinADayNeverProgressesAndTheMainLiftComesDown() throws {
        let history = [GoldenScenario.session1112(bench)] + (GoldenScenario.before1112[bench] ?? [])
        var input = ProgressionInput(name: bench, sessions: history, best: HistorySet(185, 6), energy: 7, allowWarmups: true)
        input.now = GoldenScenario.date(11, 12, hour: 13)
        let result = try XCTUnwrap(ProgressionEngine.plan(input))
        let top = try XCTUnwrap(result.topSet)
        XCTAssertEqual(top.weight, 175, "about 5% under 185, on the ladder")
        XCTAssertLessThanOrEqual(top.reps, 5)
        XCTAssertEqual(top.rir, 2)
        XCTAssertEqual(result.workingSets.count, 2, "no back-off")
        XCTAssertNotNil(result.noProgressReason)
        // A few days later nothing holds it back.
        input.now = GoldenScenario.date(11, 16, hour: 13)
        XCTAssertNil(try XCTUnwrap(ProgressionEngine.plan(input)).noProgressReason)
    }

    func testLowFuelHoldsAProgressingLift() throws {
        let history = [GoldenScenario.session(11, 3, "175x10@2, 180x10@1, 185x10@1")]
        var input = ProgressionInput(name: bench, sessions: history, best: HistorySet(185, 10), energy: 7)
        input.now = GoldenScenario.date(11, 8)
        XCTAssertEqual(try XCTUnwrap(ProgressionEngine.plan(input)).topSet?.weight, 190, "fed: the jump is made")
        input.fuelLow = true
        input.fuelReason = "eating well under target this week"
        let held = try XCTUnwrap(ProgressionEngine.plan(input))
        XCTAssertEqual(held.topSet?.weight, 185)
        XCTAssertLessThanOrEqual(held.topSet?.reps ?? 99, 10)
        XCTAssertTrue(held.noProgressReason?.contains("fuel") == true)
    }

    func testRecencyWarningRules() {
        let now = GoldenScenario.date(11, 12, hour: 13)
        let lifts = [(name: "Bench Press", muscleGroup: "Chest"), (name: "Lat Pulldown", muscleGroup: "Back")]
        let recency = ["chest": MuscleRecency(lastTrained: GoldenScenario.date(11, 12, hour: 8), hardSets: 5),
                       "back": MuscleRecency(lastTrained: GoldenScenario.date(11, 12, hour: 8), hardSets: 1)]
        let w = RecencyWarning.make(lifts: lifts, recency: recency, now: now)
        XCTAssertEqual(w?.message, "You trained chest about 5 hours ago.", "back had only 1 hard set")
        XCTAssertNil(RecencyWarning.make(lifts: lifts, recency: recency, now: GoldenScenario.date(11, 13, hour: 9)), "25 hours later")
        XCTAssertNil(RecencyWarning.make(lifts: lifts, recency: [:], now: now))
        let soon = RecencyWarning.make(lifts: lifts, recency: recency, now: GoldenScenario.date(11, 12, hour: 8).addingTimeInterval(1200))
        XCTAssertEqual(soon?.message, "You trained chest less than an hour ago.")
    }
}

final class CoachEngineOneRepMaxTests: XCTestCase {

    func testOneFormulaEverywhere() {
        XCTAssertEqual(OneRepMax.estimate(weight: 185, reps: 6), 222, accuracy: 0.001)
        XCTAssertEqual(HistorySet(185, 6).e1RM, OneRepMax.estimate(weight: 185, reps: 6))
        XCTAssertEqual(GoalAssessor.Point(date: Date(), weight: 185, reps: 6).e1RM, 222, accuracy: 0.001)
        XCTAssertEqual(OneRepMax.estimate(weight: 205, reps: 3), 225.5, accuracy: 0.001)
        XCTAssertEqual(OneRepMax.weight(forE1RM: 222, reps: 6), 185, accuracy: 0.001)
    }

    func testGoalLineSaysNowAndNeedsWithoutBeingReadableBackwards() throws {
        let sessions = [GoldenScenario.session1112(GoldenScenario.bench)] + (GoldenScenario.before1112[GoldenScenario.bench] ?? [])
        let points = GoalAssessor.topPoints(from: sessions + [GoldenScenario.session(10, 16, "230x1@1")])
        let a = try XCTUnwrap(GoalAssessor.assess(exercise: GoldenScenario.bench, targetWeight: 205, targetReps: 3,
                                                  history: points, now: GoldenScenario.date(11, 13)))
        let goal = CoachGoal(exerciseName: GoldenScenario.bench, targetWeight: 205, targetReps: 3, deadline: nil, steps: [])
        let block = CoachPromptService(validationService: ValidationService()).goalsBlock(
            [GoalPlanItem(goal: goal, assessment: a, step: nil, stepIsToday: false)]) ?? ""
        XCTAssertTrue(block.contains("now ~222 e1RM, goal needs ~226"), block)
    }
}

final class CoachTextClippingTests: XCTestCase {

    func testReasonsAndCuesKeepTheWholeSentence() {
        let reason = "Progressing bench press stability and strength after a lighter week, so the load holds and the reps build."
        XCTAssertEqual(InputSanitizer.sanitizeSentence(reason, limit: 200), reason)
        let cue = "Keep a steady cadence and squeeze at full contraction on every single rep."
        XCTAssertEqual(InputSanitizer.sanitizeSentence(cue, limit: 160), cue)
        // sanitizeLabel is the short-label cap: using it for these was the bug.
        XCTAssertLessThan(InputSanitizer.sanitizeLabel(reason).count, reason.count)
    }

    func testLongTextIsCutAtAWordBoundaryWithAnEllipsis() {
        let text = "Safety rail: top weight 195 is above the limit of 185 (15 days since the last session, so no increase over 185)"
        let clipped = InputSanitizer.clipAtWord(text, limit: 60)
        XCTAssertLessThanOrEqual(clipped.count, 60)
        XCTAssertTrue(clipped.hasSuffix("…"))
        let body = String(clipped.dropLast())
        XCTAssertTrue(text.hasPrefix(body))
        let next = text[text.index(text.startIndex, offsetBy: body.count)]
        XCTAssertEqual(next, " ", "cut sits between words: \(clipped)")
        XCTAssertEqual(InputSanitizer.clipAtWord("short", limit: 60), "short")
    }

    func testStoredDecisionReasonAndPromptLinesCutOnWordsNotMidWord() {
        let reason = "Safety rail: top weight 195 is above the limit of 185 (15 days since the last session, so no increase over 185)"
        XCTAssertEqual(SessionAnalyzer.cleanLine(reason, limit: CoachReviewStore.decisionReasonLimit), reason)
        let tight = SessionAnalyzer.cleanLine(reason, limit: 50) ?? ""
        XCTAssertFalse(tight.contains("se…"), tight)
        XCTAssertLessThanOrEqual(tight.count, 50)
    }
}
