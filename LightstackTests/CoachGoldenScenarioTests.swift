import XCTest
@testable import Lightstack

/// The real case from 2026-11-12/13: a Push session finished at ~08:00 and a new Push plan was requested ~5 hours later,
/// in a deep nutrition deficit. `GoldenScenario` is the reusable history builder: extend it for new coach tests.
enum GoldenScenario {

    static let bench = "Smith Machine Flat Bench Press"
    static let fly = "Single Arm Pec Fly Machine"
    static let laterals = "Dumbbell Lateral Raises"
    static let triceps = "EZ Bar Tricep cable overhead press"

    static func date(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)) ?? Date()
    }

    /// "185x6@1, 170x5" -> sets (RIR optional).
    static func sets(_ text: String) -> [HistorySet] {
        text.split(separator: ",").map { token in
            let parts = token.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0 == "x" || $0 == "@" })
            return HistorySet(Double(parts[0]) ?? 0, Int(parts[1]) ?? 0, rir: parts.count > 2 ? Int(parts[2]) : nil)
        }
    }

    static func session(_ month: Int, _ day: Int, _ text: String, hour: Int = 12) -> HistorySession {
        HistorySession(date: date(month, day, hour: hour), sets: sets(text))
    }

    /// The 11/12 session as logged (the morning session, 08:00).
    static let lastSessionHour = 8
    static var loggedOn1112: [String: String] {
        [bench: "95x10@5, 150x10@2, 185x5@1, 170x5@1",
         fly: "165x7@1, 150x5@1",
         laterals: "25x9@2, 25x9@2",
         triceps: "50x12@2, 50x12@2"]
    }

    /// Sessions BEFORE 11/12, newest first. The triceps cable also shows an older 42.5 so its 7.5 ladder is learnable.
    static var before1112: [String: [HistorySession]] {
        [bench: [session(10, 28, "175x5, 185x6, 180x5"), session(10, 20, "185x6, 185x6, 180x5")],
         fly: [session(11, 3, "165x8, 165x7"), session(10, 28, "165x8, 155x8"), session(10, 23, "160x10, 160x10"),
               session(10, 20, "160x9, 160x7")],
         laterals: [session(10, 28, "25x12, 25x9"), session(10, 23, "25x11, 25x11"), session(10, 20, "25x10, 25x8")],
         triceps: [session(11, 3, "50x15, 57.5x11"), session(10, 28, "50x10"), session(10, 23, "50x10, 50x10"),
                   session(10, 20, "50x9"), session(10, 13, "42.5x12, 42.5x12")]]
    }

    /// 11/12 as a history session at `hour`.
    static func session1112(_ name: String, hour: Int = lastSessionHour) -> HistorySession {
        HistorySession(date: date(11, 12, hour: hour), sets: sets(loggedOn1112[name] ?? ""))
    }

    static let order = [bench, fly, laterals, triceps]
    static let muscleGroups = [bench: "Chest", fly: "Chest", laterals: "Shoulders", triceps: "Triceps"]

    private static func best(_ sessions: [HistorySession]) -> HistorySet? {
        ExerciseHistoryIndex.bestLogged(in: sessions)
    }

    /// History as the plan request sees it (11/12 included, newest first).
    static var historyForPlanRequest: ExerciseHistoryIndex {
        ExerciseHistoryIndex(groups: order.map { name in
            let sessions = [session1112(name)] + (before1112[name] ?? [])
            return ExerciseHistoryGroup(names: [name], sessions: sessions, best: best(sessions),
                                        latestSessionDate: date(11, 12, hour: lastSessionHour))
        })
    }

    /// History as the 11/12 review sees it (11/12 not included yet).
    static var historyForReview: ExerciseHistoryIndex {
        ExerciseHistoryIndex(groups: order.map { name in
            let sessions = before1112[name] ?? []
            return ExerciseHistoryGroup(names: [name], sessions: sessions, best: best(sessions),
                                        latestSessionDate: date(11, 3))
        })
    }

    /// What the plan asked for on 11/12.
    static var prescription1112: [ExercisePrescription] {
        func p(_ role: SetRole, _ w: Double, _ r: Int, _ rir: Int) -> PrescribedSet {
            PrescribedSet(role: role, weight: w, reps: r, rir: rir, restSeconds: 90)
        }
        return [
            ExercisePrescription(name: bench, muscleGroup: "Chest", sets: [
                p(.warmup, 95, 10, 5), p(.ramp, 150, 10, 2), p(.top, 185, 6, 2), p(.backoff, 170, 7, 2)]),
            ExercisePrescription(name: fly, muscleGroup: "Chest", sets: [p(.straight, 165, 8, 2), p(.straight, 165, 8, 2)]),
            ExercisePrescription(name: laterals, muscleGroup: "Shoulders", sets: [p(.straight, 25, 9, 2), p(.straight, 25, 9, 2)]),
            ExercisePrescription(name: triceps, muscleGroup: "Triceps", sets: [p(.straight, 52.5, 12, 2), p(.straight, 52.5, 12, 2)])
        ]
    }

    /// The 11/12 session analysed the way the finish flow does (finished 09:30 the same day).
    static func analysisOf1112(energy: Int = 6) -> SessionAnalysis {
        SessionAnalyzer.analyze(
            logged: order.map { LoggedExercise(name: $0, muscleGroup: muscleGroups[$0] ?? "", sets: sets(loggedOn1112[$0] ?? "")) },
            prescription: prescription1112, energy: energy, userNote: nil, reasons: [:], previous: [],
            history: historyForReview, focus: .hypertrophy, now: date(11, 12, hour: 9))
    }

    /// 13:00 on 11/12, 5 hours after the session: chest 5 hard sets, shoulders 2, triceps 2; and a deep deficit.
    static let planRequestTime = date(11, 12, hour: 13)

    static var recency: [String: MuscleRecency] {
        let t = date(11, 12, hour: lastSessionHour)
        return ["chest": MuscleRecency(lastTrained: t, hardSets: 5),
                "shoulders": MuscleRecency(lastTrained: t, hardSets: 2),
                "triceps": MuscleRecency(lastTrained: t, hardSets: 2)]
    }

    /// 7-day average 1302 of 1852 kcal and 44 of 160 g protein.
    static var deficitAssessment: FuelAssessment {
        let week = FuelWeek(loggedDays: 7, avgKcal: 1302, avgProtein: 44, avgCarbs: 120, avgFat: 40,
                            avgTargetKcal: 1852, avgTargetProtein: 160, daysOnTarget: 0, daysWithTarget: 7)
        return FuelRules.assess(fuel: CoachFuelSummary(last7: week, dataQuality: .good), meals: nil)
    }

    static func planContext(withFuel: Bool = true, now: Date = planRequestTime) -> PlanCoachContext {
        var c = PlanCoachContext()
        c.now = now
        c.recency = recency
        c.fuelHold = withFuel ? deficitAssessment : nil
        return c
    }

    /// The Push exercises of 11/12 in plan order (the engine's draft is built from these).
    static func lastSessionExercises() -> [Exercise] {
        let workoutId = UUID()
        return order.enumerated().map { index, name in
            Exercise.create(workoutId: workoutId, name: name, muscleGroup: muscleGroups[name] ?? "", orderIndex: index,
                            targetSets: 2, targetReps: nil, targetRir: nil, restSeconds: 90, coachNote: nil)
        }
    }

    /// The engine's full baseline for the same-day Push request.
    static func baselinePlan(withFuel: Bool = true) -> [DraftExercise] {
        PlanDraftBuilder.build(lastSessionExercises: lastSessionExercises(), history: historyForPlanRequest, energy: 6,
                               feedback: nil, coach: planContext(withFuel: withFuel), timeMinutes: nil)
    }
}

