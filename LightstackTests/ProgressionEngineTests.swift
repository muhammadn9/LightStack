import XCTest
@testable import Lightstack

/// Regression tests built from the owner's real logged sessions (weight x reps @RIR).
final class ProgressionEngineTests: XCTestCase {

    // MARK: - Fixture helpers

    private func day(_ month: Int, _ d: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: month, day: d, hour: 12)) ?? Date()
    }

    /// "160x3@4, 185x6@1" -> sets.
    private func sets(_ text: String) -> [HistorySet] {
        text.split(separator: ",").map { token in
            let parts = token.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0 == "x" || $0 == "@" })
            let weight = Double(parts[0]) ?? 0
            let reps = Int(parts[1]) ?? 0
            let rir = parts.count > 2 ? Int(parts[2]) : nil
            return HistorySet(weight, reps, rir: rir)
        }
    }

    private func session(_ month: Int, _ d: Int, _ text: String) -> HistorySession {
        HistorySession(date: day(month, d), sets: sets(text))
    }

    private let bench = "Smith Machine Flat Bench Press"
    private var benchHistory: [HistorySession] {
        [session(10, 20, "160x3@4, 185x6@1, 185x6@1, 180x5@1"),
         session(10, 16, "110x6@4, 160x5@3, 180x3@3, 200x3@3, 220x1@2, 230x1@1, 160x8@1, 180x6@1"),
         session(10, 3, "20x10@6, 110x6@5, 160x6@4, 180x3@3, 200x3@2")]
    }
    private let fly = "Single Arm Pec Fly Machine"
    private var flyHistory: [HistorySession] {
        [session(10, 20, "160x9@2, 160x7@1"), session(10, 12, "140x9@2, 140x7@1"),
         session(10, 3, "130x11@1, 145x7@0"), session(9, 29, "130x9@1, 130x9@1")]
    }
    private let laterals = "Dumbbell Lateral Raises"
    private var lateralHistory: [HistorySession] {
        [session(10, 20, "25x10@1, 25x8@1"), session(10, 16, "25x8@1, 20x15@1"),
         session(10, 12, "20x15@2, 20x8@1"), session(9, 29, "20x15@1, 20x13@1")]
    }
    private let legExt = "Seated Leg extension machine"
    private var legHistory: [HistorySession] {
        [session(10, 19, "175x9@2, 175x9@1"), session(10, 15, "215x7@1, 215x6@1, 215x8@1"),
         session(10, 9, "215x9@2, 215x8@2"), session(10, 6, "215x9@2, 205x8@1")]
    }
    private let cableRow = "Cable row machine"
    private var rowHistory: [HistorySession] {
        [session(10, 17, "160x8@1, 180x5@1, 140x10@1"), session(10, 13, "160x8@1, 160x6@2"),
         session(10, 8, "160x7@1, 160x8@1")]
    }
    private let curl = "Incline Dumbbell Curl"
    private var curlHistory: [HistorySession] {
        [session(10, 17, "25x13@2, 30x9@1"), session(10, 13, "25x10@2, 25x10@1"), session(10, 8, "25x10@1, 25x10@1")]
    }

    private func plan(_ name: String, _ history: [HistorySession], best: HistorySet? = nil,
                      feedback: SessionFeedback? = nil, energy: Int = 6, warmups: Bool = false) -> ProgressionResult? {
        ProgressionEngine.plan(ProgressionInput(name: name, sessions: history, best: best,
                                                feedback: feedback, energy: energy, allowWarmups: warmups))
    }

    private func isMultiple(_ value: Double, of step: Double) -> Bool {
        abs((value / step).rounded() * step - value) < 0.0001
    }

    private func assertNotAllHardRIR(_ r: ProgressionResult, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(r.workingSets.allSatisfy { $0.rir <= 1 }, "RIR 0-1 on every set", file: file, line: line)
    }

    // MARK: - Owner fixtures

    func testBenchNextSession() throws {
        let r = try XCTUnwrap(plan(bench, benchHistory, best: HistorySet(230, 1), warmups: true))
        print("BENCH:", r.sets.map(\.text), "|", r.rationale, "| style", r.style, "range", r.repRange, "trend", r.trend)
        let work = r.workingSets
        let top = work.map(\.weight).max() ?? 0
        XCTAssertGreaterThanOrEqual(top, 180)
        XCTAssertLessThanOrEqual(top, 195)
        XCTAssertLessThanOrEqual(top, 230 + 5)
        XCTAssertEqual(work.count, 3)
        XCTAssertTrue(r.sets.allSatisfy { isMultiple($0.weight, of: 5) && $0.weight > 0 })
        XCTAssertTrue(r.warmupCount >= 1 && r.warmupCount <= 2)
        XCTAssertTrue(r.sets.prefix(r.warmupCount).allSatisfy { $0.isWarmup && $0.rir >= 4 && $0.weight < top })
        XCTAssertTrue(work.allSatisfy { $0.reps >= 5 && $0.reps <= 8 })
        assertNotAllHardRIR(r)
        XCTAssertEqual(r.style, .straightSets)
    }

    func testBenchWithoutWarmupPermissionHasNone() throws {
        let r = try XCTUnwrap(plan(bench, benchHistory, best: HistorySet(230, 1), warmups: false))
        XCTAssertEqual(r.warmupCount, 0)
        XCTAssertEqual(r.sets.count, 3)
    }

    func testPecFlyHoldsAndProgressesReps() throws {
        let r = try XCTUnwrap(plan(fly, flyHistory, best: HistorySet(160, 9)))
        print("FLY:", r.sets.map(\.text), "|", r.rationale, "| style", r.style, "range", r.repRange)
        XCTAssertTrue(r.sets.allSatisfy { $0.weight == 160 })
        XCTAssertGreaterThan(r.sets[0].reps, 9)
        XCTAssertEqual(r.workingSets.count, 3)
        XCTAssertEqual(r.warmupCount, 0)
        assertNotAllHardRIR(r)
    }

    func testLateralsKeepStraightSetsAt25() throws {
        let r = try XCTUnwrap(plan(laterals, lateralHistory, best: HistorySet(25, 10)))
        print("LATERALS:", r.sets.map(\.text), "|", r.rationale, "| style", r.style, "range", r.repRange)
        XCTAssertTrue(r.sets.allSatisfy { $0.weight == 25 || $0.weight == 20 })
        XCTAssertEqual(r.sets[0].weight, 25)
        XCTAssertTrue(r.sets.allSatisfy { isMultiple($0.weight, of: 2.5) })
        XCTAssertEqual(r.workingSets.count, 3)
        XCTAssertEqual(r.warmupCount, 0)
        assertNotAllHardRIR(r)
    }

    func testLegExtensionHandlesDropFrom215To175() throws {
        let r = try XCTUnwrap(plan(legExt, legHistory, best: HistorySet(215, 9)))
        print("LEGEXT:", r.sets.map(\.text), "|", r.rationale, "| trend", r.trend)
        XCTAssertEqual(r.trend, .down)
        XCTAssertTrue(r.sets.allSatisfy { $0.weight <= 175 && $0.weight >= 165 })
        XCTAssertEqual(r.workingSets.count, 3)
        assertNotAllHardRIR(r)
    }

    func testCableRowAndCurlInvariants() throws {
        let row = try XCTUnwrap(plan(cableRow, rowHistory, best: HistorySet(180, 5)))
        print("ROW:", row.sets.map(\.text), "|", row.rationale)
        XCTAssertTrue(row.sets.allSatisfy { isMultiple($0.weight, of: 5) && $0.weight >= 140 && $0.weight <= 185 })
        XCTAssertEqual(row.workingSets.count, 3)
        XCTAssertEqual(row.warmupCount, 0)
        assertNotAllHardRIR(row)

        let c = try XCTUnwrap(plan(curl, curlHistory, best: HistorySet(30, 9)))
        print("CURL:", c.sets.map(\.text), "|", c.rationale)
        XCTAssertTrue(c.sets.allSatisfy { isMultiple($0.weight, of: 2.5) && $0.weight > 0 })
        XCTAssertEqual(c.workingSets.count, 3)
        assertNotAllHardRIR(c)
    }

    func testWarmupsOnlyWhereAllowedAcrossTheWorkout() throws {
        let all: [(String, [HistorySession], Bool)] = [
            (bench, benchHistory, true), (fly, flyHistory, false), (laterals, lateralHistory, false),
            (cableRow, rowHistory, false), (curl, curlHistory, false), (legExt, legHistory, false)
        ]
        for (name, history, allowed) in all {
            let r = try XCTUnwrap(plan(name, history, warmups: allowed))
            XCTAssertEqual(r.warmupCount > 0, allowed, name)
            assertNotAllHardRIR(r)
        }
    }

    func testDeterministic() {
        for (name, history) in [(bench, benchHistory), (fly, flyHistory), (laterals, lateralHistory)] {
            XCTAssertEqual(plan(name, history, warmups: true), plan(name, history, warmups: true))
        }
    }

    // MARK: - Progression rules

    func testIncreaseWhenEverySetHitTopOfRange() throws {
        let h = [session(10, 20, "185x8@2, 185x8@1, 185x8@1")]
        let r = try XCTUnwrap(plan(bench, h))
        XCTAssertEqual(r.workingSets.map(\.weight), [190, 190, 190])
        XCTAssertEqual(r.workingSets.map(\.reps), [5, 5, 5])
    }

    func testDumbbellIncreaseIsTwoPointFive() throws {
        let h = [session(10, 20, "25x12@2, 25x12@1, 25x12@1")]
        let r = try XCTUnwrap(plan(laterals, h))
        XCTAssertEqual(r.workingSets.map(\.weight), [27.5, 27.5, 27.5])
        XCTAssertEqual(r.workingSets[0].reps, 8)
    }

    func testRepProgressionExample() throws {
        let h = [session(10, 20, "185x6@1, 185x6@1, 180x5@1")]
        let r = try XCTUnwrap(plan(bench, h))
        XCTAssertEqual(r.workingSets.map(\.weight), [185, 185, 185])
        XCTAssertEqual(r.workingSets.map(\.reps), [7, 6, 6])
        XCTAssertEqual(r.workingSets.map(\.rir), [2, 2, 1])
    }

    func testTooHardFeedbackReducesLoad() throws {
        let h = [session(10, 20, "185x6@1, 185x6@1, 185x6@1")]
        let r = try XCTUnwrap(plan(bench, h, feedback: .tooHard))
        XCTAssertTrue(r.workingSets.allSatisfy { $0.weight < 185 && $0.weight >= 170 && isMultiple($0.weight, of: 5) })
    }

    func testTooEasyFeedbackIncreasesLoad() throws {
        let h = [session(10, 20, "185x6@2, 185x6@2, 185x6@2")]
        let r = try XCTUnwrap(plan(bench, h, feedback: .tooEasy))
        XCTAssertTrue(r.workingSets.allSatisfy { $0.weight == 190 })
    }

    func testLowEnergyHoldsOrReduces() throws {
        let h = [session(10, 20, "185x8@2, 185x8@2, 185x8@2")]
        XCTAssertTrue(try XCTUnwrap(plan(bench, h, energy: 3)).workingSets.allSatisfy { $0.weight == 185 })
        XCTAssertTrue(try XCTUnwrap(plan(bench, h, energy: 2)).workingSets.allSatisfy { $0.weight < 185 })
    }

    func testIncreaseNeverExceedsBestPlusStep() throws {
        let h = [session(10, 20, "185x8@2, 185x8@2, 185x8@2")]
        let r = try XCTUnwrap(plan(bench, h, best: HistorySet(180, 8)))
        XCTAssertTrue(r.workingSets.allSatisfy { $0.weight <= 185 })
    }

    func testNoHistoryReturnsNil() {
        XCTAssertNil(plan(bench, []))
        XCTAssertNil(plan(bench, [HistorySession(date: day(10, 1), sets: [])]))
        XCTAssertNil(plan("Pull Up", [session(10, 1, "0x8@2, 0x7@1")]))
    }

    func testRepRangeInferredFromHighRepHistory() {
        let high = [session(10, 20, "100x15@2, 100x14@2, 100x13@1"), session(10, 13, "100x14@2, 100x14@2, 100x13@1")]
        let r = ProgressionEngine.inferRange(cls: .isolation, sessions: high)
        XCTAssertEqual(r, RepRange(lower: 10, upper: 15))
        XCTAssertEqual(ProgressionEngine.inferRange(cls: .heavyCompound, sessions: []), RepRange(lower: 5, upper: 8))
    }

    // MARK: - Styles

    func testStyleDetector() {
        XCTAssertEqual(SetStyleDetector.classify(session(10, 16, "110x6@4, 160x5@3, 180x3@3, 200x3@3, 220x1@2, 230x1@1, 160x8@1, 180x6@1")), .pyramid)
        XCTAssertEqual(SetStyleDetector.classify(session(10, 20, "185x6@1, 185x6@1, 180x5@1")), .straightSets)
        XCTAssertEqual(SetStyleDetector.classify(session(10, 16, "25x8@1, 20x15@1")), .dropSet)
        XCTAssertEqual(SetStyleDetector.classify(session(10, 1, "225x3@1, 185x8@2, 185x9@1")), .topSetBackoff)
        XCTAssertEqual(SetStyleDetector.classify(session(10, 1, "100x10@2")), .straightSets)
    }

    func testStyleNeedsConsistencyAcrossSessions() {
        XCTAssertEqual(SetStyleDetector.detect(sessions: benchHistory), .straightSets)
        XCTAssertEqual(SetStyleDetector.detect(sessions: lateralHistory), .straightSets)
        let pyramids = [session(10, 20, "150x5@3, 165x3@2, 180x2@2, 200x1@1, 165x8@1"),
                        session(10, 13, "150x5@3, 165x3@2, 180x2@2, 195x1@1, 165x7@1"),
                        session(10, 6, "145x5@3, 160x3@2, 175x2@2, 190x1@1, 160x7@1")]
        XCTAssertEqual(SetStyleDetector.detect(sessions: pyramids), .pyramid)
        XCTAssertEqual(SetStyleDetector.detect(sessions: Array(pyramids.prefix(1))), .straightSets)
    }

    func testPyramidShapeIsKeptAndCapped() throws {
        let pyramids = [session(10, 20, "100x8@3, 120x6@3, 140x5@2, 160x4@2, 180x3@2, 200x1@2, 150x8@1, 160x7@1"),
                        session(10, 13, "100x8@3, 120x6@3, 140x5@2, 160x4@2, 180x3@2, 195x1@2, 150x8@1, 160x7@1"),
                        session(10, 6, "100x8@3, 120x6@3, 140x5@2, 160x4@2, 180x3@2, 190x1@2, 150x8@1, 160x7@1")]
        let r = try XCTUnwrap(plan(bench, pyramids, warmups: true))
        XCTAssertEqual(r.style, .pyramid)
        XCTAssertLessThanOrEqual(r.sets.count, ProgressionEngine.maxPyramidSets)
        let top = r.sets.max { $0.weight < $1.weight }
        XCTAssertEqual(top?.reps, 1)
        XCTAssertEqual(top?.weight, 205)
        // Ramp ascends to the top set.
        let weights = r.sets.map(\.weight)
        let topIndex = weights.firstIndex(of: weights.max() ?? 0) ?? 0
        XCTAssertEqual(Array(weights[..<topIndex]), weights[..<topIndex].sorted())
        assertNotAllHardRIR(r)
    }

    func testDropSetStyleIsKept() throws {
        let drops = [session(10, 20, "25x10@1, 25x9@1, 20x15@1"), session(10, 13, "25x10@1, 25x9@1, 20x14@1"),
                     session(10, 6, "25x9@1, 25x9@1, 20x14@1")]
        let r = try XCTUnwrap(plan(laterals, drops))
        XCTAssertEqual(r.style, .dropSet)
        XCTAssertEqual(r.workingSets.count, 3)
        XCTAssertLessThan(r.sets[2].weight, r.sets[1].weight)
        XCTAssertTrue(r.sets.allSatisfy { isMultiple($0.weight, of: 2.5) })
        assertNotAllHardRIR(r)
    }

    func testTopSetBackoffStyleIsKept() throws {
        let h = [session(10, 20, "225x3@1, 185x8@2, 185x9@2"), session(10, 13, "225x3@1, 185x8@2, 185x8@2"),
                 session(10, 6, "220x3@1, 185x8@2, 185x8@2")]
        let r = try XCTUnwrap(plan(bench, h))
        XCTAssertEqual(r.style, .topSetBackoff)
        XCTAssertEqual(r.workingSets.count, 3)
        XCTAssertGreaterThan(r.sets[0].weight, r.sets[1].weight)
        XCTAssertGreaterThan(r.sets[1].reps, r.sets[0].reps)
        assertNotAllHardRIR(r)
    }

    // MARK: - Guardrails

    private func t(_ w: String, _ reps: String, _ rir: String) -> SetTarget { SetTarget(weight: w, reps: reps, rir: rir) }

    func testGuardrailsStripWarmupsFromNonFirstExercises() {
        let targets = [t("60", "10", "5"), t("100", "8", "2"), t("110", "8", "1")]
        let out = PlanGuardrails.apply(name: "Barbell Row", targets: targets, allowWarmups: false, bestWeight: nil)
        XCTAssertEqual(out.targets.count, 2)
        XCTAssertTrue(out.report.adjustedByGuardrails)
        let kept = PlanGuardrails.apply(name: "Barbell Row", targets: targets, allowWarmups: true, bestWeight: nil)
        XCTAssertEqual(kept.targets.count, 3)
        XCTAssertFalse(kept.report.adjustedByGuardrails)
    }

    func testGuardrailsClampSetCount() {
        let many = (0..<8).map { _ in t("100", "8", "2") }
        let capped = PlanGuardrails.apply(name: "Barbell Row", targets: many, allowWarmups: false, bestWeight: nil)
        XCTAssertEqual(capped.targets.count, 5)
        let single = PlanGuardrails.apply(name: "Barbell Row", targets: [t("100", "8", "2")], allowWarmups: false, bestWeight: nil)
        XCTAssertEqual(single.targets.count, 2)
        XCTAssertEqual(PlanGuardrails.clampedSetCount(9).count, 5)
        XCTAssertEqual(PlanGuardrails.clampedSetCount(1).count, 2)
        XCTAssertFalse(PlanGuardrails.clampedSetCount(3).report.adjustedByGuardrails)
    }

    func testGuardrailsClampWeightsAboveBest() {
        let targets = [t("150", "8", "2"), t("200", "8", "2"), t("250", "6", "1")]
        let out = PlanGuardrails.apply(name: "Barbell Row", targets: targets, allowWarmups: false, bestWeight: 160)
        XCTAssertTrue(out.targets.allSatisfy { (Double($0.prefillWeight) ?? 0) <= 160 * 1.05 })
        XCTAssertEqual(out.targets[0].weight, "150")
        XCTAssertTrue(out.report.adjustedByGuardrails)
        let within = PlanGuardrails.apply(name: "Barbell Row", targets: [t("165", "8", "2"), t("165", "8", "2")],
                                          allowWarmups: false, bestWeight: 160)
        XCTAssertFalse(within.report.adjustedByGuardrails)
    }

    func testGuardrailsRewriteAllHardRIR() {
        let targets = [t("100", "8", "0"), t("100", "8", "1"), t("100", "8", "1")]
        let out = PlanGuardrails.apply(name: "Barbell Row", targets: targets, allowWarmups: false, bestWeight: nil)
        XCTAssertEqual(out.targets.map(\.prefillRir), ["2", "2", "1"])
        XCTAssertTrue(out.report.adjustedByGuardrails)
    }

    func testGuardrailsLeaveGoodTargetsAlone() {
        let targets = [t("100", "10", "3"), t("100", "8", "2"), t("100", "8", "1")]
        let out = PlanGuardrails.apply(name: "Barbell Row", targets: targets, allowWarmups: false, bestWeight: 100)
        XCTAssertEqual(out.targets, targets)
        XCTAssertFalse(out.report.adjustedByGuardrails)
    }

    // MARK: - Applier

    func testApplierReplacesAIWithEngineAndGuardsTheRest() {
        let workoutId = UUID()
        let benchEx = Exercise.create(workoutId: workoutId, name: "Smith Machine Flat Bench Press", muscleGroup: "Chest", orderIndex: 0,
                                      targetSets: 4, targetReps: "5", targetRir: "1", restSeconds: 120,
                                      coachNote: "Target: 230 lbs — Drive your feet")
        let newEx = Exercise.create(workoutId: workoutId, name: "Cable Crossover", muscleGroup: "Chest", orderIndex: 1,
                                    targetSets: 3, targetReps: "10", targetRir: "1", restSeconds: 60, coachNote: nil)
        let parsed = WorkoutSessionService.ParsedPlan(
            exercises: [benchEx, newEx],
            setTargets: [benchEx.id: [t("230", "5", "0")],
                         newEx.id: [t("40", "10", "5"), t("40", "10", "1"), t("40", "10", "0")]])
        let group = ExerciseHistoryGroup(names: ["Smith Machine Flat Bench Press"], sessions: benchHistory,
                                         best: HistorySet(230, 1))
        let applied = PlanProgressionApplier.apply(
            plan: parsed, history: ExerciseHistoryIndex(groups: [group]), energy: 6, feedback: nil)

        let b = applied.exercises[0]
        let targets = applied.setTargets[b.id] ?? []
        XCTAssertEqual(targets.filter { $0.isWarmup == true }.count, 2)
        XCTAssertEqual(b.targetSets, targets.count)
        XCTAssertEqual(b.coachNoteParts.message, "Drive your feet")
        XCTAssertLessThanOrEqual(b.coachNoteParts.weight.flatMap { Double($0.replacingOccurrences(of: " lbs", with: "")) } ?? 999, 195)
        let evidence = applied.evidence[b.id]
        XCTAssertEqual(evidence?.source, .engine)
        XCTAssertEqual(evidence?.best, "230×1")
        XCTAssertEqual(evidence?.lastSets.first, "160×3@4")
        XCTAssertFalse(evidence?.rationale.isEmpty ?? true)

        let n = applied.exercises[1]
        let nTargets = applied.setTargets[n.id] ?? []
        XCTAssertEqual(applied.evidence[n.id]?.source, .aiGuarded)
        XCTAssertEqual(applied.evidence[n.id]?.adjustedByGuardrails, true)
        XCTAssertTrue(nTargets.allSatisfy { $0.isWarmup != true })
        XCTAssertFalse(nTargets.allSatisfy { Int($0.prefillRir).map { $0 <= 1 } ?? false })
    }

    func testApplierWarmupGoesOnlyToFirstHeavyCompound() {
        let wid = UUID()
        func ex(_ name: String, _ i: Int) -> Exercise {
            Exercise.create(workoutId: wid, name: name, muscleGroup: "x", orderIndex: i, targetSets: 3,
                            targetReps: nil, targetRir: nil, restSeconds: nil, coachNote: nil)
        }
        let a = ex(fly, 0), b = ex(bench, 1), c = ex("Barbell Bench Press", 2)
        let parsed = WorkoutSessionService.ParsedPlan(exercises: [a, b, c], setTargets: [:])
        let groups = [ExerciseHistoryGroup(names: [fly], sessions: flyHistory, best: nil),
                      ExerciseHistoryGroup(names: [bench], sessions: benchHistory, best: nil),
                      ExerciseHistoryGroup(names: ["Barbell Bench Press"], sessions: benchHistory, best: nil)]
        let applied = PlanProgressionApplier.apply(plan: parsed, history: ExerciseHistoryIndex(groups: groups),
                                                   energy: 6, feedback: nil)
        XCTAssertEqual(applied.evidence[a.id]?.warmupCount, 0)
        XCTAssertGreaterThan(applied.evidence[b.id]?.warmupCount ?? 0, 0)
        XCTAssertEqual(applied.evidence[c.id]?.warmupCount, 0)
    }

    // MARK: - History index and debug store

    func testNameVariantsMergeIntoOneGroup() {
        let group = ExerciseHistoryGroup(names: ["Smith Machine Flat Bench Press"], sessions: benchHistory, best: nil)
        let index = ExerciseHistoryIndex(groups: [group])
        XCTAssertNotNil(index.group(for: "Smith machine flat bench press"))
        XCTAssertNil(index.group(for: "Lat Pulldown"))
    }

    func testTrendLineIsCompactAndOldestFirst() {
        let line = ExerciseHistoryIndex.trendLine(for: benchHistory) { date in
            let c = Calendar(identifier: .gregorian).dateComponents([.month, .day], from: date)
            return String(format: "%02d/%02d", c.month ?? 0, c.day ?? 0)
        }
        XCTAssertTrue(line.hasPrefix("10/03 "), line)
        XCTAssertTrue(line.contains("10/20 185×6,185×6,180×5"), line)
        XCTAssertTrue(line.contains("230×1 top"), line)
    }

    func testDebugStoreIsUserScopedCappedAndClearable() throws {
        let suite = "coach-debug-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CoachDebugStore(defaults: defaults)
        let me = UUID(), other = UUID()
        let huge = String(repeating: "x", count: 200_000)
        store.recordRequest(userId: me, workoutType: "Push", model: "Gemini (test)", systemPromptName: "plan",
                            systemPromptLength: 1234, userMessage: huge)
        store.recordResponse(userId: me, raw: huge, adjustments: ["a"])
        XCTAssertNotNil(store.lastPlan(forUser: me))
        XCTAssertNil(store.lastPlan(forUser: other))
        let stored = try XCTUnwrap(defaults.data(forKey: CoachDebugStore.defaultsKey))
        XCTAssertLessThanOrEqual(stored.count, CoachDebugStore.maxBytes)
        XCTAssertEqual(CoachDebugStore(defaults: defaults).lastPlan(forUser: me)?.systemPromptLength, 1234)
        store.clear()
        XCTAssertNil(store.lastPlan(forUser: me))
        XCTAssertNil(defaults.data(forKey: CoachDebugStore.defaultsKey))
    }
}
