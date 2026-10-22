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
                      feedback: SessionFeedback? = nil, energy: Int = 6, warmups: Bool = false,
                      focus: CoachFocus = .hypertrophy, rest: Int = 90, next: NextTarget? = nil,
                      fresh: Bool = false) -> ProgressionResult? {
        ProgressionEngine.plan(ProgressionInput(name: name, sessions: history, best: best,
                                                feedback: feedback, energy: energy, allowWarmups: warmups,
                                                focus: focus, restPreference: rest, nextTarget: next,
                                                recentlyTrained: fresh))
    }

    private func isMultiple(_ value: Double, of step: Double) -> Bool {
        abs((value / step).rounded() * step - value) < 0.0001
    }

    private func assertNotAllHardRIR(_ r: ProgressionResult, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(r.workingSets.allSatisfy { $0.rir <= 1 }, "RIR 0-1 on every set", file: file, line: line)
    }

    /// The owner's structure: at most one top set (two only for strength), nothing above 2 sets at 95%+.
    private func assertStandardMainStructure(_ r: ProgressionResult, strength: Bool = false,
                                             file: StaticString = #filePath, line: UInt = #line) {
        let top = r.topSet?.weight ?? 0
        let work = r.workingSets
        XCTAssertEqual(work.count, strength ? 4 : 3, file: file, line: line)
        XCTAssertEqual(work.filter { $0.role == .top }.count, strength ? 2 : 1, file: file, line: line)
        XCTAssertLessThanOrEqual(work.filter { $0.weight >= 0.95 * top }.count, 2, file: file, line: line)
        let ramp = work.first { $0.role == .ramp }
        XCTAssertNotNil(ramp, file: file, line: line)
        let share = (ramp?.weight ?? 0) / max(top, 1)
        XCTAssertTrue(share >= 0.75 && share <= 0.85, "Set 1 is \(share) of the top", file: file, line: line)
        XCTAssertGreaterThan(r.topSet?.restSeconds ?? 0, ramp?.restSeconds ?? 0, file: file, line: line)
        XCTAssertEqual(work.filter { $0.role == .backoff }.count, 1, file: file, line: line)
        XCTAssertEqual(work.last?.role, .backoff, file: file, line: line)
        let back = work.first { $0.role == .backoff }
        XCTAssertLessThan(back?.weight ?? 999, top * 0.95, file: file, line: line)
        XCTAssertGreaterThanOrEqual(back?.reps ?? 0, r.topSet?.reps ?? 99, file: file, line: line)
        XCTAssertGreaterThanOrEqual(ramp?.reps ?? 0, r.topSet?.reps ?? 99, file: file, line: line)
    }

    // MARK: - Owner fixtures

    func testBenchNextSession() throws {
        let r = try XCTUnwrap(plan(bench, benchHistory, best: HistorySet(230, 1), warmups: true))
        print("BENCH:", r.sets.map { "\($0.role.rawValue) \($0.text) rest \($0.restSeconds)" }, "|", r.rationale)
        assertStandardMainStructure(r)
        let top = try XCTUnwrap(r.topSet)
        XCTAssertEqual(top.weight, 185)
        XCTAssertEqual(top.reps, 7)
        XCTAssertEqual(top.rir, 1)
        XCTAssertEqual(r.workingSets.map(\.weight), [150, 185, 170])
        XCTAssertEqual(r.workingSets.map(\.reps), [10, 7, 8])
        // The athlete warms up on this lift: one easy 60 s warm-up.
        XCTAssertEqual(r.warmupCount, 1)
        XCTAssertEqual(r.sets.first?.role, .warmup)
        XCTAssertEqual(r.sets.first?.restSeconds, 60)
        XCTAssertTrue(r.sets.allSatisfy { isMultiple($0.weight, of: 5) && $0.weight > 0 })
        XCTAssertEqual(r.sets.map(\.restSeconds), [60, 90, 120, 90])
        XCTAssertLessThanOrEqual(top.weight, 230 + 5)
    }

    func testCableRowIsOneTopSetNotFourHeavySets() throws {
        let r = try XCTUnwrap(plan(cableRow, rowHistory, best: HistorySet(180, 5), warmups: true))
        print("ROW:", r.sets.map { "\($0.role.rawValue) \($0.text) rest \($0.restSeconds)" }, "|", r.rationale)
        assertStandardMainStructure(r)
        XCTAssertEqual(r.workingSets.map(\.weight), [145, 180, 165])
        XCTAssertEqual(r.workingSets.map(\.reps), [10, 6, 7])
        // No warm-ups in the athlete's own history: none prescribed.
        XCTAssertEqual(r.warmupCount, 0)
        XCTAssertTrue(r.sets.allSatisfy { isMultiple($0.weight, of: 5) })
    }

    func testBenchWithoutWarmupPermissionHasNone() throws {
        let r = try XCTUnwrap(plan(bench, benchHistory, best: HistorySet(230, 1), warmups: false))
        XCTAssertEqual(r.warmupCount, 0)
        XCTAssertEqual(r.sets.count, 3)
    }

    func testIsolationGetsTwoSetsWithRest() throws {
        let fly = try XCTUnwrap(plan(self.fly, flyHistory, best: HistorySet(160, 9)))
        print("FLY:", fly.sets.map(\.text), "|", fly.rationale)
        XCTAssertEqual(fly.sets.count, 2)
        XCTAssertTrue(fly.sets.allSatisfy { $0.weight == 160 && $0.role == .straight })
        XCTAssertEqual(fly.sets.map(\.reps), [10, 10])
        XCTAssertEqual(fly.sets.map(\.rir), [2, 1], "the last set is closest to failure")
        XCTAssertTrue(fly.sets.allSatisfy { $0.restSeconds >= 60 && $0.restSeconds <= 90 })

        let c = try XCTUnwrap(plan(curl, curlHistory, best: HistorySet(30, 9)))
        print("CURL:", c.sets.map(\.text), "|", c.rationale)
        XCTAssertEqual(c.sets.count, 2)
        XCTAssertEqual(c.sets.map(\.weight), [30, 30])
        XCTAssertEqual(c.sets.map(\.reps), [10, 10])
        XCTAssertTrue(c.sets.allSatisfy { isMultiple($0.weight, of: 2.5) })

        let l = try XCTUnwrap(plan(laterals, lateralHistory, best: HistorySet(25, 10)))
        XCTAssertEqual(l.sets.count, 2)
        XCTAssertEqual(l.sets.map(\.weight), [25, 25])
        XCTAssertTrue(l.sets.allSatisfy { isMultiple($0.weight, of: 2.5) })
    }

    func testRestIsLongerOnTheTopSetAndPreferenceIsTheFloor() throws {
        let r = try XCTUnwrap(plan(bench, benchHistory, warmups: true))
        let rest = Dictionary(uniqueKeysWithValues: r.sets.map { ($0.role, $0.restSeconds) })
        XCTAssertEqual(rest[.warmup], 60)
        XCTAssertEqual(rest[.ramp], 90)
        XCTAssertEqual(rest[.top], 120)
        XCTAssertEqual(rest[.backoff], 90)
        XCTAssertGreaterThan(rest[.top] ?? 0, rest[.backoff] ?? 999)

        // A 150 s preference lifts back-off and isolation rest, not the top set's.
        let long = try XCTUnwrap(plan(bench, benchHistory, rest: 150))
        XCTAssertEqual(long.workingSets.first { $0.role == .backoff }?.restSeconds, 150)
        XCTAssertEqual(long.workingSets.first { $0.role == .top }?.restSeconds, 150 > 120 ? 120 : 120)
        let iso = try XCTUnwrap(plan(fly, flyHistory, rest: 150))
        XCTAssertTrue(iso.sets.allSatisfy { $0.restSeconds == 150 })
        // A short preference never goes under the minimums.
        let short = try XCTUnwrap(plan(fly, flyHistory, rest: 30))
        XCTAssertTrue(short.sets.allSatisfy { $0.restSeconds == 60 })
    }

    func testLegExtensionHandlesDropFrom215To175() throws {
        let r = try XCTUnwrap(plan(legExt, legHistory, best: HistorySet(215, 9)))
        print("LEGEXT:", r.sets.map(\.text), "|", r.rationale, "| trend", r.trend)
        XCTAssertEqual(r.trend, .down)
        XCTAssertTrue(r.sets.allSatisfy { $0.weight <= 175 && $0.weight >= 165 })
        XCTAssertEqual(r.sets.count, 2)
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

    func testNoLiftEverHasMoreThanTwoSetsAtNinetyFivePercent() throws {
        let all: [(String, [HistorySession])] = [
            (bench, benchHistory), (cableRow, rowHistory), (fly, flyHistory), (curl, curlHistory),
            (laterals, lateralHistory), (legExt, legHistory)
        ]
        for focus in CoachFocus.allCases {
            for (name, history) in all {
                let r = try XCTUnwrap(plan(name, history, warmups: true, focus: focus))
                let top = r.workingSets.map(\.weight).max() ?? 0
                XCTAssertLessThanOrEqual(r.workingSets.filter { $0.weight >= 0.95 * top }.count, 2, "\(name) \(focus)")
                XCTAssertLessThanOrEqual(r.workingSets.count, focus == .strength ? 4 : 3, "\(name) \(focus)")
            }
        }
    }

    func testDeterministic() {
        for (name, history) in [(bench, benchHistory), (fly, flyHistory), (laterals, lateralHistory), (cableRow, rowHistory)] {
            XCTAssertEqual(plan(name, history, warmups: true), plan(name, history, warmups: true))
        }
    }

    // MARK: - Focus

    func testStrengthFocusUsesLowRepsTwoTopSetsAndLongRest() throws {
        let r = try XCTUnwrap(plan(bench, benchHistory, best: HistorySet(230, 1), focus: .strength))
        print("STRENGTH:", r.sets.map { "\($0.role.rawValue) \($0.text) rest \($0.restSeconds)" })
        XCTAssertEqual(r.repRange, RepRange(lower: 3, upper: 6))
        assertStandardMainStructure(r, strength: true)
        XCTAssertTrue(r.workingSets.filter { $0.role == .top }.allSatisfy { $0.restSeconds == 180 })
        XCTAssertEqual(r.workingSets.last?.role, .backoff, "strength still ends with a back-off")
        // 185x6 is the top of the 3-6 range, so the load goes up.
        XCTAssertEqual(r.topSet?.weight, 190)
        XCTAssertEqual(r.topSet?.reps, 3)
    }

    func testHypertrophyTopSetRangeIsSixToTen() throws {
        let r = try XCTUnwrap(plan(bench, benchHistory))
        XCTAssertEqual(r.repRange, RepRange(lower: 6, upper: 10))
        XCTAssertTrue((6...10).contains(r.topSet?.reps ?? 0))
    }

    func testMaintenanceHoldsLoads() throws {
        let r = try XCTUnwrap(plan(bench, benchHistory, focus: .maintenance))
        XCTAssertEqual(r.topSet?.weight, 185)
        XCTAssertEqual(r.topSet?.reps, 6)
        let f = try XCTUnwrap(plan(fly, flyHistory, focus: .maintenance))
        XCTAssertEqual(f.sets.map(\.weight), [160, 160])
        XCTAssertEqual(f.sets.map(\.reps), [9, 9])
    }

    // MARK: - Next targets from the last review

    func testNextTargetFromLastReviewBecomesTheTopSet() throws {
        let r = try XCTUnwrap(plan(bench, benchHistory, best: HistorySet(230, 1),
                                   next: NextTarget(weight: 190, reps: 6, note: "make the jump")))
        XCTAssertTrue(r.usedNextTarget)
        XCTAssertEqual(r.topSet?.weight, 190)
        XCTAssertEqual(r.topSet?.reps, 6)
        XCTAssertTrue(r.rationale.contains("from last review"))
        assertStandardMainStructure(r)
    }

    func testInsaneNextTargetIsIgnored() throws {
        let plain = try XCTUnwrap(plan(bench, benchHistory))
        for bad in [NextTarget(weight: 300, reps: 6), NextTarget(weight: 100, reps: 6),
                    NextTarget(weight: 185, reps: 0), NextTarget(weight: 185, reps: 40), NextTarget(weight: -5, reps: 5)] {
            let r = try XCTUnwrap(plan(bench, benchHistory, next: bad))
            XCTAssertFalse(r.usedNextTarget, "\(bad)")
            XCTAssertEqual(r, plain)
        }
    }

    func testNextTargetIsStillBentByLowEnergy() throws {
        let r = try XCTUnwrap(plan(bench, benchHistory, energy: 2, next: NextTarget(weight: 190, reps: 6)))
        XCTAssertTrue(r.usedNextTarget)
        XCTAssertLessThan(r.topSet?.weight ?? 999, 190)
        let hold = try XCTUnwrap(plan(bench, benchHistory, energy: 3, next: NextTarget(weight: 190, reps: 6)))
        XCTAssertEqual(hold.topSet?.weight, 185, "low energy never takes the step up")
    }

    func testNextTargetCarriesTheCurlJump() throws {
        let h = [session(10, 20, "20x12@2, 20x12@1")]
        let laterals = "Dumbbell Lateral Raises"
        let r = try XCTUnwrap(plan(laterals, h, next: NextTarget(weight: 22.5, reps: 12, note: "make the jump")))
        XCTAssertTrue(r.usedNextTarget)
        XCTAssertEqual(r.sets.map(\.weight), [22.5, 22.5])
        XCTAssertEqual(r.sets.map(\.reps), [12, 12])
    }

    // MARK: - Recency rule

    func testRecentlyTrainedHoldsLoadAtRIR2AndDropsBackoff() throws {
        let h = [session(10, 20, "185x10@2, 185x10@1, 185x10@1")]
        let normal = try XCTUnwrap(plan(bench, h))
        XCTAssertEqual(normal.topSet?.weight, 190)
        XCTAssertNotNil(normal.workingSets.first { $0.role == .backoff })

        let fresh = try XCTUnwrap(plan(bench, h, fresh: true))
        print("FRESH:", fresh.sets.map { "\($0.role.rawValue) \($0.text)" }, fresh.rationale)
        XCTAssertTrue(fresh.recencyApplied)
        XCTAssertEqual(fresh.topSet?.weight, 185, "load held")
        XCTAssertEqual(fresh.topSet?.rir, 2)
        XCTAssertNil(fresh.workingSets.first { $0.role == .backoff })
        XCTAssertEqual(fresh.workingSets.count, 2)

        let iso = try XCTUnwrap(plan(fly, flyHistory, fresh: true))
        XCTAssertEqual(iso.sets.map(\.rir), [2, 2])
    }

    func testMuscleRecencyIsFreshOnlyWhenHardAndWithin48Hours() {
        let now = Date()
        XCTAssertTrue(MuscleRecency(lastTrained: now.addingTimeInterval(-30 * 3600), hardSets: 6).isFresh(now: now))
        XCTAssertFalse(MuscleRecency(lastTrained: now.addingTimeInterval(-60 * 3600), hardSets: 6).isFresh(now: now))
        XCTAssertFalse(MuscleRecency(lastTrained: now.addingTimeInterval(-10 * 3600), hardSets: 2).isFresh(now: now))
        XCTAssertEqual(MuscleGroups.canonical("Upper Chest"), "chest")
        XCTAssertEqual(MuscleGroups.canonical("Rear Delts"), "rear delts")
        XCTAssertEqual(MuscleGroups.canonical("Lats"), "back")
    }

    // MARK: - Progression rules

    func testIncreaseWhenTopSetHitTopOfRange() throws {
        let h = [session(10, 20, "185x10@2, 185x10@1, 185x10@1")]
        let r = try XCTUnwrap(plan(bench, h))
        XCTAssertEqual(r.topSet?.weight, 190)
        XCTAssertEqual(r.topSet?.reps, 6)
        assertStandardMainStructure(r)
    }

    func testDumbbellIncreaseIsTwoPointFive() throws {
        let h = [session(10, 20, "25x12@2, 25x12@1, 25x12@1")]
        let r = try XCTUnwrap(plan(laterals, h))
        XCTAssertEqual(r.sets.map(\.weight), [27.5, 27.5])
        XCTAssertEqual(r.sets[0].reps, 8)
    }

    func testRepProgressionExample() throws {
        let h = [session(10, 20, "185x6@1, 185x6@1, 180x5@1")]
        let r = try XCTUnwrap(plan(bench, h))
        XCTAssertEqual(r.topSet?.weight, 185)
        XCTAssertEqual(r.topSet?.reps, 7)
        XCTAssertEqual(r.workingSets.map(\.rir), [2, 1, 2])
    }

    func testTooHardFeedbackReducesLoad() throws {
        let h = [session(10, 20, "185x6@1, 185x6@1, 185x6@1")]
        let r = try XCTUnwrap(plan(bench, h, feedback: .tooHard))
        XCTAssertTrue(r.workingSets.allSatisfy { $0.weight < 185 && $0.weight >= 140 && isMultiple($0.weight, of: 5) })
        XCTAssertEqual(r.topSet?.weight, 175)
    }

    func testTooEasyFeedbackIncreasesLoad() throws {
        let h = [session(10, 20, "185x6@2, 185x6@2, 185x6@2")]
        let r = try XCTUnwrap(plan(bench, h, feedback: .tooEasy))
        XCTAssertEqual(r.topSet?.weight, 190)
    }

    func testLowEnergyHoldsOrReduces() throws {
        let h = [session(10, 20, "185x8@2, 185x8@2, 185x8@2")]
        XCTAssertEqual(try XCTUnwrap(plan(bench, h, energy: 3)).topSet?.weight, 185)
        XCTAssertEqual(try XCTUnwrap(plan(bench, h, energy: 3)).topSet?.reps, 8)
        XCTAssertLessThan(try XCTUnwrap(plan(bench, h, energy: 2)).topSet?.weight ?? 999, 185)
    }

    func testIncreaseNeverExceedsBestPlusStep() throws {
        let h = [session(10, 20, "185x10@2, 185x10@2, 185x10@2")]
        let r = try XCTUnwrap(plan(bench, h, best: HistorySet(180, 8)))
        XCTAssertEqual(r.topSet?.weight, 185)
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

    // MARK: - Styles are only read, the output is the standard structure

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

    func testPyramidHistoryStillGetsOneTopSet() throws {
        let pyramids = [session(10, 20, "100x8@3, 120x6@3, 140x5@2, 160x4@2, 180x3@2, 200x1@2, 150x8@1, 160x7@1"),
                        session(10, 13, "100x8@3, 120x6@3, 140x5@2, 160x4@2, 180x3@2, 195x1@2, 150x8@1, 160x7@1"),
                        session(10, 6, "100x8@3, 120x6@3, 140x5@2, 160x4@2, 180x3@2, 190x1@2, 150x8@1, 160x7@1")]
        let r = try XCTUnwrap(plan(bench, pyramids, warmups: true))
        XCTAssertEqual(r.style, .pyramid, "the history is still read as a pyramid")
        XCTAssertEqual(r.workingSets.count, 3)
        XCTAssertEqual(r.workingSets.filter { $0.role == .top }.count, 1)
        XCTAssertEqual(r.topSet?.weight, 205)
        assertNotAllHardRIR(r)
    }

    func testDropSetHistoryGetsTwoStraightSets() throws {
        let drops = [session(10, 20, "25x10@1, 25x9@1, 20x15@1"), session(10, 13, "25x10@1, 25x9@1, 20x14@1"),
                     session(10, 6, "25x9@1, 25x9@1, 20x14@1")]
        let r = try XCTUnwrap(plan(laterals, drops))
        XCTAssertEqual(r.style, .dropSet)
        XCTAssertEqual(r.sets.count, 2)
        XCTAssertTrue(r.sets.allSatisfy { isMultiple($0.weight, of: 2.5) })
    }

    func testTopSetBackoffHistoryKeepsItsTopSet() throws {
        let h = [session(10, 20, "225x3@1, 185x8@2, 185x9@2"), session(10, 13, "225x3@1, 185x8@2, 185x8@2"),
                 session(10, 6, "220x3@1, 185x8@2, 185x8@2")]
        let r = try XCTUnwrap(plan(bench, h))
        XCTAssertEqual(r.style, .topSetBackoff)
        XCTAssertEqual(r.workingSets.count, 3)
        XCTAssertEqual(r.topSet?.weight, 225)
        XCTAssertLessThan(r.workingSets.last?.weight ?? 999, 225)
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
        let targets = [t("100", "10", "3"), t("90", "8", "2"), t("90", "8", "1")]
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
        XCTAssertEqual(targets.filter { $0.isWarmup == true }.count, 1)
        XCTAssertEqual(targets.map(\.role), [.warmup, .ramp, .top, .backoff])
        XCTAssertEqual(targets.map(\.restSeconds), [60, 90, 120, 90])
        XCTAssertEqual(targets.map(\.prefillWeight), ["95", "150", "185", "170"])
        XCTAssertEqual(b.targetSets, targets.count)
        XCTAssertEqual(b.coachNoteParts.message, "Drive your feet")
        XCTAssertEqual(b.coachNoteParts.weight, "185 lbs")
        XCTAssertEqual(b.restSeconds, 120)
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
        XCTAssertEqual(nTargets.count, 2, "new isolation exercises get 2 sets")
        XCTAssertTrue(nTargets.allSatisfy { $0.resolvedRole == .straight && $0.restSeconds != nil })
        XCTAssertFalse(nTargets.allSatisfy { Int($0.prefillRir).map { $0 <= 1 } ?? false })
    }

    func testApplierWarmupGoesOnlyToTheFirstTwoHeavyCompounds() {
        let wid = UUID()
        func ex(_ name: String, _ i: Int, _ muscle: String = "Chest") -> Exercise {
            Exercise.create(workoutId: wid, name: name, muscleGroup: muscle, orderIndex: i, targetSets: 3,
                            targetReps: nil, targetRir: nil, restSeconds: nil, coachNote: nil)
        }
        let a = ex(bench, 0), b = ex("Barbell Bench Press", 1), c = ex("Incline Chest Press Machine", 2), d = ex(fly, 3, "Shoulders")
        let parsed = WorkoutSessionService.ParsedPlan(exercises: [a, b, c, d], setTargets: [:])
        let groups = [ExerciseHistoryGroup(names: [bench], sessions: benchHistory, best: nil),
                      ExerciseHistoryGroup(names: ["Barbell Bench Press"], sessions: benchHistory, best: nil),
                      ExerciseHistoryGroup(names: ["Incline Chest Press Machine"], sessions: benchHistory, best: nil),
                      ExerciseHistoryGroup(names: [fly], sessions: flyHistory, best: nil)]
        let applied = PlanProgressionApplier.apply(plan: parsed, history: ExerciseHistoryIndex(groups: groups),
                                                   energy: 6, feedback: nil)
        XCTAssertGreaterThan(applied.evidence[a.id]?.warmupCount ?? 0, 0)
        XCTAssertGreaterThan(applied.evidence[b.id]?.warmupCount ?? 0, 0)
        XCTAssertEqual(applied.evidence[c.id]?.warmupCount, 0)
        XCTAssertEqual(applied.evidence[d.id]?.warmupCount, 0)
    }

    // MARK: - Coach review edits through the guardrails

    private func ctx(fresh: [String: MuscleRecency] = [:]) -> PlanCoachContext {
        PlanCoachContext(focus: .hypertrophy, restPreference: 90, nextTargets: [:], recency: fresh, now: Date())
    }

    private func benchPlan(_ changes: [PlanChange], coach: PlanCoachContext? = nil) -> (AppliedPlan, Exercise) {
        let wid = UUID()
        let e = Exercise.create(workoutId: wid, name: bench, muscleGroup: "Chest", orderIndex: 0, targetSets: 3,
                                targetReps: nil, targetRir: nil, restSeconds: nil, coachNote: nil)
        let parsed = WorkoutSessionService.ParsedPlan(exercises: [e], setTargets: [:])
        let group = ExerciseHistoryGroup(names: [bench], sessions: benchHistory, best: HistorySet(230, 1))
        let applied = PlanProgressionApplier.apply(plan: parsed, history: ExerciseHistoryIndex(groups: [group]),
                                                   energy: 6, feedback: nil, coach: coach ?? ctx(), changes: changes)
        return (applied, e)
    }

    func testLoadAdjustIsClampedToMinus15AndPlus5Percent() {
        let down = benchPlan([PlanChange(type: .loadAdjust, exercise: bench, detail: "-40%", reason: "tired", percent: -40)])
        let downTop = down.0.setTargets[down.1.id]?.compactMap { Double($0.prefillWeight) }.max() ?? 0
        XCTAssertLessThanOrEqual(downTop, 160, "185 -15% = 157.5, rounded down to 155")
        XCTAssertGreaterThanOrEqual(downTop, 150)
        XCTAssertEqual(down.0.changes.first?.applied, true)
        XCTAssertEqual(down.0.changes.first?.percent, -15)
        XCTAssertNotNil(down.0.changes.first?.note, "says it was clamped")

        let up = benchPlan([PlanChange(type: .loadAdjust, exercise: bench, detail: "+25%", reason: "feels light", percent: 25)])
        let upTop = up.0.setTargets[up.1.id]?.compactMap { Double($0.prefillWeight) }.max() ?? 0
        XCTAssertLessThanOrEqual(upTop, 185 * 1.05 + 0.001)
        XCTAssertEqual(up.0.changes.first?.percent, 5)

        // Percent can come from the detail text; an unsigned "cut" means lighter.
        let text = benchPlan([PlanChange(type: .loadAdjust, exercise: bench, detail: "cut 10%", reason: "r")])
        let textTop = text.0.setTargets[text.1.id]?.compactMap { Double($0.prefillWeight) }.max() ?? 0
        XCTAssertLessThan(textTop, 185)
    }

    func testSetCountEditsCannotAddHeavySets() {
        let more = benchPlan([PlanChange(type: .setCount, exercise: bench, detail: "5 sets", reason: "volume", sets: 5)])
        XCTAssertEqual(more.0.setTargets[more.1.id]?.filter { $0.isWarmup != true }.count, 3)
        XCTAssertEqual(more.0.changes.first?.applied, false)

        let fewer = benchPlan([PlanChange(type: .setCount, exercise: bench, detail: "2 sets", reason: "tired", sets: 2)])
        let targets = fewer.0.setTargets[fewer.1.id] ?? []
        XCTAssertEqual(targets.filter { $0.isWarmup != true }.count, 2)
        XCTAssertTrue(targets.contains { $0.role == .top }, "the top set is never the one removed")
        XCTAssertTrue(targets.contains { $0.role == .backoff }, "Set 1 goes first; the back-off stays")
        XCTAssertEqual(fewer.0.changes.first?.applied, true)
    }

    func testDropAndUnknownChangesAreReportedHonestly() {
        let r = benchPlan([PlanChange(type: .drop, exercise: bench, detail: "skip", reason: "x"),
                           PlanChange(type: .loadAdjust, exercise: "Not In Plan", detail: "-5%", reason: "x", percent: -5),
                           PlanChange(type: .reorder, exercise: bench, detail: "first", reason: "x")])
        XCTAssertEqual(r.0.changes.map(\.applied), [false, false, true])
    }

    // MARK: - UI-test seed bug: strength plan had two top sets and no back-off

    private let seedBench = "Barbell Bench Press"
    private var seedHistory: [HistorySession] { [session(10, 20, "95x10@5, 185x6@1, 185x6@1, 180x5@1")] }

    private func seedPlan(focus: CoachFocus, changes: [PlanChange] = [], target: NextTarget? = nil) -> [SetTarget] {
        let e = Exercise.create(workoutId: UUID(), name: seedBench, muscleGroup: "Chest", orderIndex: 0, targetSets: 3,
                                targetReps: nil, targetRir: nil, restSeconds: nil, coachNote: nil)
        let group = ExerciseHistoryGroup(names: [seedBench], sessions: seedHistory, best: HistorySet(185, 6))
        var coach = PlanCoachContext(focus: focus, restPreference: 90, nextTargets: [:], recency: [:], now: Date())
        if let target { coach.nextTargets[seedBench.lowercased()] = .init(target: target, date: day(10, 21)) }
        let applied = PlanProgressionApplier.apply(
            plan: .init(exercises: [e], setTargets: [:]), history: ExerciseHistoryIndex(groups: [group]),
            energy: 6, feedback: nil, coach: coach, changes: changes)
        return applied.setTargets[applied.exercises[0].id] ?? []
    }

    private func assertInvariants(_ t: [SetTarget], strength: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let work = t.filter { $0.isWarmup != true }
        let tops = work.filter { $0.resolvedRole == .top }
        let topW = tops.compactMap { Double($0.prefillWeight) }.max() ?? 0
        XCTAssertEqual(work.filter { $0.resolvedRole == .backoff }.count, 1, "\(t)", file: file, line: line)
        XCTAssertEqual(work.last?.resolvedRole, .backoff, file: file, line: line)
        XCTAssertLessThanOrEqual(tops.count, strength ? 2 : 1, file: file, line: line)
        XCTAssertLessThanOrEqual(work.filter { (Double($0.prefillWeight) ?? 0) >= topW * 0.95 }.count, 2, file: file, line: line)
        let topReps = Int(tops.first?.prefillReps ?? "") ?? 0
        if let ramp = work.first(where: { $0.resolvedRole == .ramp }) {
            XCTAssertGreaterThanOrEqual(Int(ramp.prefillReps) ?? 0, topReps, file: file, line: line)
        }
        XCTAssertLessThanOrEqual(topW, 194.25, "top within +5% of 185", file: file, line: line)
    }

    func testStrengthFocusSeedPlanEndsWithBackoff() {
        let t = seedPlan(focus: .strength)
        assertInvariants(t, strength: true)
        XCTAssertEqual(t.filter { $0.resolvedRole == .top }.count, 2)
    }

    func testHypertrophySeedPlanHasOneTopAndBackoffAndTenToTwelveRepSet1() {
        let t = seedPlan(focus: .hypertrophy)
        assertInvariants(t, strength: false)
        let ramp = t.first { $0.resolvedRole == .ramp }
        XCTAssertTrue((10...12).contains(Int(ramp?.prefillReps ?? "") ?? 0), "\(t)")
        XCTAssertEqual(t.first { $0.resolvedRole == .top }?.restSeconds, 120)
    }

    func testReviewChangesCannotRemoveBackoffOrDuplicateTop() {
        for focus in [CoachFocus.hypertrophy, .strength] {
            for sets in [2, 3, 4, 5] {
                let t = seedPlan(focus: focus, changes: [
                    PlanChange(type: .setCount, exercise: seedBench, detail: "\(sets) sets", reason: "x", sets: sets),
                    PlanChange(type: .loadAdjust, exercise: seedBench, detail: "+5%", reason: "x", percent: 5)])
                assertInvariants(t, strength: focus == .strength)
            }
        }
    }

    func testTopWeightNeverJumpsAboveFivePercentUnlessTargetWithinE1RMLimit() {
        // A silly review target is ignored by the engine and, if it slips through, clamped by the final pass.
        let silly = seedPlan(focus: .hypertrophy, target: NextTarget(weight: 225, reps: 5))
        XCTAssertLessThanOrEqual(silly.compactMap { Double($0.prefillWeight) }.max() ?? 0, 194.25)
        let ctx = PlanGuardrails.StructureContext(name: seedBench, focus: .hypertrophy, restPreference: 90,
                                                  bestRecentTop: 185, bestE1RM: 222, nextTarget: NextTarget(weight: 200, reps: 3))
        XCTAssertEqual(PlanGuardrails.topWeightLimit(ctx), 200, "target 200x3 is under the e1RM limit")
        var bad = ctx; bad.nextTarget = NextTarget(weight: 215, reps: 5)
        XCTAssertEqual(PlanGuardrails.topWeightLimit(bad) ?? 0, 185 * 1.05, accuracy: 0.001)
        let raw = [SetTarget(weight: "150", reps: "8", rir: "2", role: .ramp), SetTarget(weight: "215", reps: "3", rir: "1", role: .top),
                   SetTarget(weight: "215", reps: "3", rir: "1", role: .top)]
        let fixed = PlanGuardrails.enforceMainLiftStructure(raw, ctx: bad).targets
        XCTAssertEqual(fixed.map(\.resolvedRole), [.ramp, .top, .backoff])
        XCTAssertEqual(fixed[1].prefillWeight, "190")
    }

    func testFallbackOverallReadMatchesMissedMainLift() {
        let pTop = PrescribedSet(role: .top, weight: 190, reps: 5, rir: 1, restSeconds: 120)
        let pres = ExercisePrescription(name: seedBench, muscleGroup: "Chest", sets: [pTop])
        let logged = [LoggedExercise(name: seedBench, muscleGroup: "Chest", sets: [HistorySet(190, 2, rir: 0)])]
        let analysis = SessionAnalyzer.analyze(logged: logged, prescription: [pres], energy: 6, userNote: nil, reasons: [:],
                                               previous: [], history: ExerciseHistoryIndex(), focus: .hypertrophy)
        let read = SessionAnalyzer.fallbackReview(analysis, workoutType: "Push").overallRead
        XCTAssertTrue(read.contains("missed"), read)
        XCTAssertFalse(read.lowercased().contains("everything"), read)
        let merged = SessionAnalyzer.merge(analysis, model: ModelReview(exercises: [], overallRead: "Everything moved well, add 5 lbs.", recurringFlags: []), workoutType: "Push")
        XCTAssertTrue(merged.overallRead.contains("missed"), merged.overallRead)
    }

    func testRecencyRuleReachesThePlanAndExplainsItself() {
        let fresh = ctx(fresh: ["chest": MuscleRecency(lastTrained: Date().addingTimeInterval(-24 * 3600), hardSets: 8)])
        let r = benchPlan([], coach: fresh)
        let targets = r.0.setTargets[r.1.id] ?? []
        XCTAssertFalse(targets.contains { $0.role == .backoff })
        XCTAssertEqual(targets.first { $0.role == .top }?.prefillRir, "2")
        XCTAssertTrue(r.0.safeguards.contains { $0.contains("48 h") }, "\(r.0.safeguards)")
    }

    func testMuscleVolumeCapDropsExtraIsolationWork() {
        let wid = UUID()
        let names = ["Cable Fly", "Pec Deck Fly", "Incline Fly", "Decline Fly", "Machine Fly", "Dumbbell Fly"]
        let exercises = names.enumerated().map { i, n in
            Exercise.create(workoutId: wid, name: n, muscleGroup: "Chest", orderIndex: i, targetSets: 2,
                            targetReps: nil, targetRir: nil, restSeconds: nil, coachNote: nil)
        }
        var targets: [UUID: [SetTarget]] = [:]
        for e in exercises { targets[e.id] = [t("40", "10", "2"), t("40", "10", "1")] }
        let applied = PlanProgressionApplier.apply(
            plan: .init(exercises: exercises, setTargets: targets), history: ExerciseHistoryIndex(),
            energy: 6, feedback: nil, coach: ctx())
        let total = applied.exercises.reduce(0) { $0 + (applied.setTargets[$1.id]?.filter { $0.isWarmup != true }.count ?? 0) }
        XCTAssertLessThanOrEqual(total, PlanGuardrails.maxHardSetsPerMuscle)
        XCTAssertFalse(applied.safeguards.isEmpty)
        XCTAssertEqual(applied.exercises.map(\.orderIndex), Array(applied.exercises.indices))
    }

    func testHeavyCompoundsAreMovedAheadOfIsolation() {
        let wid = UUID()
        let fly = Exercise.create(workoutId: wid, name: "Cable Fly", muscleGroup: "Chest", orderIndex: 0, targetSets: 2,
                                  targetReps: nil, targetRir: nil, restSeconds: nil, coachNote: nil)
        let row = Exercise.create(workoutId: wid, name: "Barbell Row", muscleGroup: "Back", orderIndex: 1, targetSets: 3,
                                  targetReps: nil, targetRir: nil, restSeconds: nil, coachNote: nil)
        let applied = PlanProgressionApplier.apply(
            plan: .init(exercises: [fly, row], setTargets: [:]), history: ExerciseHistoryIndex(),
            energy: 6, feedback: nil, coach: ctx())
        XCTAssertEqual(applied.exercises.map(\.name), ["Barbell Row", "Cable Fly"])
        XCTAssertTrue(applied.safeguards.contains { $0.contains("Barbell Row") })
    }

    func testGuardrailsCapHeavySetsAndAssignRoles() {
        let four = (0..<4).map { _ in t("200", "5", "2") }
        let capped = PlanGuardrails.capHeavySets(four, step: 5)
        XCTAssertTrue(capped.changed)
        XCTAssertEqual(capped.targets.filter { (Double($0.prefillWeight) ?? 0) >= 190 }.count, 2)
        let out = PlanGuardrails.apply(name: "Barbell Row", targets: [t("100", "8", "2"), t("100", "8", "2"), t("100", "8", "2")],
                                       allowWarmups: false, bestWeight: 100, workingSetCap: 3)
        XCTAssertEqual(out.targets.filter { (Double($0.prefillWeight) ?? 0) >= 95 }.count, 2)
        XCTAssertTrue(out.report.adjustedByGuardrails)

        let roles = PlanGuardrails.withRolesAndRest([t("60", "10", "5"), t("100", "10", "2"), t("125", "6", "1"), t("115", "8", "2")].enumerated().map { i, x in
            var y = x; if i == 0 { y.isWarmup = true }; return y
        }, cls: .heavyCompound, focus: .hypertrophy, restPreference: 90)
        XCTAssertEqual(roles.map(\.resolvedRole), [.warmup, .ramp, .top, .backoff])
        XCTAssertEqual(roles.compactMap(\.restSeconds), [60, 90, 120, 90])
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