final class CoachGoldenScenarioTests: XCTestCase {

    private func plan(_ draft: [DraftExercise], _ name: String) throws -> ProgressionResult {
        try XCTUnwrap(draft.first { $0.name == name }?.result, name)
    }

    // MARK: - Same-day plan

    func testBaselinePlanNeverProgressesAfterTheSameDaySession() throws {
        let draft = GoldenScenario.baselinePlan()
        XCTAssertEqual(draft.count, 4)

        let bench = try plan(draft, GoldenScenario.bench)
        let top = try XCTUnwrap(bench.topSet)
        XCTAssertLessThanOrEqual(top.weight, 185, "never above last session's top")
        XCTAssertGreaterThanOrEqual(top.weight, 175)
        XCTAssertLessThanOrEqual(top.reps, 5, "reps never above last session's reps")
        // Back-off, when there is one, may not jump from 170x5@1 to 170x8.
        for set in bench.workingSets where abs(set.weight - 170) <= 5 { XCTAssertLessThanOrEqual(set.reps, 6) }
        XCTAssertNotNil(bench.noProgressReason)

        let fly = try plan(draft, GoldenScenario.fly)
        for set in fly.sets { XCTAssertLessThanOrEqual(set.weight, 165); XCTAssertLessThanOrEqual(set.reps, 7) }

        let triceps = try plan(draft, GoldenScenario.triceps)
        for set in triceps.sets {
            XCTAssertEqual(set.weight, 50, "52.5 and 57.5 are both off the table: held at 50")
            XCTAssertLessThanOrEqual(set.reps, 12)
        }

        let laterals = try plan(draft, GoldenScenario.laterals)
        for set in laterals.sets { XCTAssertEqual(set.weight, 25); XCTAssertLessThanOrEqual(set.reps, 10) }
    }

