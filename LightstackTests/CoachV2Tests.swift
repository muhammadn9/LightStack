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
        prescription: [ExercisePrescription]? = nil, now: Date? = nil, hitPR: Bool = false
    ) -> SessionAnalysis {
        SessionAnalyzer.analyze(
            logged: [LoggedExercise(name: bench, muscleGroup: "Chest", sets: sets(logged), hitPR: hitPR)],
            prescription: prescription ?? [benchPrescription], energy: energy, userNote: note, reasons: reasons,
            previous: previous, history: history, focus: .hypertrophy, now: now)
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

    func testSingleMissWithGoodEnergyRetriesInsteadOfCallingItStrengthLoss() throws {
        let a = try bench(V2.analyze(missedByOne, energy: 8))
        XCTAssertEqual(a.miss?.decision, .retry)
        XCTAssertNotEqual(a.miss?.cause, .strengthLoss)
        XCTAssertEqual(a.target?.weight, 185)
        XCTAssertEqual(a.target?.reps, 7)
        // Repeated misses still drop: 185 -7.5%, rounded down to the plate step.
        let repeated = try bench(V2.analyze(missedByOne, energy: 8, previous: [V2.review(V2.bench, outcome: .missed)]))
        XCTAssertEqual(repeated.miss?.cause, .strengthLoss)
        XCTAssertEqual(repeated.miss?.decision, .reduceAndRebuild)
        XCTAssertEqual(repeated.target?.weight, 170)
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

    // MARK: Strength-loss rule, rebuild after a break, PR snapshot

    private let lighter = "95x10@5, 150x10@2, 170x8@1"

    private var skippedHistory: ExerciseHistoryIndex {
        var g = ExerciseHistoryGroup(names: [V2.bench], sessions: V2.benchHistory, best: HistorySet(230, 1))
        g.latestSessionDate = V2.day(10, 24)   // a newer Push session without the bench
        return ExerciseHistoryIndex(groups: [g])
    }

    func testClassifyMissSingleMissIsRetryRepeatedOrTooHeavyIsReduce() {
        func classify(shortBy: Int = 1, energy: Int, reason: MissReason? = nil, repeated: Bool = false) -> MissAnalysis {
            SessionAnalyzer.classifyMiss(shortBy: shortBy, energy: energy, reason: reason, note: nil,
                                         repeated: repeated, pain: false)
        }
        XCTAssertEqual(classify(energy: 8).decision, .retry)
        XCTAssertEqual(classify(energy: 10).decision, .retry)
        XCTAssertNotEqual(classify(energy: 8).cause, .strengthLoss)
        XCTAssertEqual(classify(energy: 8, repeated: true).decision, .reduceAndRebuild)
        XCTAssertEqual(classify(energy: 8, reason: .tooHeavy).decision, .reduceAndRebuild)
        XCTAssertEqual(classify(shortBy: 3, energy: 8).decision, .reduceAndRebuild)
    }

    func testLighterLoadAfterASkippedSessionIsARebuildNotStrengthLoss() throws {
        let a = try bench(V2.analyze(lighter, energy: 8, history: skippedHistory))
        XCTAssertTrue(a.loadDropped)
        XCTAssertEqual(a.miss?.cause, .afterBreak)
        XCTAssertEqual(a.miss?.decision, .retry)
        XCTAssertEqual(a.target?.weight, a.actualTop?.weight, "retry from today's actual top")
        XCTAssertLessThan(a.target?.weight ?? 999, 185)
        XCTAssertEqual(a.target?.note, "Rebuild from today's weight")
        // Same session without the break is a real shortfall.
        let control = try bench(V2.analyze(lighter, energy: 8))
        XCTAssertEqual(control.miss?.cause, .strengthLoss)
        XCTAssertEqual(control.miss?.decision, .reduceAndRebuild)
    }

    func testLighterLoadAfterALongGapIsARebuild() throws {
        let gap = try bench(V2.analyze(lighter, energy: 8, now: V2.day(11, 10)))   // last bench 10/20
        XCTAssertEqual(gap.miss?.cause, .afterBreak)
        XCTAssertEqual(gap.target?.weight, gap.actualTop?.weight)
        let recent = try bench(V2.analyze(lighter, energy: 8, now: V2.day(10, 25)))
        XCTAssertEqual(recent.miss?.cause, .strengthLoss)
    }

    func testModelCannotTurnARebuildIntoStrengthLoss() throws {
        let analysis = V2.analyze(lighter, energy: 8, history: skippedHistory)
        let m = try XCTUnwrap(ModelReview.parse("""
        {"exercises":[{"name":"\(V2.bench)","miss":{"cause":"strengthLoss","decision":"reduceAndRebuild","reason":"lost it"}}]}
        """))
        let ex = try XCTUnwrap(SessionAnalyzer.merge(analysis, model: m, workoutType: "Push").exercises.first)
        XCTAssertEqual(ex.missAnalysis?.cause, .afterBreak)
        XCTAssertEqual(ex.missAnalysis?.decision, .retry)
        XCTAssertEqual(ex.nextTarget?.weight, analysis.exercises.first?.actualTop?.weight)
    }

    func testPRIsJudgedAgainstTheRecordFromBeforeToday() throws {
        // The stored record was already overwritten mid-workout by today's 190x7.
        let overwritten = ExerciseHistoryIndex(groups: [
            ExerciseHistoryGroup(names: [V2.bench], sessions: V2.benchHistory, best: HistorySet(190, 7))])
        let session = "95x10@5, 150x10@2, 190x7@1, 170x8@2"
        XCTAssertEqual(try bench(V2.analyze(session, history: overwritten, hitPR: true)).outcome, .pr)
        XCTAssertNotEqual(try bench(V2.analyze(session, history: overwritten, hitPR: false)).outcome, .pr,
                          "no PR flag and a record equal to today's set: nothing new")
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
        XCTAssertTrue(r.overallRead.contains("missed"), "a rosy read cannot hide a rule-detected miss")
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
        let applied = PlanProgressionApplier.apply(plan: parsed, history: V2.history, energy: 6, feedback: nil,
                                                   coach: PlanCoachContext(now: V2.day(10, 21)))
        XCTAssertEqual(applied.exercises[0].coachNoteParts.message, "Drive your feet Cue: Elbows at 45 degrees")
        XCTAssertEqual(applied.exercises[0].coachNoteParts.weight, "185 lbs")
    }

    func testPromptsCarryTheChecklistAndTheJSONSchema() {
        let service = CoachPromptService(validationService: ValidationService())
        let system = service.buildSystemPrompt(profile: nil, task: .plan, aiSetsWeights: false)
        for needle in ["REVIEW THE DRAFT", "heavy compounds first", "6-10 hard sets", "rear delts", "reorder|swap|drop|add|setCount|loadAdjust",
                       "\"verdict\"", "\"cue\"", "WORKOUT PLAN FORMAT"] {
            XCTAssertTrue(system.contains(needle), "missing \(needle)")
        }
        let post = service.buildSystemPrompt(profile: nil, task: .postWorkout)
        for needle in ["next_target", "retry", "reduceAndRebuild", "holdOrSwap", "recurring_flags", "afterBreak"] {
            XCTAssertTrue(post.contains(needle), "missing \(needle)")
        }
        XCTAssertFalse(post.contains("good energy or a second miss"), "one miss with good energy is no longer strength loss")
        XCTAssertTrue(post.contains("single miss"))
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
        let message = service.buildWorkoutRequestMessage(workoutType: "Push", time: 45, energy: 6, notes: nil, coach: extras,
                                                         aiSetsWeights: false)
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
        XCTAssertEqual(s.reasons, MissReason.missCases)
        XCTAssertFalse(s.reasons.contains(.plannedDrop))
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

    // MARK: Lowered weight

    func testDropVersusPreviousSetFiresWithNoPlan() throws {
        let d = try XCTUnwrap(InSessionAdjuster.evaluateDrop(prescribed: [], logged: logged("50x15, 47.5x11@1")))
        XCTAssertEqual(d.loggedIndex, 1)
        XCTAssertEqual(d.previousWeight, 50)
        XCTAssertEqual(d.weight, 47.5)
        XCTAssertFalse(d.fromPlan)
        XCTAssertEqual(d.message, "You dropped to 47.5 lb from 50 lb. What's the reason?")
        XCTAssertEqual(d.reasons.first, .plannedDrop)
    }

    func testDropVersusPlanTargetFires() throws {
        let plan = [SetTarget(weight: "50", reps: "12", rir: "2")]
        let d = try XCTUnwrap(InSessionAdjuster.evaluateDrop(prescribed: plan, logged: logged("47.5x11@1")))
        XCTAssertTrue(d.fromPlan)
        XCTAssertEqual(d.previousWeight, 50)
    }

    func testNoDropWhenWeightIsEqualOrHigher() {
        XCTAssertNil(InSessionAdjuster.evaluateDrop(prescribed: [], logged: logged("50x15, 50x12")))
        XCTAssertNil(InSessionAdjuster.evaluateDrop(prescribed: [], logged: logged("50x15, 55x10")))
        XCTAssertNil(InSessionAdjuster.evaluateDrop(prescribed: [], logged: logged("50x15")))
    }

    func testNoDropForWarmupSets() {
        let plan = [SetTarget(weight: "95", reps: "10", rir: nil, role: .warmup),
                    SetTarget(weight: "150", reps: "8", rir: "2")]
        XCTAssertNil(InSessionAdjuster.evaluateDrop(prescribed: plan, logged: logged("60x10")), "logged set is the planned warm-up")
    }

    func testNoDropForTinyChange() {
        XCTAssertNil(InSessionAdjuster.evaluateDrop(prescribed: [], logged: logged("100x8, 98x8")), "2% is noise")
        XCTAssertNil(InSessionAdjuster.evaluateDrop(prescribed: [], logged: logged("100x8, 0x8")), "zero weight is bodyweight")
    }

    func testPlannedDropIsNotOfferedForMisses() {
        XCTAssertEqual(MissReason.from("plannedDrop"), .plannedDrop)
        XCTAssertFalse(MissReason.missCases.contains(.plannedDrop))
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
        CoachPreferences.setFocus(.maintenance, in: defaults)
        XCTAssertEqual(CoachPreferences.resolvedFocus(in: defaults), .maintenance)
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
                                          coach: PlanCoachContext(now: V2.day(10, 21)), timeMinutes: nil)
        let short = PlanDraftBuilder.build(lastSessionExercises: many, history: groups, energy: 6, feedback: nil,
                                           coach: PlanCoachContext(now: V2.day(10, 21)), timeMinutes: 20)
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

// MARK: - Coach v3: the coach sets the weights, the app keeps wide rails

final class CoachV3Tests: XCTestCase {

    private func set(_ type: String, _ weight: Double, _ reps: Int, _ rir: Int, rest: Int? = 120) -> SetTarget {
        let warm = type == "warmup"
        return SetTarget(weight: String(format: "%g", weight), reps: String(reps), rir: String(rir),
                         isWarmup: warm ? true : nil, role: warm ? .warmup : nil, restSeconds: rest)
    }

    /// Bench: last top 185x6@1 three days ago, recent best e1RM about 237.7 (230x1).
    private func rail(last: HistorySet? = HistorySet(185, 6, rir: 1), days: Int? = 3, best: Double? = 237.7,
                      cls: ExerciseClass = .heavyCompound, focus: CoachFocus = .hypertrophy) -> PlanGuardrails.RailContext {
        PlanGuardrails.RailContext(name: V2.bench, cls: cls, focus: focus, lastTop: last, daysSinceLast: days, capBestE1RM: best)
    }

    private func check(_ sets: [SetTarget], _ ctx: PlanGuardrails.RailContext)
        -> (targets: [SetTarget], verdict: PlanGuardrails.RailVerdict) {
        PlanGuardrails.validateCoachSets(name: V2.bench, targets: sets, ctx: ctx)
    }

    private func rejection(_ verdict: PlanGuardrails.RailVerdict) -> String? {
        if case .rejected(let reason) = verdict { return reason }
        return nil
    }

    // MARK: Rails

    func testRailsAcceptWideTopWeightAndDeriveRoles() {
        let sets = [set("warmup", 95, 8, 4, rest: 60), set("work", 165, 8, 2), set("work", 200, 5, 1), set("work", 185, 8, 2)]
        let result = check(sets, rail())
        XCTAssertEqual(result.verdict, .accepted(softFixes: []))
        XCTAssertEqual(result.targets.map(\.resolvedRole), [.warmup, .ramp, .top, .straight], "no back-off is forced")
        XCTAssertEqual(result.targets.compactMap(\.restSeconds), [60, 120, 120, 120], "the coach's rest stands")
    }

    func testRailRejectsTopWeightMoreThanTenPercentOverTheLastTop() {
        let result = check([set("work", 210, 5, 1), set("work", 185, 6, 2)], rail())
        let reason = rejection(result.verdict)
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason?.contains("203.5") ?? false, reason ?? "")
        XCTAssertEqual(result.targets, [set("work", 210, 5, 1), set("work", 185, 6, 2)], "rejected sets come back untouched")
        XCTAssertEqual(check([set("work", 203, 5, 1)], rail()).verdict, .accepted(softFixes: []))
    }

    func testSmallLiftsMayAlwaysTakeOneIncrement() {
        // 20 lb curl: +10% is 22, but one increment (5) is 25.
        let ctx = PlanGuardrails.RailContext(name: "Dumbbell Curl", cls: .isolation, focus: .hypertrophy,
                                             lastTop: HistorySet(20, 10, rir: 2), daysSinceLast: 4, capBestE1RM: nil)
        let limit = PlanGuardrails.coachTopLimit(ctx)?.limit ?? 0
        XCTAssertGreaterThanOrEqual(limit, 20 + ExerciseTraits.increment("Dumbbell Curl"))
    }

    func testGapWindowsTightenTheTopWeight() {
        // Same comparison as the engine: more than 14 days holds, more than 28 days comes back lighter.
        XCTAssertEqual(check([set("work", 200, 5, 1)], rail(days: 14)).verdict, .accepted(softFixes: []))
        XCTAssertNotNil(rejection(check([set("work", 190, 5, 1)], rail(days: 15)).verdict))
        XCTAssertNotNil(rejection(check([set("work", 190, 5, 1)], rail(days: 28)).verdict))
        XCTAssertEqual(check([set("work", 185, 6, 2)], rail(days: 28)).verdict, .accepted(softFixes: []))
        XCTAssertNotNil(rejection(check([set("work", 185, 6, 2)], rail(days: 29)).verdict))
        XCTAssertEqual(check([set("work", 175, 6, 2)], rail(days: 29)).verdict, .accepted(softFixes: []))
        XCTAssertEqual(ProgressionEngine.holdAfterDays, 14)
        XCTAssertEqual(ProgressionEngine.layoffAfterDays, 28)
    }

    func testRailRejectsAnE1RMOverTheRecentBestPlusFivePercent() {
        let noLast = rail(last: nil, days: nil, best: 240)
        // 200x10 estimates 266.7, over 252.
        let high = check([set("work", 200, 10, 1)], noLast)
        XCTAssertTrue(rejection(high.verdict)?.contains("one-rep max") ?? false, "\(high.verdict)")
        XCTAssertEqual(check([set("work", 200, 6, 1)], noLast).verdict, .accepted(softFixes: []))
    }

    func testRailRejectsAWorkWeightUnderHalfTheLastTopAtHardEffort() {
        let result = check([set("work", 60, 10, 2), set("work", 60, 10, 1)], rail())
        XCTAssertTrue(rejection(result.verdict)?.contains("half") ?? false, "\(result.verdict)")
        // A light set at easy effort is fine.
        XCTAssertEqual(check([set("work", 90, 12, 4), set("work", 185, 6, 1)], rail()).verdict, .accepted(softFixes: []))
    }

    func testGoalAllowanceHookIsNilAndRaisesOnlyTheTenPercentCeiling() {
        XCTAssertNil(rail().goalAllowance)
        var ctx = rail()
        ctx.goalAllowance = 215
        XCTAssertEqual(check([set("work", 210, 5, 1)], ctx).verdict, .accepted(softFixes: []))
        ctx.daysSinceLast = 20
        XCTAssertNotNil(rejection(check([set("work", 210, 5, 1)], ctx).verdict), "gap rules still win")
    }

    func testSoftFixesClampInsteadOfRejecting() {
        let sets = [set("warmup", 20, 10, 5, rest: 60), set("warmup", 40, 10, 5, rest: 60), set("warmup", 60, 8, 4, rest: 60),
                    set("warmup", 80, 6, 3, rest: 60), set("warmup", 100, 5, 3, rest: 60),
                    set("work", 100, 45, 7, rest: 10), set("work", 100, 8, 0), set("work", 100, 8, 0),
                    set("work", 100, 8, 2, rest: 900), set("work", 100, 8, 2), set("work", 100, 8, 2)]
        let result = check(sets, rail(last: nil, days: nil, best: nil))
        guard case .accepted(let fixes) = result.verdict else { return XCTFail("expected accepted, got \(result.verdict)") }
        XCTAssertFalse(fixes.isEmpty)
        let warm = result.targets.filter { $0.isWarmup == true }
        let work = result.targets.filter { $0.isWarmup != true }
        XCTAssertEqual(warm.map(\.prefillWeight), ["40", "60", "80"], "none at the working weight, at most 3, heaviest kept")
        XCTAssertEqual(work.count, 5)
        XCTAssertEqual(work[0].prefillReps, "30")
        XCTAssertEqual(work.map(\.prefillRir), ["5", "1", "0", "2", "2"], "RIR 0-5, a single RIR 0")
        XCTAssertEqual(work[0].restSeconds, 30)
        XCTAssertEqual(work[3].restSeconds, 300)
        // Strength focus may rest up to 360 s.
        let strength = check(sets, rail(last: nil, days: nil, best: nil, focus: .strength))
        XCTAssertEqual(strength.targets.filter { $0.isWarmup != true }[3].restSeconds, 360)
    }

    func testRolesAreDerivedByTheApp() {
        func roles(_ sets: [SetTarget], isolation: Bool = false) -> [SetRole] {
            PlanGuardrails.assignCoachRoles(sets, isolation: isolation).map(\.resolvedRole)
        }
        XCTAssertEqual(roles([set("work", 150, 10, 2), set("work", 190, 5, 1)]), [.ramp, .top])
        XCTAssertEqual(roles([set("work", 175, 8, 2), set("work", 190, 5, 1)]), [.straight, .top], "175 is within 10% of 190")
        XCTAssertEqual(roles([set("work", 100, 8, 2), set("work", 100, 8, 2)]), [.top, .straight])
        XCTAssertEqual(roles([set("work", 30, 12, 2), set("work", 30, 12, 1)], isolation: true), [.straight, .straight])
    }

    // MARK: Applier

    private func applyCoach(_ sets: [SetTarget], reason: String? = "Last 185x6@1, e1RM up.", now: Date = V2.day(10, 21),
                            aiSetsWeights: Bool = true) -> (AppliedPlan, Exercise) {
        let e = Exercise.create(workoutId: UUID(), name: V2.bench, muscleGroup: "Chest", orderIndex: 0, targetSets: 3,
                                targetReps: nil, targetRir: nil, restSeconds: nil, coachNote: nil)
        var parsed = WorkoutSessionService.ParsedPlan(exercises: [e], setTargets: [e.id: sets])
        parsed.coachSetIds = [e.id]
        if let reason { parsed.reasons = [e.id: reason] }
        let applied = PlanProgressionApplier.apply(
            plan: parsed, history: V2.history, energy: 6, feedback: nil,
            coach: PlanCoachContext(now: now), aiSetsWeights: aiSetsWeights)
        return (applied, e)
    }

    func testApplierKeepsTheCoachsSetsWithoutForcingABackoffOrFivePercent() throws {
        let (applied, e) = applyCoach([set("warmup", 95, 8, 4, rest: 60), set("work", 150, 10, 2, rest: 90), set("work", 195, 5, 1, rest: 150)])
        let targets = try XCTUnwrap(applied.setTargets[e.id])
        XCTAssertEqual(targets.map(\.resolvedRole), [.warmup, .ramp, .top])
        XCTAssertEqual(targets.map(\.prefillWeight), ["95", "150", "195"], "195 is over +5% (194.25) but inside the +10% rail")
        let evidence = try XCTUnwrap(applied.evidence[e.id])
        XCTAssertEqual(evidence.source, .coach)
        XCTAssertEqual(evidence.rationale, "Last 185x6@1, e1RM up.")
        XCTAssertEqual(evidence.warmupCount, 1)
        XCTAssertEqual(applied.reasons, [CoachExerciseReason(exercise: V2.bench, railFallback: false, text: "Last 185x6@1, e1RM up.")])
        XCTAssertEqual(applied.exercises[0].coachNoteParts.weight, "195 lbs")
        XCTAssertEqual(applied.exercises[0].restSeconds, 150)
    }

    func testCoachStraightSetsAtOneWeightAreNotCappedButEngineSetsStillAre() throws {
        let (applied, e) = applyCoach([set("work", 100, 8, 2), set("work", 100, 8, 2), set("work", 100, 8, 1)])
        XCTAssertEqual(applied.setTargets[e.id]?.map(\.prefillWeight), ["100", "100", "100"])
        let capped = PlanGuardrails.capHeavySets((0..<4).map { _ in set("work", 200, 5, 2) }, step: 5)
        XCTAssertTrue(capped.changed, "the cap still exists for engine and fallback sets")
    }

    func testRejectedExerciseGetsTheEnginePlanWithTheRailInItsEvidence() throws {
        let (applied, e) = applyCoach([set("work", 150, 10, 2), set("work", 215, 5, 1)])
        let targets = try XCTUnwrap(applied.setTargets[e.id])
        XCTAssertEqual(targets.map(\.resolvedRole), [.warmup, .ramp, .top, .backoff], "the engine's baseline")
        XCTAssertEqual(targets.map(\.prefillWeight), ["95", "150", "185", "170"])
        let evidence = try XCTUnwrap(applied.evidence[e.id])
        XCTAssertEqual(evidence.source, .engineFallback)
        XCTAssertTrue(evidence.rationale.hasPrefix("Safety rail:"), evidence.rationale)
        XCTAssertTrue(applied.safeguards.contains { $0.contains("safety rail") }, "\(applied.safeguards)")
        XCTAssertEqual(applied.reasons.first?.railFallback, true)
        XCTAssertEqual(applied.reasons.first?.label, "Safety rail: rule-based")
    }

    func testRailsUseTheGapBetweenTodayAndTheLastSession() throws {
        // 21 days after 10/20: no increase, so 190 is rejected and the engine holds 185.
        let (applied, e) = applyCoach([set("work", 150, 10, 2), set("work", 190, 5, 1)], now: V2.day(11, 10))
        XCTAssertEqual(applied.evidence[e.id]?.source, .engineFallback)
    }

    func testRollbackSwitchIgnoresTheCoachsNumbers() throws {
        let (applied, e) = applyCoach([set("work", 150, 10, 2), set("work", 200, 5, 1)], aiSetsWeights: false)
        XCTAssertEqual(applied.evidence[e.id]?.source, .engine)
        XCTAssertTrue(applied.reasons.isEmpty)
    }

    func testNewExerciseWithoutHistoryKeepsCoachSetsAfterTheExistingGuardrails() throws {
        let e = Exercise.create(workoutId: UUID(), name: "Cable Crossover", muscleGroup: "Chest", orderIndex: 0, targetSets: 3,
                                targetReps: nil, targetRir: nil, restSeconds: nil, coachNote: nil)
        var parsed = WorkoutSessionService.ParsedPlan(
            exercises: [e], setTargets: [e.id: [set("warmup", 40, 10, 4, rest: 60), set("work", 40, 10, 3, rest: 75), set("work", 45, 8, 2, rest: 75)]])
        parsed.coachSetIds = [e.id]
        parsed.reasons = [e.id: "New lift: start light."]
        let applied = PlanProgressionApplier.apply(plan: parsed, history: ExerciseHistoryIndex(), energy: 6, feedback: nil,
                                                   coach: PlanCoachContext(now: V2.day(10, 21)))
        let targets = try XCTUnwrap(applied.setTargets[e.id])
        XCTAssertFalse(targets.contains { $0.isWarmup == true }, "a warm-up at the working weight is stripped")
        XCTAssertEqual(targets.compactMap(\.restSeconds), [75, 75], "the coach's rest stands")
        XCTAssertEqual(applied.evidence[e.id]?.source, .aiGuarded)
        XCTAssertEqual(applied.evidence[e.id]?.rationale, "New lift: start light.")
        XCTAssertEqual(applied.reasons.first?.text, "New lift: start light.")
    }

    // MARK: Parsing

    func testNewReplyParsesNumericSetsReasonsAndSummary() throws {
        let reply = """
        {"summary":"Heavy day.","coaching_notes":"x","exercises":[
         {"name":"Barbell Bench Press","muscle_group":"Chest","superset":null,"cue":null,"reason":"Last 185x6@1, e1RM rising.",
          "sets":[{"type":"warmup","weight":95,"reps":8,"rir":4,"rest":60},{"type":"work","weight":150,"reps":10,"rir":2,"rest":90},
                  {"type":"work","weight":190,"reps":5,"rir":1,"rest":150}]}]}
        """
        let plan = try XCTUnwrap(WorkoutSessionService.plan(fromPlanJSON: reply, workoutId: UUID(), sanitizeLabel: { $0 }))
        let bench = try XCTUnwrap(plan.exercises.first)
        XCTAssertEqual(plan.summary, "Heavy day.")
        XCTAssertEqual(plan.reasons[bench.id], "Last 185x6@1, e1RM rising.")
        XCTAssertTrue(plan.coachSetIds.contains(bench.id))
        XCTAssertEqual(bench.targetSets, 3)
        XCTAssertEqual(plan.setTargets[bench.id]?.map(\.resolvedRole), [.warmup, .ramp, .top])
        XCTAssertEqual(plan.setTargets[bench.id]?.compactMap(\.restSeconds), [60, 90, 150])
        XCTAssertEqual(bench.coachNoteParts.weight, "190 lbs")
    }

    func testOldReplyShapesStillParseAndAreNotMarkedAsCoachSets() throws {
        let old = """
        {"review":{"verdict":"sound","summary":"Fine.","changes":[]},
         "exercises":[{"name":"Barbell Row","muscle_group":"Back","cue":"Ribs down","coach_note":"Pull to the hip"},
                      {"name":"Face Pull","muscle_group":"Rear Delts",
                       "set_targets":[{"weight":"40","reps":"15","rir":"2"},{"weight":"40","reps":"15","rir":"1"}]}]}
        """
        let plan = try XCTUnwrap(WorkoutSessionService.plan(fromPlanJSON: old, workoutId: UUID(), sanitizeLabel: { $0 }))
        XCTAssertTrue(plan.coachSetIds.isEmpty)
        XCTAssertTrue(plan.reasons.isEmpty)
        XCTAssertNil(plan.summary)
        XCTAssertEqual(plan.setTargets[plan.exercises[1].id]?.count, 2)
        XCTAssertEqual(CoachPlanReview.parse(fromReply: old)?.summary, "Fine.")
        // The integer form of "sets" still works.
        let counted = try XCTUnwrap(WorkoutSessionService.plan(
            fromPlanJSON: #"{"exercises":[{"name":"Squat","muscle_group":"Legs","sets":4}]}"#, workoutId: UUID(), sanitizeLabel: { $0 }))
        XCTAssertEqual(counted.exercises.first?.targetSets, 4)
        XCTAssertTrue(counted.coachSetIds.isEmpty)
    }

    func testUnparseableReplyStillFallsBackToTheDraft() {
        XCTAssertNil(WorkoutSessionService.plan(fromPlanJSON: "Here is a plan: bench 3x8", workoutId: UUID(), sanitizeLabel: { $0 }))
    }

    // MARK: Switch, store, labels

    func testRollbackSwitchDefaultsToOn() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "coachv3-\(UUID().uuidString)"))
        XCTAssertTrue(CoachPreferences.aiSetsWeights(in: defaults))
        defaults.set(false, forKey: CoachPreferences.aiSetsWeightsKey)
        XCTAssertFalse(CoachPreferences.aiSetsWeights(in: defaults))
    }

    func testOldDebugSnapshotsStillDecode() throws {
        let json = #"{"userId":"u","timestamp":0,"workoutType":"Push","model":"m","systemPromptName":"plan","systemPromptLength":1,"userMessage":"x","adjustments":[]}"#
        let snapshot = try JSONDecoder().decode(CoachPlanSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(snapshot.reasons)
        var withReasons = snapshot
        withReasons.reasons = [CoachExerciseReason(exercise: "Bench", railFallback: true, text: "Safety rail: x")]
        let round = try JSONDecoder().decode(CoachPlanSnapshot.self, from: JSONEncoder().encode(withReasons))
        XCTAssertEqual(round.reasons?.first?.label, "Safety rail: rule-based")
        XCTAssertEqual(CoachExerciseReason(exercise: "Bench", railFallback: false, text: "t").label, "Set by the coach")
    }

    func testEvidenceLabelsNameWhoSetTheNumbers() {
        XCTAssertEqual(EvidenceFormat.sourceTitle(.coach), "Set by the coach")
        XCTAssertEqual(EvidenceFormat.sourceTitle(.engineFallback), "Safety rail: rule-based")
    }
}

// MARK: - Coach v3 goals: assessor, ladder, store, threads

final class GoalAssessorTests: XCTestCase {

    private let bench = "Barbell Bench Press"
    private let now = V2.day(11, 3)

    private func daysAgo(_ days: Int) -> Date { now.addingTimeInterval(-Double(days) * 86_400) }

    /// 185, 190, 195, 200 x3 over the last three weeks: e1RM 203.5, 209, 214.5, 220 (+5.5 a week).
    private var risingBench: [GoalAssessor.Point] {
        [GoalAssessor.Point(date: daysAgo(21), weight: 185, reps: 3),
         GoalAssessor.Point(date: daysAgo(14), weight: 190, reps: 3),
         GoalAssessor.Point(date: daysAgo(7), weight: 195, reps: 3),
         GoalAssessor.Point(date: daysAgo(0), weight: 200, reps: 3)]
    }

    private func assess(_ weight: Double, _ reps: Int = 1, history: [GoalAssessor.Point]? = nil) throws -> GoalAssessor.Assessment {
        try XCTUnwrap(GoalAssessor.assess(exercise: bench, targetWeight: weight, targetReps: reps,
                                          history: history ?? risingBench, now: now))
    }

    func testCurrentE1RMSlopeAndGap() throws {
        let a = try assess(225)
        XCTAssertEqual(a.currentE1RM, 220, accuracy: 0.01)
        XCTAssertEqual(a.targetE1RM, 232.5, accuracy: 0.01)
        XCTAssertEqual(a.weeklySlope, 5.5, accuracy: 0.3)
        XCTAssertEqual(a.gapPercent, 5.68, accuracy: 0.05)
        XCTAssertFalse(a.stale)
    }

    func testWithinThreePercentIsRealisticNow() throws {
        XCTAssertEqual(try assess(215).verdict, .realisticNow)   // gap about 1%
        XCTAssertEqual(try assess(218).verdict, .realisticNow)   // gap about 2.4%
        XCTAssertEqual(try assess(190).verdict, .realisticNow)   // already past it
    }

    func testThreeToTenPercentIsABlockOfWeeks() throws {
        XCTAssertEqual(try assess(220).verdict, .block(weeks: 2))   // gap 3.3%: 7.3 to go at 5.5 a week
        XCTAssertEqual(try assess(225).verdict, .block(weeks: 3))   // gap 5.7%: 12.5 to go
        XCTAssertEqual(try assess(232).verdict, .block(weeks: 4))   // gap 9.0%: 19.7 to go
        XCTAssertGreaterThan(try assess(235).gapPercent, 10)        // just past the block range
        if case .longTerm = try assess(235).verdict {} else { XCTFail("10.4% should be long term") }
    }

    func testBeyondTenPercentIsLongTermWithAnIntermediateGoal() throws {
        let a = try assess(250)
        XCTAssertGreaterThan(a.gapPercent, 10)
        // About 5% over the current e1RM at one rep, on the 5 lb step.
        XCTAssertEqual(a.verdict, .longTerm(intermediateWeight: 225))
    }

    func testFlatTrendFallsBackToAnAssumedGain() throws {
        let flat = [GoalAssessor.Point(date: daysAgo(14), weight: 200, reps: 3),
                    GoalAssessor.Point(date: daysAgo(0), weight: 200, reps: 3)]
        let a = try assess(225, history: flat)
        XCTAssertEqual(a.weeklySlope, 0, accuracy: 0.01)
        guard case .block(let weeks) = a.verdict else { return XCTFail("expected a block, got \(a.verdict)") }
        XCTAssertEqual(weeks, 12)   // 12.5 to go at 0.5% of 220 a week
    }

    func testStaleHistoryStillAssessesButIsFlagged() throws {
        let old = [GoalAssessor.Point(date: daysAgo(70), weight: 200, reps: 3)]
        let a = try assess(225, history: old)
        XCTAssertTrue(a.stale)
        XCTAssertEqual(a.weeklySlope, 0, accuracy: 0.001)
        XCTAssertTrue(GoalAssessor.appCheckLine(a).contains("nothing logged"))
    }

    func testNoHistoryHasNoAssessment() {
        XCTAssertNil(GoalAssessor.assess(exercise: bench, targetWeight: 225, targetReps: 1, history: [], now: now))
        XCTAssertTrue(GoalAssessor.noHistoryLine(exercise: bench, targetWeight: 225, targetReps: 1).hasPrefix("APP CHECK:"))
    }

    func testWarmupLadderForA225Single() {
        let ladder = GoalAssessor.ladder(exercise: bench, weight: 225, reps: 1)
        XCTAssertEqual(ladder.map(\.weight), [90, 135, 170, 190, 205, 225])
        XCTAssertEqual(ladder.map(\.reps), [5, 3, 2, 1, 1, 1])
        XCTAssertEqual(ladder.map(\.isAttempt), [false, false, false, false, false, true])
    }

    func testLadderStartsAtTheBarForLightTargets() {
        let ladder = GoalAssessor.ladder(exercise: bench, weight: 95, reps: 1)
        XCTAssertEqual(ladder.first?.weight, 45)
        XCTAssertEqual(ladder.last?.weight, 95)
        XCTAssertEqual(ladder.last?.isAttempt, true)
        XCTAssertEqual(ladder.map(\.weight), ladder.map(\.weight).sorted())
        XCTAssertEqual(Set(ladder.map(\.weight)).count, ladder.count, "ladder repeats a weight")
    }

    func testLadderRoundsToDumbbellSteps() {
        let ladder = GoalAssessor.ladder(exercise: "Incline Dumbbell Press", weight: 100, reps: 1)
        for step in ladder { XCTAssertEqual(step.weight.truncatingRemainder(dividingBy: 2.5), 0, "\(step.weight)") }
        XCTAssertEqual(ladder.last?.weight, 100)
    }

    func testAppCheckLineStatesTheFacts() throws {
        let line = GoalAssessor.appCheckLine(try assess(225))
        XCTAssertTrue(line.hasPrefix("APP CHECK: \(bench) e1RM 220"), line)
        XCTAssertTrue(line.contains("225x1 = e1RM 233") || line.contains("225x1 = e1RM 232"), line)
        XCTAssertTrue(line.contains("gap 6%"), line)
        XCTAssertTrue(line.contains("not this week"), line)
        let near = GoalAssessor.appCheckLine(try assess(215))
        XCTAssertTrue(near.contains("Warm-up ladder"), near)
        let far = GoalAssessor.appCheckLine(try assess(250))
        XCTAssertTrue(far.contains("intermediate goal"), far)
    }

    func testTopPointsTakeEachSessionsBestWorkingSetNotWarmups() {
        let sessions = [
            HistorySession(date: daysAgo(7), sets: V2.sets("95x8@4, 185x5@2, 200x3@1")),
            HistorySession(date: daysAgo(14), sets: V2.sets("100x5@4, 185x3@2"))
        ]
        let points = GoalAssessor.topPoints(from: sessions)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.first?.weight, 185)          // oldest first
        XCTAssertEqual(points.last?.weight, 200)
        XCTAssertEqual(points.last?.reps, 3)
    }
}

final class CoachGoalStoreTests: XCTestCase {

    private func makeDefaults() throws -> UserDefaults {
        let suite = "coach-goals-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testGoalRoundTripsThroughTheStore() throws {
        let store = CoachGoalStore(defaults: try makeDefaults())
        let user = UUID()
        XCTAssertTrue(store.goals(for: user).isEmpty)

        var goal = CoachGoal(exerciseName: "Barbell Bench Press", targetWeight: 225, targetReps: 1,
                             deadline: CoachGoal.parseDay("2026-12-15"),
                             steps: [CoachGoalStep(date: "2026-12-01", text: "Heavy single 205", weight: 205, reps: 1, attempt: false),
                                     CoachGoalStep(date: "2026-12-15", text: "Attempt 225x1", weight: 225, reps: 1, attempt: true)],
                             assessment: "APP CHECK: x")
        store.add(goal, for: user)

        let loaded = try XCTUnwrap(store.goals(for: user).first)
        XCTAssertEqual(loaded, goal)
        XCTAssertEqual(loaded.targetText, "225x1")
        XCTAssertEqual(loaded.steps.last?.attempt, true)
        XCTAssertEqual(store.activeGoals(for: user).count, 1)

        goal.status = .achieved
        store.update(goal, for: user)
        XCTAssertEqual(store.goals(for: user).first?.status, .achieved)
        XCTAssertTrue(store.activeGoals(for: user).isEmpty)
    }

    func testGoalsAreKeptPerUserAndDroppedGoalsLeaveTheActiveList() throws {
        let store = CoachGoalStore(defaults: try makeDefaults())
        let a = UUID(), b = UUID()
        let first = CoachGoal(exerciseName: "Back Squat", targetWeight: 315, targetReps: 1)
        let second = CoachGoal(exerciseName: "Deadlift", targetWeight: 405, targetReps: 1)
        store.add(first, for: a)
        store.add(second, for: a)
        XCTAssertTrue(store.goals(for: b).isEmpty)
        XCTAssertEqual(store.activeGoals(for: a).map(\.exerciseName), ["Back Squat", "Deadlift"])

        store.setStatus(.dropped, goalId: first.id, for: a)
        XCTAssertEqual(store.activeGoals(for: a).map(\.exerciseName), ["Deadlift"])
        XCTAssertEqual(store.goals(for: a).count, 2, "dropped goals stay in the list")

        store.add(second, for: a)   // same id replaces, never duplicates
        XCTAssertEqual(store.goals(for: a).count, 2)
    }

    func testUpdateIgnoresUnknownGoals() throws {
        let store = CoachGoalStore(defaults: try makeDefaults())
        let user = UUID()
        store.update(CoachGoal(exerciseName: "Back Squat", targetWeight: 315, targetReps: 1), for: user)
        XCTAssertTrue(store.goals(for: user).isEmpty)
    }
}

final class CoachThreadTests: XCTestCase {

    private func makeStore() throws -> CoachThreadStore {
        let suite = "coach-threads-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return CoachThreadStore(defaults: defaults)
    }

    private func exercise(_ name: String, sets: Int = 3) -> Exercise {
        Exercise.create(workoutId: UUID(), name: name, muscleGroup: "Chest", orderIndex: 0,
                        targetSets: sets, targetReps: "8", targetRir: "2", restSeconds: 90, coachNote: nil)
    }

    private func seed(review: SessionReview? = nil) -> ThreadSeed {
        let bench = exercise("Barbell Bench Press")
        let fly = exercise("Cable Fly")
        let targets: [UUID: [SetTarget]] = [
            bench.id: [SetTarget(weight: "95", reps: "8", role: .warmup),
                       SetTarget(weight: "135", reps: "8", rir: "2", role: .top),
                       SetTarget(weight: "135", reps: "8", rir: "1", role: .straight)]
        ]
        return ThreadSeed.build(
            workoutId: UUID(),
            summary: "Good order for a push day.",
            notes: "Controlled reps.",
            exercises: [bench, fly],
            setTargets: targets,
            reasons: [CoachExerciseReason(exercise: "Barbell Bench Press", railFallback: false, text: "Repeat last top set."),
                      CoachExerciseReason(exercise: "Cable Fly", railFallback: true, text: "Capped at last session.")],
            review: review)
    }

    func testPlanMessageHasSummaryNotesReasonsAndTargets() throws {
        let message = try XCTUnwrap(seed().planMessage)
        XCTAssertTrue(message.contains("Good order for a push day."))
        XCTAssertTrue(message.contains("Controlled reps."))
        XCTAssertTrue(message.contains("Barbell Bench Press: 95x8 warm-up, 135x8 @RIR2, 135x8 @RIR1"), message)
        XCTAssertTrue(message.contains("Repeat last top set."))
        XCTAssertTrue(message.contains("Safety rail: Capped at last session."))
        // No prescription: the exercise's own targets are used.
        XCTAssertTrue(message.contains("Cable Fly: 3 sets of 8"), message)
    }

    func testCompactSummaryIsShortAndKeepsTopSets() throws {
        let compact = try XCTUnwrap(seed().compactSummary)
        XCTAssertTrue(compact.contains("Barbell Bench Press (2 sets, top 135x8)"), compact)
        XCTAssertLessThanOrEqual(compact.count, ThreadSeed.compactLimit + 1)
        XCTAssertNil(ThreadSeed(workoutId: UUID(), summary: nil, notes: nil, items: [], reviewText: nil).planMessage)
    }

    func testReviewTextComesFromTheSessionReview() throws {
        let review = SessionReview(
            exercises: [ExerciseReview(name: "Bench", notes: "Hit every target.", outcome: .hold,
                                       nextTarget: NextTarget(weight: 140, reps: 8), missAnalysis: nil)],
            overallRead: "Solid push day.", recurringFlags: [])
        let text = try XCTUnwrap(seed(review: review).reviewText)
        XCTAssertTrue(text.hasPrefix("Workout review: Solid push day."), text)
        XCTAssertTrue(text.contains("Next time: 140 x 8"), text)
        XCTAssertNil(seed().reviewText)
    }

    func testThreadStoreRoundTripKeepsIdsOrderAndFlags() throws {
        let store = try makeStore()
        let workoutId = UUID()
        XCTAssertNil(store.thread(forWorkout: workoutId))

        let messages = [ChatMessage(role: .coach, content: "Plan"), ChatMessage(role: .user, content: "Swap flies?")]
        store.save(StoredChatThread(messages: messages.map(StoredChatMessage.init), planSeeded: true,
                                    reviewAppended: false, updatedAt: Date()), forWorkout: workoutId)

        let loaded = try XCTUnwrap(store.thread(forWorkout: workoutId))
        XCTAssertTrue(loaded.planSeeded)
        XCTAssertFalse(loaded.reviewAppended)
        let restored = loaded.messages.map(\.message)
        XCTAssertEqual(restored.map(\.id), messages.map(\.id))
        XCTAssertEqual(restored.map(\.content), ["Plan", "Swap flies?"])
        XCTAssertEqual(restored.first?.role, .coach)
        XCTAssertEqual(restored.last?.role, .user)
        XCTAssertNil(store.thread(forWorkout: UUID()), "another workout has its own thread")
    }

    func testThreadStoreCapsMessagesLengthAndThreads() throws {
        let store = try makeStore()
        let id = UUID()
        let many = (0..<(CoachThreadStore.maxMessages + 20)).map { ChatMessage(role: .user, content: "m\($0)") }
        let long = ChatMessage(role: .coach, content: String(repeating: "x", count: CoachThreadStore.maxCharacters + 500))
        store.save(StoredChatThread(messages: (many + [long]).map(StoredChatMessage.init), planSeeded: false,
                                    reviewAppended: false, updatedAt: Date()), forWorkout: id)
        let loaded = try XCTUnwrap(store.thread(forWorkout: id))
        XCTAssertEqual(loaded.messages.count, CoachThreadStore.maxMessages)
        XCTAssertEqual(loaded.messages.last?.content.count, CoachThreadStore.maxCharacters + 1)   // text plus "…"

        // The oldest threads are dropped past the cap.
        let ids = (0..<(CoachThreadStore.maxThreads + 3)).map { _ in UUID() }
        for (index, threadId) in ids.enumerated() {
            store.save(StoredChatThread(messages: [StoredChatMessage(ChatMessage(role: .user, content: "t"))],
                                        planSeeded: true, reviewAppended: false,
                                        updatedAt: Date(timeIntervalSince1970: Double(1_000 + index))), forWorkout: threadId)
        }
        XCTAssertNil(store.thread(forWorkout: ids[0]))
        XCTAssertNotNil(store.thread(forWorkout: ids[ids.count - 1]))
    }

    func testHiddenContextIsAppendedOnlyForTheAIAndWindowKeepsTheContextMessage() {
        let context = ChatMessage(role: .user, content: "ctx")
        let ask = ChatMessage(role: .user, content: "225x1 bench")
        var all = [context, ask]
        for i in 0..<10 { all.append(ChatMessage(role: i % 2 == 0 ? .coach : .user, content: "m\(i)")) }
        let windowed = CoachChatViewModel.windowedMessages(all)
        XCTAssertEqual(windowed.count, CoachChatViewModel.historyWindow + 1)
        XCTAssertEqual(windowed.first?.content, "ctx")

        let sent = CoachChatViewModel.withHiddenContext([context, ask], hidden: [ask.id: "APP CHECK: Bench e1RM 221"])
        XCTAssertEqual(sent[0].content, "ctx")
        XCTAssertEqual(sent[1].content, "225x1 bench\n\nAPP CHECK: Bench e1RM 221")
        XCTAssertEqual(ask.content, "225x1 bench", "the visible message is unchanged")
    }

    func testAgreedNotesPreferTheCoachsPlanNotesLineAndStayWithin300() {
        let context = ChatMessage(role: .user, content: "ctx")
        let said = ChatMessage(role: .user, content: "my left shoulder is sore")
        let reply = ChatMessage(role: .coach, content: "Got it.\nPlan notes: Left shoulder sore, no overhead pressing.")
        XCTAssertEqual(CoachChatViewModel.agreedNotes(from: [context, said, reply]),
                       "Left shoulder sore, no overhead pressing.")
        // Without a coach line it is what the athlete said.
        XCTAssertEqual(CoachChatViewModel.agreedNotes(from: [context, said]), "my left shoulder is sore")
        let rambling = ChatMessage(role: .user, content: String(repeating: "a", count: 500))
        XCTAssertLessThanOrEqual(CoachChatViewModel.agreedNotes(from: [context, rambling]).count, 300)
        XCTAssertEqual(CoachChatViewModel.agreedNotes(from: [context]), "")
    }
}
