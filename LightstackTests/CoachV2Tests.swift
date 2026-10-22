import XCTest
import Supabase
@testable import Lightstack

// MARK: - Fixtures shared by the Coach v2 tests

private enum V2 {
    static let bench = "Smith Machine Flat Bench Press"
    static let fly = "Single Arm Pec Fly Machine"

    static func day(_ month: Int, _ d: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: month, day: d, hour: 12)) ?? Date()
    }

    static func sets(_ text: String) -> [HistorySet] {
        text.split(separator: ",").map { token in
            let parts = token.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0 == "x" || $0 == "@" })
            return HistorySet(Double(parts[0]) ?? 0, Int(parts[1]) ?? 0, rir: parts.count > 2 ? Int(parts[2]) : nil)
        }
    }

    static func session(_ m: Int, _ d: Int, _ text: String) -> HistorySession {
        HistorySession(date: day(m, d), sets: sets(text))
    }

    static var benchHistory: [HistorySession] {
        [session(10, 20, "160x3@4, 185x6@1, 185x6@1, 180x5@1"),
         session(10, 16, "110x6@4, 160x5@3, 180x3@3, 200x3@3, 220x1@2, 230x1@1, 160x8@1, 180x6@1")]
    }
    static var flyHistory: [HistorySession] {
        [session(10, 20, "160x9@2, 160x7@1"), session(10, 12, "140x9@2, 140x7@1")]
    }

    static var history: ExerciseHistoryIndex {
        ExerciseHistoryIndex(groups: [
            ExerciseHistoryGroup(names: [bench], sessions: benchHistory, best: HistorySet(230, 1)),
            ExerciseHistoryGroup(names: [fly], sessions: flyHistory, best: HistorySet(160, 9))])
    }

    /// What the engine prescribes for the bench in the owner's history.
    static var benchPrescription: ExercisePrescription {
        let r = ProgressionEngine.plan(ProgressionInput(name: bench, sessions: benchHistory, best: HistorySet(230, 1),
                                                        allowWarmups: true))
        return ExercisePrescription(name: bench, muscleGroup: "Chest", sets: r?.sets.map(\.prescribed) ?? [])
    }

    static func review(_ name: String, outcome: ExerciseOutcome, target: NextTarget? = nil,
                       miss: MissAnalysis? = nil) -> CoachReviewEntry {
        var doc = CoachReviewDocument()
        doc.review = SessionReview(
            exercises: [ExerciseReview(name: name, notes: "n", outcome: outcome, nextTarget: target, missAnalysis: miss)],
            overallRead: "read", recurringFlags: ["rear delts skipped"], createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        return CoachReviewEntry(workoutId: UUID(), date: day(10, 16), workoutType: "Push", document: doc)
    }

    static func analyze(
        _ logged: String, energy: Int = 6, note: String? = nil, reasons: [String: String] = [:],
        previous: [CoachReviewEntry] = [], history: ExerciseHistoryIndex = V2.history,
        prescription: [ExercisePrescription]? = nil
    ) -> SessionAnalysis {
        SessionAnalyzer.analyze(
            logged: [LoggedExercise(name: bench, muscleGroup: "Chest", sets: sets(logged))],
            prescription: prescription ?? [benchPrescription], energy: energy, userNote: note, reasons: reasons,
            previous: previous, history: history, focus: .hypertrophy)
    }
}

// MARK: - Document

final class CoachReviewDocumentTests: XCTestCase {