    /// Prints the whole baseline so a reviewer can read it in the test log (GOLDEN-PLAN lines).
    func testBaselinePlanIsReadable() {
        for ex in GoldenScenario.baselinePlan() {
            print("GOLDEN-PLAN \(ex.name): " + ex.result.sets.map(\.text).joined(separator: " | ")
                  + " || \(ex.result.rationale)")
        }
        print("GOLDEN-WARNING " + (PlanDraftBuilder.recencyWarning(for: GoldenScenario.baselinePlan(),
                                                                 coach: GoldenScenario.planContext())?.message ?? "none"))
        print("GOLDEN-READ " + SessionAnalyzer.deterministicOverallRead(GoldenScenario.analysisOf1112(), workoutType: "Push"))
        for a in GoldenScenario.analysisOf1112().exercises { print("GOLDEN-REVIEW \(a.name): \(a.outcome.rawValue) | \(a.note)") }
    }

    func testBaselineNeverEmitsAWeightTheLadderDoesNotHave() throws {
        for ex in GoldenScenario.baselinePlan() {
            let ladder = WeightIncrements.learned(name: ex.name, group: GoldenScenario.historyForPlanRequest.group(for: ex.name))
            for set in ex.result.sets {
                XCTAssertTrue(ladder.isOnLadder(set.weight), "\(ex.name) \(set.weight) is not on its ladder")
            }
        }
    }

    func testRecencyWarningNamesTheMusclesAndTheHours() {
        let warning = PlanDraftBuilder.recencyWarning(for: GoldenScenario.baselinePlan(), coach: GoldenScenario.planContext())
        XCTAssertEqual(warning?.message, "You trained chest, shoulders and arms about 5 hours ago.")
        XCTAssertEqual(warning?.muscles, ["chest", "shoulders", "arms"])
        // Two days later nothing is flagged.
        let later = PlanDraftBuilder.recencyWarning(
            for: GoldenScenario.baselinePlan(), coach: GoldenScenario.planContext(now: GoldenScenario.date(11, 14, hour: 13)))
        XCTAssertNil(later)
    }

    func testFuelDeficitAloneAlsoHoldsEverything() throws {
        // Next morning (not "very recent"), but still in a deep deficit: nothing progresses.
        var coach = GoldenScenario.planContext(now: GoldenScenario.date(11, 14, hour: 9))
        coach.recency = [:]
        let draft = PlanDraftBuilder.build(lastSessionExercises: GoldenScenario.lastSessionExercises(),
                                           history: GoldenScenario.historyForPlanRequest, energy: 6, feedback: nil,
                                           coach: coach, timeMinutes: nil)
        let bench = try plan(draft, GoldenScenario.bench)
        XCTAssertLessThanOrEqual(try XCTUnwrap(bench.topSet).weight, 185)
        XCTAssertLessThanOrEqual(try XCTUnwrap(bench.topSet).reps, 5)
        XCTAssertNotNil(bench.noProgressReason)
        XCTAssertTrue(bench.noProgressReason?.contains("fuel") == true, bench.noProgressReason ?? "")
        for set in try plan(draft, GoldenScenario.triceps).sets { XCTAssertEqual(set.weight, 50) }
    }

    func testWithoutAnyHoldTheEngineStillRespectsTheLadder() throws {
        // Two days after, rested and fed: the triceps may progress, but only to a weight that exists.
        var coach = GoldenScenario.planContext(withFuel: false, now: GoldenScenario.date(11, 14, hour: 9))
        coach.recency = [:]
        let draft = PlanDraftBuilder.build(lastSessionExercises: GoldenScenario.lastSessionExercises(),
                                           history: GoldenScenario.historyForPlanRequest, energy: 6, feedback: nil,
                                           coach: coach, timeMinutes: nil)
        let triceps = try plan(draft, GoldenScenario.triceps)
        for set in triceps.sets { XCTAssertTrue([50.0, 57.5].contains(set.weight), "\(set.weight)") }
        XCTAssertFalse(triceps.sets.contains { $0.weight == 52.5 })
    }

    // MARK: - The 11/12 review

    func testSessionOf1112IsOnTargetEverywhereNothingMissed() throws {
        let analysis = GoldenScenario.analysisOf1112()
        func a(_ name: String) throws -> ExerciseAnalysis { try XCTUnwrap(analysis.exercises.first { $0.name == name }) }

        let bench = try a(GoldenScenario.bench)
        XCTAssertEqual(bench.outcome, .close)
        XCTAssertNil(bench.miss)
        XCTAssertEqual(bench.layoffDays, 15, "first session back after 15 days")
        XCTAssertEqual(bench.target, NextTarget(weight: 185, reps: 6, note: "First session back after 15 days: retry the same target"))
        XCTAssertTrue(bench.note.contains("15 days"), bench.note)
        XCTAssertFalse(bench.note.lowercased().contains("strength"), bench.note)

        let fly = try a(GoldenScenario.fly)
        XCTAssertEqual(fly.outcome, .close)
        XCTAssertNil(fly.miss)
        XCTAssertEqual(fly.target?.weight, 165)
        XCTAssertEqual(fly.target?.reps, 8)

        let laterals = try a(GoldenScenario.laterals)
        XCTAssertNil(laterals.miss)
        XCTAssertFalse(laterals.isClose)
        XCTAssertEqual(laterals.shortBy, 0)

        let triceps = try a(GoldenScenario.triceps)
        XCTAssertNil(triceps.miss)
        XCTAssertTrue(triceps.plannedWeightUnavailable)
        XCTAssertEqual(triceps.shortBy, 0)
        XCTAssertTrue(triceps.note.contains("Did 50×12@2; planned 52.5x12@2"), triceps.note)
        XCTAssertFalse(triceps.note.contains("short by"), triceps.note)

        XCTAssertEqual(analysis.missedCount, 0)
        XCTAssertEqual(analysis.onTargetCount, 4)
        let read = SessionAnalyzer.deterministicOverallRead(analysis, workoutType: "Push")
        XCTAssertTrue(read.contains("4 of 4 lifts on target"), read)
        XCTAssertFalse(read.lowercased().contains("missed"), read)
        XCTAssertTrue(SessionAnalyzer.mandatoryFlags(analysis).isEmpty)
    }

    // MARK: - The goal line and the brief show one e1RM

    func testBenchE1RMIsTheSameNumberInTheGoalLineAndTheBrief() throws {
        let sessions = [GoldenScenario.session1112(GoldenScenario.bench)] + (GoldenScenario.before1112[GoldenScenario.bench] ?? [])
        // The brief's trend ends on the newest session (216) and shows 222 for the two before it.
        let brief = try XCTUnwrap(ExerciseBriefBuilder.build(
            name: GoldenScenario.bench, muscleGroup: "Chest",
            sessions: sessions.map { s in
                BriefSession(date: s.date, sets: s.sets.enumerated().map { index, set in
                    WorkoutSet.create(exerciseId: UUID(), setNumber: index + 1, weightLbs: set.weight, reps: set.reps, rir: set.rir)
                }, inSuperset: false, prescription: nil)
            }))
        XCTAssertEqual(brief.e1RMTrend, [222, 222, 216])

        // The goal line's "now" is the recent best: the same 222. (A 230x1 from 10/16 would be 238 and must not leak in.)
        let points = GoalAssessor.topPoints(from: [GoldenScenario.session(10, 16, "110x6@4, 230x1@1")] + sessions.reversed())
        let assessment = try XCTUnwrap(GoalAssessor.assess(exercise: GoldenScenario.bench, targetWeight: 205, targetReps: 3,
                                                           history: points, now: GoldenScenario.date(11, 13)))
        XCTAssertEqual(Int(assessment.currentE1RM.rounded()), 222)
        XCTAssertEqual(Int(assessment.targetE1RM.rounded()), 226)
        XCTAssertEqual(OneRepMax.recentBest(sessions: sessions).map { Int($0.rounded()) }, 222)
    }
}