    private func fullDocument() -> CoachReviewDocument {
        var doc = CoachReviewDocument()
        doc.prescription = [V2.benchPrescription]
        doc.planReview = CoachPlanReview(
            verdict: .adjusted, summary: "Moved rows first",
            changes: [PlanChange(type: .loadAdjust, exercise: "Row", detail: "-10%", reason: "tired", percent: -10,
                                 applied: true, note: nil)],
            safeguards: ["Back trained 20 h ago"])
        doc.review = SessionReview(
            exercises: [ExerciseReview(
                name: V2.bench, notes: "Missed by one.", outcome: .missed,
                nextTarget: NextTarget(weight: 185, reps: 7, note: "retry"),
                missAnalysis: MissAnalysis(cause: .lowEnergy, decision: .retry, reason: "bad day"))],
            overallRead: "Decent session.", recurringFlags: ["Rear delts skipped"],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000), aiAuthored: true)
        doc.inSessionReasons = [V2.bench: "lowEnergy"]
        return doc
    }

    func testRoundTrips() throws {
        let doc = fullDocument()
        let text = try XCTUnwrap(doc.encoded())
        XCTAssertTrue(text.hasPrefix("{"))
        XCTAssertEqual(CoachReviewDocument.parse(text), doc)
        XCTAssertEqual(CoachReviewDocument.parse(text)?.version, CoachReviewDocument.currentVersion)
        XCTAssertEqual(doc.encoded(), doc.encoded(), "stable output")
    }

    func testLegacyPlainTextStillLoads() {
        let doc = CoachReviewDocument.parse("Solid session. Add 5 lbs to bench.")
        XCTAssertEqual(doc?.legacyNote, "Solid session. Add 5 lbs to bench.")
        XCTAssertNil(doc?.review)
        XCTAssertEqual(CoachReviewDocument.displayText(from: "Solid session. Add 5 lbs to bench."), "Solid session. Add 5 lbs to bench.")
        XCTAssertNil(CoachReviewDocument.parse(nil))
        XCTAssertNil(CoachReviewDocument.parse("   \n"))
        XCTAssertNil(CoachReviewDocument.displayText(from: ""))
        // Text that merely looks like JSON is kept as a legacy note.
        XCTAssertEqual(CoachReviewDocument.parse("{not json at all")?.legacyNote, "{not json at all")
        // A legacy note survives a round trip through a new document.
        var doc2 = CoachReviewDocument(legacyNote: "old")
        doc2.prescription = [V2.benchPrescription]
        XCTAssertEqual(CoachReviewDocument.parse(doc2.encoded())?.legacyNote, "old")
    }

    func testOneDamagedSectionDoesNotLoseTheRest() throws {
        let text = #"{"coachReview":1,"prescription":[{"name":"Bench","sets":[{"role":"top","weight":185,"reps":7,"rir":1,"restSeconds":120}]}],"review":{"oops":true}}"#
        let doc = try XCTUnwrap(CoachReviewDocument.parse(text))
        XCTAssertNil(doc.legacyNote)
        XCTAssertEqual(doc.prescription.first?.topSet?.weight, 185)
        XCTAssertNil(doc.review)
    }

    func testDisplayTextShowsReadTargetsAndFlagsButNotPlanOnlyDocuments() throws {
        let text = try XCTUnwrap(CoachReviewDocument.displayText(from: fullDocument().encoded()))
        XCTAssertTrue(text.hasPrefix("Decent session."))
        XCTAssertTrue(text.contains("185 x 7"))
        XCTAssertTrue(text.contains("Rear delts skipped"))
        var planOnly = CoachReviewDocument()
        planOnly.prescription = [V2.benchPrescription]
        XCTAssertNil(CoachReviewDocument.displayText(from: planOnly.encoded()))
    }

    func testSetTargetCarriesRoleAndRestAndOldJSONStillDecodes() throws {
        let t = SetTarget(weight: "185", reps: "7", rir: "1", role: .top, restSeconds: 120)
        XCTAssertEqual(t.resolvedRole, .top)
        XCTAssertNil(t.isWarmup)
        let back = try JSONDecoder().decode(SetTarget.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(back, t)
        XCTAssertEqual(SetTarget(weight: "95", reps: "10", rir: "5", role: .warmup).isWarmup, true)
        XCTAssertEqual(SetTarget(weight: "95", reps: "10", rir: "5", isWarmup: true).resolvedRole, .warmup)
        let old = try JSONDecoder().decode(SetTarget.self, from: Data(#"{"weight":"100","reps":"8","rir":"2"}"#.utf8))
        XCTAssertEqual(old.resolvedRole, .straight)
        XCTAssertNil(old.restSeconds)
    }
}

// MARK: - Prescribed vs actual and the miss rules

final class SessionAnalyzerTests: XCTestCase {

    private let missedByOne = "95x10@5, 150x10@2, 185x6@1, 170x8@2"

    private func bench(_ a: SessionAnalysis, file: StaticString = #filePath, line: UInt = #line) throws -> ExerciseAnalysis {
        try XCTUnwrap(a.exercises.first, file: file, line: line)
    }

    func testPrescriptionIsWhatTheEngineBuilt() {
        XCTAssertEqual(V2.benchPrescription.sets.map(\.role), [.warmup, .ramp, .top, .backoff])
        XCTAssertEqual(V2.benchPrescription.topSet?.weight, 185)
        XCTAssertEqual(V2.benchPrescription.topSet?.reps, 7)
    }

    func testHitTopSetIsNotAMiss() throws {
        let a = try bench(V2.analyze("95x10@5, 150x10@2, 185x7@1, 170x8@2"))
        XCTAssertEqual(a.shortBy, 0)
        XCTAssertNil(a.miss)
        XCTAssertEqual(a.outcome, .hold)
        XCTAssertEqual(a.target, NextTarget(weight: 185, reps: 8, note: "Add a rep"))
    }

    func testOneOffMissOnABadDayRetriesTheSameTarget() throws {
        for energy in [2, 3, 4] {
            let a = try bench(V2.analyze(missedByOne, energy: energy))
            XCTAssertEqual(a.shortBy, 1)
            XCTAssertEqual(a.outcome, .missed)
            XCTAssertEqual(a.miss?.decision, .retry, "energy \(energy)")
            XCTAssertEqual(a.miss?.cause, .lowEnergy)
            XCTAssertEqual(a.target?.weight, 185)
            XCTAssertEqual(a.target?.reps, 7)
        }
        // Bad sleep or fuel, said in-session or in the note, is also a bad day even with good energy.
        let sleepy = try bench(V2.analyze(missedByOne, energy: 8, reasons: [V2.bench: MissReason.poorSleep.rawValue]))
        XCTAssertEqual(sleepy.miss?.cause, .poorRecovery)
        XCTAssertEqual(sleepy.miss?.decision, .retry)
        let fasted = try bench(V2.analyze(missedByOne, energy: 8, note: "Trained fasted, barely slept"))
        XCTAssertEqual(fasted.miss?.decision, .retry)
    }

    func testMissWithGoodEnergyDropsAndRebuilds() throws {
        let a = try bench(V2.analyze(missedByOne, energy: 8))
        XCTAssertEqual(a.miss?.cause, .strengthLoss)
        XCTAssertEqual(a.miss?.decision, .reduceAndRebuild)
        XCTAssertEqual(a.target?.weight, 175, "185 -5%, rounded down to the plate step")
        XCTAssertEqual(a.target?.reps, 7)
        let big = try bench(V2.analyze("95x10@5, 150x10@2, 185x4@0, 170x8@2", energy: 8))
        XCTAssertEqual(big.shortBy, 3)
        XCTAssertEqual(big.target?.weight, 165, "a big miss drops 10%")
        XCTAssertTrue(big.harderThanPlanned)
    }

    func testTwoMissesInARowDropEvenOnALowEnergyDay() throws {
        let previous = [V2.review(V2.bench, outcome: .missed)]
        let a = try bench(V2.analyze(missedByOne, energy: 3, previous: previous))
        XCTAssertTrue(a.repeatedMiss)
        XCTAssertEqual(a.miss?.decision, .reduceAndRebuild)
        XCTAssertEqual(a.miss?.cause, .strengthLoss)
        XCTAssertLessThan(a.target?.weight ?? 999, 185)
        XCTAssertTrue(SessionAnalyzer.mandatoryFlags(V2.analyze(missedByOne, energy: 3, previous: previous)).contains { $0.contains("two sessions in a row") })
        // A previous hit does not count.
        let hit = try bench(V2.analyze(missedByOne, energy: 3, previous: [V2.review(V2.bench, outcome: .hold)]))
        XCTAssertFalse(hit.repeatedMiss)
        XCTAssertEqual(hit.miss?.decision, .retry)
    }

    func testPainOrFormHoldsAndFlags() throws {
        let byNote = V2.analyze(missedByOne, energy: 8, note: "Left shoulder pinch on bench")
        let a = try bench(byNote)
        XCTAssertEqual(a.miss?.cause, .painOrForm)
        XCTAssertEqual(a.miss?.decision, .holdOrSwap)
        XCTAssertEqual(a.target?.weight, 185, "load is held, not pushed or cut")
        XCTAssertTrue(SessionAnalyzer.mandatoryFlags(byNote).contains { $0.contains("Pain or form") })
        // Pain mentioned about something else does not blame the bench.
        let elsewhere = try bench(V2.analyze(missedByOne, energy: 8, note: "knee hurt on the warm-up bike"))
        XCTAssertNotEqual(elsewhere.miss?.cause, .painOrForm)
        let byReason = try bench(V2.analyze(missedByOne, energy: 3, reasons: [V2.bench: "painOrForm"]))
        XCTAssertEqual(byReason.miss?.decision, .holdOrSwap)
    }

    func testNeutralEnergyMissDependsOnHowBigItWas() throws {
        XCTAssertEqual(try bench(V2.analyze(missedByOne, energy: 6)).miss?.decision, .retry)
        XCTAssertEqual(try bench(V2.analyze(missedByOne, energy: 6)).miss?.cause, .unknown)
        XCTAssertEqual(try bench(V2.analyze("95x10@5, 150x10@2, 185x4@1, 170x8@2", energy: 6)).miss?.decision, .reduceAndRebuild)
        XCTAssertEqual(try bench(V2.analyze(missedByOne, energy: 6, reasons: [V2.bench: "tooHeavy"])).miss?.decision, .reduceAndRebuild)
    }

    func testLighterLoadCountsAsAMiss() throws {
        let a = try bench(V2.analyze("95x10@5, 150x10@2, 170x8@1"))
        XCTAssertTrue(a.loadDropped)
        XCTAssertGreaterThanOrEqual(a.shortBy, 1)
        XCTAssertEqual(a.outcome, .missed)
    }

    func testPRNewAndRegressionOutcomes() throws {
        let lowBest = ExerciseHistoryIndex(groups: [ExerciseHistoryGroup(names: [V2.bench], sessions: V2.benchHistory, best: HistorySet(200, 3))])
        XCTAssertEqual(try bench(V2.analyze("95x10@5, 150x10@2, 190x7@1, 170x8@2", history: lowBest)).outcome, .pr)
        XCTAssertEqual(try bench(V2.analyze("95x10@5, 150x10@2, 185x7@1", history: ExerciseHistoryIndex())).outcome, .new)
        // A prescription the athlete met, but well under the previous session.
        let lighter = ExercisePrescription(name: V2.bench, muscleGroup: "Chest",
                                           sets: [PrescribedSet(role: .top, weight: 150, reps: 7, rir: 1, restSeconds: 120)])
        let a = try bench(V2.analyze("150x7@1", prescription: [lighter]))
        XCTAssertEqual(a.outcome, .regression)
    }

    func testSkippedExercisesAreFlaggedAndDeterministic() {
        let flyRx = ExercisePrescription(name: V2.fly, muscleGroup: "Chest",
                                         sets: [PrescribedSet(role: .straight, weight: 160, reps: 10, rir: 2, restSeconds: 90)])
        let a = V2.analyze("95x10@5, 150x10@2, 185x7@1, 170x8@2", prescription: [V2.benchPrescription, flyRx])
        XCTAssertEqual(a.skipped, [V2.fly])
        XCTAssertTrue(SessionAnalyzer.mandatoryFlags(a).contains("Skipped: \(V2.fly)"))
        XCTAssertEqual(a, V2.analyze("95x10@5, 150x10@2, 185x7@1, 170x8@2", prescription: [V2.benchPrescription, flyRx]))
    }

    func testPromptLineSaysPrescribedVsActual() throws {
        let line = try bench(V2.analyze(missedByOne, energy: 3)).promptLine
        XCTAssertTrue(line.contains("TOP SET MISSED by 1 rep"), line)
        XCTAssertTrue(line.contains("185x7@1"), line)
        XCTAssertTrue(line.contains("retry"), line)
    }

    // MARK: Merging the model's words with the rules

    private func model(_ json: String) throws -> ModelReview {
        try XCTUnwrap(ModelReview.parse(json))
    }

    func testModelCannotHideAMissOrDodgeARepeatRule() throws {
        let analysis = V2.analyze(missedByOne, energy: 3, previous: [V2.review(V2.bench, outcome: .missed)])
        let m = try model("""
        {"exercises":[{"name":"\(V2.bench)","notes":"Great set!","outcome":"pr",
          "next_target":{"weight":200,"reps":8,"note":"go heavy"},
          "miss":{"cause":"lowEnergy","decision":"retry","reason":"bad day"}}],
         "overall_read":"Strong.","recurring_flags":["Rear delts skipped"]}
        """)
        let r = SessionAnalyzer.merge(analysis, model: m, workoutType: "Push")
        let ex = try XCTUnwrap(r.exercises.first)
        XCTAssertEqual(ex.outcome, .missed)
        XCTAssertEqual(ex.missAnalysis?.decision, .reduceAndRebuild, "a repeat miss is never a retry")
        XCTAssertLessThan(ex.nextTarget?.weight ?? 999, 185)
        XCTAssertEqual(ex.notes, "Great set!")
        XCTAssertEqual(r.overallRead, "Strong.")
        XCTAssertTrue(r.recurringFlags.contains("Rear delts skipped"))
        XCTAssertTrue(r.recurringFlags.contains { $0.contains("two sessions in a row") })
        XCTAssertTrue(r.aiAuthored)
    }

    func testModelCanRefineAnAmbiguousMissAndItsTargetFollowsTheDecision() throws {
        let analysis = V2.analyze(missedByOne, energy: 6)   // rules: unknown -> retry
        let m = try model("""
        {"exercises":[{"name":"\(V2.bench)","outcome":"missed","miss":{"cause":"strengthLoss","decision":"reduceAndRebuild","reason":"Third heavy week"}}]}
        """)
        let ex = try XCTUnwrap(SessionAnalyzer.merge(analysis, model: m, workoutType: "Push").exercises.first)
        XCTAssertEqual(ex.missAnalysis?.decision, .reduceAndRebuild)
        XCTAssertEqual(ex.missAnalysis?.reason, "Third heavy week")
        XCTAssertEqual(ex.nextTarget?.weight, 175)
    }

    func testInsaneModelTargetsAreReplacedByTheRules() throws {
        let analysis = V2.analyze("95x10@5, 150x10@2, 185x7@1, 170x8@2")
        for bad in [#"{"weight":300,"reps":8}"#, #"{"weight":120,"reps":8}"#, #"{"weight":190,"reps":99}"#] {
            let m = try model(#"{"exercises":[{"name":"\#(V2.bench)","next_target":\#(bad)}]}"#)
            let ex = try XCTUnwrap(SessionAnalyzer.merge(analysis, model: m, workoutType: "Push").exercises.first)
            XCTAssertEqual(ex.nextTarget, analysis.exercises.first?.target, bad)
        }
        let ok = try model(#"{"exercises":[{"name":"\#(V2.bench)","next_target":{"weight":190,"reps":6,"note":"make the jump"}}]}"#)
        let good = try XCTUnwrap(SessionAnalyzer.merge(analysis, model: ok, workoutType: "Push").exercises.first)
        XCTAssertEqual(good.nextTarget, NextTarget(weight: 190, reps: 6, note: "make the jump"))
    }

    func testNoModelReplyStillGivesAFullReview() throws {
        let analysis = V2.analyze(missedByOne, energy: 3)
        let r = SessionAnalyzer.merge(analysis, model: nil, workoutType: "Push", now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertFalse(r.aiAuthored)
        XCTAssertEqual(r.exercises.first?.missAnalysis?.decision, .retry)
        XCTAssertEqual(r.exercises.first?.nextTarget?.weight, 185)
        XCTAssertTrue(r.overallRead.contains("Push"))
        XCTAssertFalse(r.exercises.first?.notes.isEmpty ?? true)
    }

    func testModelReplyParsingIsLenient() throws {
        let fenced = "```json\n{\"exercises\":[{\"name\":\"Bench\",\"outcome\":\"HOLD\",\"next_target\":{\"weight\":\"185\",\"reps\":\"8\"}}],\"overall_read\":\"ok\",\"recurring_flags\":[\"a\",5]}\n```"
        let m = try XCTUnwrap(ModelReview.parse(fenced))
        XCTAssertEqual(m.exercises.first?.outcome, .hold)
        XCTAssertEqual(m.exercises.first?.nextTarget, NextTarget(weight: 185, reps: 8, note: nil))
        XCTAssertEqual(m.recurringFlags, ["a", "5"])
        // The old reply shape still yields an overall read.
        XCTAssertEqual(ModelReview.parse(#"{"note":"Solid.","summary":"x"}"#)?.overallRead, "Solid.")
        XCTAssertNil(ModelReview.parse("not json"))
        XCTAssertNil(ModelReview.parse(#"{"unrelated":1}"#))
        XCTAssertEqual(WorkoutSessionService.modelReview(from: "Nice work today.")?.overallRead, "Nice work today.")
        XCTAssertNil(WorkoutSessionService.modelReview(from: "{broken"))
    }

    func testRollingSummaryComesFromTheReview() {
        let review = SessionReview(exercises: [], overallRead: "Bench missed by one.", recurringFlags: ["Rear delts skipped"])
        let text = SessionAnalyzer.rollingSummary(review: review, workoutType: "Push", previous: "Earlier note")
        XCTAssertTrue(text.hasPrefix("Push: Bench missed by one."))
        XCTAssertTrue(text.contains("Flags: Rear delts skipped"))
        XCTAssertTrue(text.contains("Earlier: Earlier note"))
        XCTAssertLessThanOrEqual(text.count, 700)
    }
}

// MARK: - Plan review and prompts

final class CoachPlanReviewTests: XCTestCase {

    func testReviewParsesAndSkipsBrokenChanges() throws {
        let reply = """
        {"review":{"verdict":"adjusted","summary":"Rear delts were missing.","changes":[
          {"type":"add","exercise":"Face Pull","detail":"2 sets","reason":"no rear delts"},
          {"type":"loadAdjust","exercise":"Barbell Row","detail":"-10%","reason":"tired","percent":"-10"},
          {"type":"nonsense","exercise":"x"},{"type":"drop"}]},
         "exercises":[{"name":"Barbell Row","muscle_group":"Back","cue":"Ribs down"},
                      {"name":"Face Pull","muscle_group":"Rear Delts",
                       "set_targets":[{"weight":"40","reps":"15","rir":"2"},{"weight":"40","reps":"15","rir":"1"}]}]}
        """
        let review = try XCTUnwrap(CoachPlanReview.parse(fromReply: reply))
        XCTAssertEqual(review.verdict, .adjusted)
        XCTAssertEqual(review.changes.map(\.type), [.add, .loadAdjust])
        XCTAssertEqual(review.changes[1].percent, -10)
        XCTAssertNil(CoachPlanReview.parse(fromReply: #"{"exercises":[]}"#))

        // The same reply still parses as a plan, with the cue, and without "sets" on kept exercises.
        let plan = try XCTUnwrap(WorkoutSessionService.plan(fromPlanJSON: reply, workoutId: UUID(), sanitizeLabel: { $0 }))
        XCTAssertEqual(plan.exercises.map(\.name), ["Barbell Row", "Face Pull"])
        XCTAssertEqual(plan.exercises[0].targetSets, 3)
        XCTAssertEqual(plan.cues[plan.exercises[0].id], "Ribs down")
        XCTAssertEqual(plan.setTargets[plan.exercises[1].id]?.count, 2)
    }

    func testCueAndReviewEditsReachThePlan() {
        let wid = UUID()
        let e = Exercise.create(workoutId: wid, name: V2.bench, muscleGroup: "Chest", orderIndex: 0, targetSets: 3,
                                targetReps: nil, targetRir: nil, restSeconds: nil, coachNote: "Target: 230 lbs — Drive your feet")
        let parsed = WorkoutSessionService.ParsedPlan(exercises: [e], setTargets: [:], cues: [e.id: "Elbows at 45 degrees"])
        let applied = PlanProgressionApplier.apply(plan: parsed, history: V2.history, energy: 6, feedback: nil)
        XCTAssertEqual(applied.exercises[0].coachNoteParts.message, "Drive your feet Cue: Elbows at 45 degrees")
        XCTAssertEqual(applied.exercises[0].coachNoteParts.weight, "185 lbs")
    }

    func testPromptsCarryTheChecklistAndTheJSONSchema() {
        let service = CoachPromptService(validationService: ValidationService())
        let system = service.buildSystemPrompt(profile: nil, task: .plan)
        for needle in ["REVIEW THE DRAFT", "heavy compounds first", "6-10 hard sets", "rear delts", "reorder|swap|drop|add|setCount|loadAdjust",
                       "\"verdict\"", "\"cue\"", "WORKOUT PLAN FORMAT"] {
            XCTAssertTrue(system.contains(needle), "missing \(needle)")
        }
        let post = service.buildSystemPrompt(profile: nil, task: .postWorkout)
        for needle in ["next_target", "retry", "reduceAndRebuild", "holdOrSwap", "recurring_flags"] {
            XCTAssertTrue(post.contains(needle), "missing \(needle)")
        }
    }

    func testPlanMessageSendsDraftReviewsRecencyFocusAndConstraints() throws {
        let service = CoachPromptService(validationService: ValidationService())
        let draftResult = try XCTUnwrap(ProgressionEngine.plan(ProgressionInput(name: V2.bench, sessions: V2.benchHistory,
                                                                                best: HistorySet(230, 1), allowWarmups: true)))
        let now = V2.day(10, 21)
        let extras = CoachPromptService.PlanPromptExtras(
            focus: .strength, constraints: "incline smith not available",
            draft: [DraftExercise(name: V2.bench, muscleGroup: "Chest", result: draftResult)], estimatedMinutes: 38,
            reviews: [V2.review(V2.bench, outcome: .missed, miss: MissAnalysis(cause: .lowEnergy, decision: .retry, reason: "bad day"))],
            recency: ["chest": MuscleRecency(lastTrained: now.addingTimeInterval(-36 * 3600), hardSets: 8)], now: now)
        let message = service.buildWorkoutRequestMessage(workoutType: "Push", time: 45, energy: 6, notes: nil, coach: extras)
        for needle in ["Focus: strength", "Constraints: incline smith not available", "DRAFT PLAN", "top set 185x7@1",
                       "DAYS SINCE EACH MUSCLE", "chest: 1.5 d (8 hard sets)", "PREVIOUS REVIEWS", "missed [lowEnergy -> retry]",
                       "rear delts skipped", "~38 min", "Review the DRAFT PLAN"] {
            XCTAssertTrue(message.contains(needle), "missing \(needle)\n\(message)")
        }
    }

    func testPostWorkoutMessageSendsPrescribedVsActualAndPastReviews() throws {
        let service = CoachPromptService(validationService: ValidationService())
        let ex = Exercise.create(workoutId: UUID(), name: V2.bench, muscleGroup: "Chest", orderIndex: 0,
                                 targetSets: 4, targetReps: nil, targetRir: nil, restSeconds: nil, coachNote: nil)
        let logged = [95.0, 150, 185, 170].enumerated().map { i, w in
            WorkoutSet.create(exerciseId: ex.id, setNumber: i + 1, weightLbs: w, reps: i == 2 ? 6 : 8, rir: 1)
        }
        let analysis = V2.analyze("95x8@1, 150x8@1, 185x6@1, 170x8@1", energy: 4, note: "slept badly")
        let message = service.buildPostWorkoutMessage(
            workoutType: "Push", exercises: [ex], sets: [ex.id: logged], analysis: analysis,
            previousReviews: [V2.review(V2.bench, outcome: .hold)], userNote: "slept badly")
        for needle in ["completed sets", "PRESCRIBED vs ACTUAL", "TOP SET MISSED by 1 rep", "Energy today: 4/10",
                       "Athlete note: slept badly", "PREVIOUS REVIEWS", "Return the review JSON"] {
            XCTAssertTrue(message.contains(needle), "missing \(needle)\n\(message)")
        }
    }
}

// MARK: - In-session adjuster

final class InSessionAdjusterTests: XCTestCase {

    private var prescribed: [SetTarget] {
        ProgressionEngine.plan(ProgressionInput(name: V2.bench, sessions: V2.benchHistory, best: HistorySet(230, 1),
                                                allowWarmups: true))?.sets.map(\.setTarget) ?? []
    }
    private func logged(_ text: String) -> [HistorySet] { V2.sets(text) }

    func testPrescribedSetsAreWarmupSet1TopBackoff() {
        XCTAssertEqual(prescribed.map(\.prefillWeight), ["95", "150", "185", "170"])
        XCTAssertEqual(prescribed.map(\.resolvedRole), [.warmup, .ramp, .top, .backoff])
    }

    func testTopSetShortLowersTheBackoffByTenPercent() throws {
        let s = try XCTUnwrap(InSessionAdjuster.evaluate(prescribed: prescribed, logged: logged("95x10@5, 150x10@2, 185x4@1")))
        XCTAssertEqual(s.role, .top)
        XCTAssertEqual(s.triggerIndex, 2)
        XCTAssertEqual(s.triggerLoggedIndex, 2)
        XCTAssertEqual(s.shortBy, 3)
        XCTAssertEqual(s.changes.count, 1)
        XCTAssertEqual(s.changes.first?.index, 3)
        XCTAssertEqual(s.changes.first?.previousWeight, 170)
        XCTAssertEqual(s.changes.first?.weight, 150, "170 -10% = 153, rounded down to the plate step")
        XCTAssertEqual(s.changes.first?.reps, 8)
        XCTAssertFalse(s.question.isEmpty)
        XCTAssertEqual(s.reasons, MissReason.allCases)
    }

    func testFirstWorkingSetShortLowersTopAndBackoff() throws {
        let s = try XCTUnwrap(InSessionAdjuster.evaluate(prescribed: prescribed, logged: logged("95x10@5, 150x7@1")))
        XCTAssertEqual(s.role, .ramp)
        XCTAssertEqual(s.changes.map(\.index), [2, 3])
        XCTAssertEqual(s.changes.map(\.weight), [175, 150])
        XCTAssertTrue(s.message.contains("175"))
    }

    func testRIRZeroWhenOneWasPlannedTriggers() throws {
        let s = try XCTUnwrap(InSessionAdjuster.evaluate(prescribed: prescribed, logged: logged("95x10@5, 150x10@2, 185x7@0")))
        XCTAssertTrue(s.rirZero)
        XCTAssertEqual(s.shortBy, 0)
        XCTAssertEqual(s.changes.map(\.index), [3])
    }

    func testNoSuggestionForSmallMissesOrWhenTheAthleteAlreadyAdjusted() {
        XCTAssertNil(InSessionAdjuster.evaluate(prescribed: prescribed, logged: logged("95x10@5, 150x9@1")), "one rep short is noise")
        XCTAssertNil(InSessionAdjuster.evaluate(prescribed: prescribed, logged: logged("95x10@5, 150x10@2, 185x7@1")))
        XCTAssertNil(InSessionAdjuster.evaluate(prescribed: prescribed, logged: logged("95x10@5, 140x5@1")), "already went lighter")
        XCTAssertNil(InSessionAdjuster.evaluate(prescribed: prescribed, logged: []))
        XCTAssertNil(InSessionAdjuster.evaluate(prescribed: [], logged: logged("100x5@1")))
    }

    func testWarmupSkippedInTheLogStillLinesUp() throws {
        let s = try XCTUnwrap(InSessionAdjuster.evaluate(prescribed: prescribed, logged: logged("150x7@1")))
        XCTAssertEqual(s.triggerIndex, 1)
        XCTAssertEqual(s.triggerLoggedIndex, 0)
        XCTAssertEqual(s.changes.map(\.index), [2, 3])
    }

    func testIsolationStraightSetsAndDeterminism() throws {
        let fly = ProgressionEngine.plan(ProgressionInput(name: V2.fly, sessions: V2.flyHistory))?.sets.map(\.setTarget) ?? []
        XCTAssertEqual(fly.count, 2)
        let s = try XCTUnwrap(InSessionAdjuster.evaluate(prescribed: fly, logged: logged("160x6@0"), roundingStep: 2.5))
        XCTAssertEqual(s.changes.count, 1)
        XCTAssertEqual(s.changes.first?.weight, 150)
        XCTAssertEqual(s, InSessionAdjuster.evaluate(prescribed: fly, logged: logged("160x6@0"), roundingStep: 2.5))
    }
}

// MARK: - Preferences

final class CoachPreferencesTests: XCTestCase {

    func testFocusResolutionOrder() throws {
        let suite = "coach-prefs-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(CoachPreferences.storedFocus(in: defaults))
        XCTAssertEqual(CoachPreferences.resolvedFocus(in: defaults), .hypertrophy)
        XCTAssertEqual(CoachPreferences.resolvedFocus(profileGoals: ["Get stronger"], in: defaults), .strength)
        XCTAssertEqual(CoachPreferences.resolvedFocus(profileGoals: ["Build muscle", "get strong"], in: defaults), .hypertrophy)
        CoachPreferences.setFocus(.maintenance, in: defaults)
        XCTAssertEqual(CoachPreferences.resolvedFocus(profileGoals: ["Build muscle"], in: defaults), .maintenance)
        XCTAssertEqual(CoachPreferences.resolvedFocus(override: .strength, in: defaults), .strength)
        CoachPreferences.setFocus(nil, in: defaults)
        XCTAssertNil(CoachPreferences.storedFocus(in: defaults))
        XCTAssertEqual(CoachPreferences.neutralEnergy, 6)
    }
}

// MARK: - Draft and storage

final class PlanDraftTests: XCTestCase {

    private func ex(_ name: String, _ muscle: String, _ i: Int) -> Exercise {
        Exercise.create(workoutId: UUID(), name: name, muscleGroup: muscle, orderIndex: i, targetSets: 3,
                        targetReps: nil, targetRir: nil, restSeconds: nil, coachNote: nil)
    }

    func testDraftFollowsTheLastSessionWithHeavyLiftsFirstAndUsesNextTargets() {
        let last = [ex(V2.fly, "Chest", 0), ex(V2.bench, "Chest", 1)]
        let coach = PlanCoachContext(
            focus: .hypertrophy, restPreference: 90,
            nextTargets: [V2.bench.lowercased(): .init(target: NextTarget(weight: 190, reps: 6), date: V2.day(10, 20))],
            recency: [:], now: V2.day(10, 21))
        let draft = PlanDraftBuilder.build(lastSessionExercises: last, history: V2.history, energy: 6, feedback: nil,
                                           coach: coach, timeMinutes: 60)
        XCTAssertEqual(draft.map(\.name), [V2.bench, V2.fly])
        XCTAssertEqual(draft[0].result.topSet?.weight, 190)
        XCTAssertTrue(draft[0].result.usedNextTarget)
        XCTAssertEqual(draft[1].result.sets.count, 2)
        XCTAssertEqual(draft, PlanDraftBuilder.build(lastSessionExercises: last, history: V2.history, energy: 6,
                                                     feedback: nil, coach: coach, timeMinutes: 60))
        // A target from before the last session is stale.
        let stale = PlanCoachContext(nextTargets: [V2.bench.lowercased(): .init(target: NextTarget(weight: 190, reps: 6), date: V2.day(9, 1))])
        XCTAssertNil(stale.nextTarget(for: V2.bench, lastSessionDate: V2.day(10, 20)))
    }

    func testDraftIsTrimmedToTheTimeAvailable() {
        let last = [ex(V2.bench, "Chest", 0), ex(V2.fly, "Chest", 1)]
        let groups = ExerciseHistoryIndex(groups: [
            ExerciseHistoryGroup(names: [V2.bench], sessions: V2.benchHistory, best: nil),
            ExerciseHistoryGroup(names: [V2.fly], sessions: V2.flyHistory, best: nil),
            ExerciseHistoryGroup(names: ["Cable Row Machine"], sessions: [V2.session(10, 20, "160x8@1, 180x5@1")], best: nil),
            ExerciseHistoryGroup(names: ["Lat Pulldown"], sessions: [V2.session(10, 20, "120x10@1, 130x8@1")], best: nil)])
        let many = last + [ex("Cable Row Machine", "Back", 2), ex("Lat Pulldown", "Back", 3)]
        let full = PlanDraftBuilder.build(lastSessionExercises: many, history: groups, energy: 6, feedback: nil,
                                          coach: PlanCoachContext(), timeMinutes: nil)
        let short = PlanDraftBuilder.build(lastSessionExercises: many, history: groups, energy: 6, feedback: nil,
                                           coach: PlanCoachContext(), timeMinutes: 20)
        XCTAssertEqual(full.count, 4)
        XCTAssertLessThan(short.count, full.count)
        XCTAssertGreaterThanOrEqual(short.count, 2)
        let plan = PlanDraftBuilder.parsedPlan(from: short, workoutId: UUID())
        XCTAssertEqual(plan.exercises.map(\.name), short.map(\.name))
    }

    func testPrescriptionFromTargets() {
        let e = ex(V2.bench, "Chest", 0)
        let targets = [e.id: ProgressionEngine.plan(ProgressionInput(name: V2.bench, sessions: V2.benchHistory, allowWarmups: true))?.sets.map(\.setTarget) ?? []]
        let rx = CoachReviewStore.prescription(exercises: [e, ex("No Targets", "Back", 1)], targets: targets)
        XCTAssertEqual(rx.count, 1)
        XCTAssertEqual(rx[0].sets.map(\.role), [.warmup, .ramp, .top, .backoff])
        XCTAssertEqual(rx[0].sets.map(\.restSeconds), [60, 90, 120, 90])
        XCTAssertEqual(rx[0].topSet?.weight, 185)
    }
}

@MainActor
final class CoachReviewStoreTests: XCTestCase {

    private var stack: OutboxTestStack!
    private var workouts: WorkoutRepository!
    private var store: CoachReviewStore!
    private var builder: CoachContextBuilder!

    override func setUp() {
        super.setUp()
        stack = OutboxTestStack()
        workouts = WorkoutRepository(localStorage: stack.storage, offlineQueueManager: stack.queue)
        store = CoachReviewStore(workoutRepository: workouts)
        let profiles = ProfileRepository(localStorage: stack.storage, supabaseService: SupabaseServiceFactory.unreachable(),
                                         offlineQueueManager: stack.queue)
        builder = CoachContextBuilder(profileRepository: profiles, workoutRepository: workouts,
                                      localStorage: stack.storage, validationService: ValidationService())
    }

    @discardableResult
    private func seed(type: String = "Push", hoursAgo: Double, exercise: String = V2.bench, muscle: String = "Chest",
                      sets: [(Double, Int, Int?)] = [(185, 6, 1), (185, 6, 1), (180, 5, 1)],
                      minutes: Int? = nil, note: String? = nil) -> Workout {
        var w = Workout.create(userId: stack.userId, workoutType: type, energyLevel: 6, timeAvailableMinutes: 45)
        w.date = Date(timeIntervalSinceNow: -hoursAgo * 3600)
        w.durationMinutes = minutes
        w.aiProgressionNote = note
        workouts.createWorkout(w)
        let e = Exercise.create(workoutId: w.id, name: exercise, muscleGroup: muscle, orderIndex: 0, targetSets: sets.count,
                                targetReps: nil, targetRir: nil, restSeconds: 90, coachNote: nil)
        workouts.saveExercises([e], workoutId: w.id)
        for (i, s) in sets.enumerated() {
            workouts.saveSet(WorkoutSet.create(exerciseId: e.id, setNumber: i + 1, weightLbs: s.0, reps: s.1, rir: s.2), exerciseId: e.id)
        }
        return w
    }

    private func reviewed(_ w: Workout, outcome: ExerciseOutcome = .hold, target: NextTarget? = nil) {
        let review = SessionReview(
            exercises: [ExerciseReview(name: V2.bench, notes: "n", outcome: outcome, nextTarget: target, missAnalysis: nil)],
            overallRead: "read", recurringFlags: [], createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(store.recordReview(review, for: w.id))
    }

    func testPrescriptionReasonAndReviewAccumulateInOneDocument() throws {
        let w = seed(hoursAgo: 1)
        XCTAssertNil(store.document(forWorkoutId: w.id))
        XCTAssertTrue(store.recordPrescription([V2.benchPrescription], planReview: CoachPlanReview(verdict: .sound, summary: "ok", changes: []), for: w.id))
        XCTAssertTrue(store.recordInSessionReason(exercise: V2.bench, reason: .poorSleep, workoutId: w.id))
        reviewed(w, outcome: .missed, target: NextTarget(weight: 185, reps: 7))
        let doc = try XCTUnwrap(store.document(forWorkoutId: w.id))
        XCTAssertEqual(doc.prescription.first?.topSet?.weight, 185)
        XCTAssertEqual(doc.planReview?.summary, "ok")
        XCTAssertEqual(doc.reason(for: V2.bench), "poorSleep")
        XCTAssertEqual(doc.review?.exercises.first?.outcome, .missed)
        // The stored string is the workout's aiProgressionNote, as plain JSON text.
        let stored = try XCTUnwrap(workouts.fetchWorkout(id: w.id)?.aiProgressionNote)
        XCTAssertEqual(CoachReviewDocument.parse(stored), doc)
        XCTAssertFalse(store.recordInSessionReason(exercise: "x", reason: "y", workoutId: UUID()), "unknown workout")
        // Clearing an answer.
        XCTAssertTrue(store.recordInSessionReason(exercise: V2.bench, reason: "", workoutId: w.id))
        XCTAssertNil(store.document(forWorkoutId: w.id)?.reason(for: V2.bench))
    }

    func testRecordingKeepsALegacyNote() throws {
        let w = seed(hoursAgo: 5, note: "Old plain note.")
        XCTAssertTrue(store.recordInSessionReason(exercise: V2.bench, reason: "tired", workoutId: w.id))
        let doc = try XCTUnwrap(store.document(forWorkoutId: w.id))
        XCTAssertEqual(doc.legacyNote, "Old plain note.")
        XCTAssertEqual(doc.reason(for: V2.bench), "tired")
    }

    func testLatestReviewsAndNextTargets() {
        let oldest = seed(hoursAgo: 24 * 9)
        let middle = seed(hoursAgo: 24 * 6)
        let newest = seed(hoursAgo: 24 * 3)
        let pull = seed(type: "Pull", hoursAgo: 24 * 2, exercise: "Barbell Row", muscle: "Back")
        _ = seed(hoursAgo: 24)   // newest of all, never reviewed
        reviewed(oldest, target: NextTarget(weight: 175, reps: 8))
        reviewed(middle, target: NextTarget(weight: 180, reps: 8))
        reviewed(newest, target: NextTarget(weight: 185, reps: 7))
        reviewed(pull)

        let reviews = store.latestReviews(userId: stack.userId, workoutType: "push", limit: 2)
        XCTAssertEqual(reviews.map(\.workoutId), [newest.id, middle.id])
        XCTAssertTrue(store.latestReviews(userId: stack.userId, workoutType: "Push", limit: 5, excluding: newest.id).allSatisfy { $0.workoutId != newest.id })
        XCTAssertEqual(store.latestReviews(userId: stack.userId, workoutType: "Push", limit: 9).count, 3)
        XCTAssertEqual(store.latestReviews(userId: stack.userId, workoutType: "Pull", limit: 9).map(\.workoutId), [pull.id])

        let targets = store.nextTargets(userId: stack.userId, workoutType: "Push")
        XCTAssertEqual(targets[V2.bench.lowercased()]?.target, NextTarget(weight: 185, reps: 7))
    }

    func testContextCarriesReviewsMuscleRecencyAndMedianSessionLength() throws {
        let push = seed(hoursAgo: 30, minutes: 50)
        _ = seed(type: "Pull", hoursAgo: 24 * 4, exercise: "Barbell Row", muscle: "Back", minutes: 40)
        _ = seed(hoursAgo: 24 * 9, minutes: 60)
        _ = seed(hoursAgo: 24 * 12, minutes: 45)
        reviewed(push, target: NextTarget(weight: 185, reps: 7))

        let ctx = builder.buildContext(userId: stack.userId, workoutType: "Push")
        XCTAssertEqual(ctx.recentReviews.map(\.workoutId), [push.id])
        let chest = try XCTUnwrap(ctx.muscleRecency["chest"])
        XCTAssertTrue(chest.isFresh(now: Date()), "trained 30 h ago with 3 hard sets")
        let back = try XCTUnwrap(ctx.muscleRecency["back"])
        XCTAssertFalse(back.isFresh(now: Date()), "pull day was 4 days ago")
        XCTAssertEqual(ctx.medianSessionMinutes, 50, "median of 50, 60, 45 for the same type")

        // The workout being finished is left out of its own context.
        let other = builder.buildContext(userId: stack.userId, workoutType: "Push", excludingWorkoutId: push.id)
        XCTAssertTrue(other.recentReviews.isEmpty)
        XCTAssertFalse(other.recentSessions.contains { $0.id == push.id })
    }

    func testMedianNeedsTwoSessionsAndIgnoresNonsense() {
        func w(_ minutes: Int?) -> Workout {
            var x = Workout.create(userId: UUID(), workoutType: "Push", energyLevel: nil, timeAvailableMinutes: nil)
            x.durationMinutes = minutes
            return x
        }
        XCTAssertNil(CoachContextBuilder.medianMinutes([], preferring: "Push"))
        XCTAssertNil(CoachContextBuilder.medianMinutes([w(45)], preferring: "Push"))
        XCTAssertEqual(CoachContextBuilder.medianMinutes([w(40), w(50)], preferring: nil), 45)
        XCTAssertEqual(CoachContextBuilder.medianMinutes([w(40), w(50), w(1), w(900), w(nil)], preferring: "Push"), 45)
    }
}
