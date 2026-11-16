import XCTest
@testable import Lightstack

/// The golden scenario (Push requested 5 hours after a Push session, deep deficit) as full plan-prompt inputs:
/// sessions with logged sets, stored coach documents (reviews, decisions with outcomes, memory notes), a goal,
/// fuel numbers and a realistic exercise library. `GoldenScenario` supplies the lifts and their history.
enum GoldenPrompt {

    static let userId = UUID()

    struct Inputs {
        var sessions: [Workout]
        var exercises: [UUID: [Exercise]]
        var logged: [UUID: [WorkoutSet]]
        var best: [String: (weightLbs: Double, reps: Int)]
        var library: [String]
        var rolling: String
        var reviews: [CoachReviewEntry]
        var memory: CoachMemoryIndex
        var briefs: [ExerciseBrief]
        var muscleLoad: [String: MuscleLoad]
        var fuel: CoachFuelSummary
        var goalItems: [GoalPlanItem]
        var draft: [DraftExercise]
        var coach: PlanCoachContext
        var history: ExerciseHistoryIndex
    }

    static let library: [String] = [
        "Smith Machine Flat Bench Press", "Single Arm Pec Fly Machine", "Dumbbell Lateral Raises",
        "EZ Bar Tricep cable overhead press", "Barbell Bench Press", "Incline Dumbbell Press", "Cable Crossover",
        "Overhead Press", "Seated Dumbbell Shoulder Press", "Rope Pushdown", "Skullcrushers", "Dips",
        "Lat Pulldown", "Seated Cable Row", "Barbell Row", "Pull-ups", "Face Pulls", "Dumbbell Curl", "Hammer Curl",
        "Preacher Curl", "Cable Curl", "Back Squat", "Leg Press", "Romanian Deadlift", "Leg Curl", "Leg Extension",
        "Calf Raise", "Hip Thrust", "Walking Lunge", "Bulgarian Split Squat", "Deadlift", "T-Bar Row",
        "Chest Supported Row", "Rear Delt Fly", "Cable Lateral Raise", "Incline Bench Press", "Pec Deck",
        "Machine Shoulder Press", "Hack Squat", "Goblet Squat", "Ab Wheel", "Hanging Leg Raise", "Cable Crunch",
        "Plank", "Farmer Carry", "Shrugs", "Upright Row", "Close Grip Bench Press", "Machine Row", "Straight Arm Pulldown",
        "Single Arm Cable Row", "Concentration Curl", "Reverse Curl", "Wrist Curl", "Tricep Kickback", "Bench Dips",
        "Decline Press", "Landmine Press", "Arnold Press", "Front Raise", "Reverse Pec Deck", "Sumo Deadlift",
        "Stiff Leg Deadlift", "Good Morning", "Sissy Squat", "Step Up", "Seated Calf Raise", "Glute Bridge",
        "Hip Abduction", "Hip Adduction", "Back Extension", "Cable Pull Through", "Treadmill", "Rowing Machine",
        "Stair Climber", "Cycling", "Elliptical", "Jump Rope", "Battle Ropes", "Box Jump", "Kettlebell Swing"]

    static func workout(_ date: Date, note: CoachReviewDocument?) -> Workout {
        var w = Workout.create(userId: userId, workoutType: "Push", energyLevel: 6, timeAvailableMinutes: 45, date: date)
        w.aiProgressionNote = note?.encoded()
        return w
    }

    static func decision(_ name: String, _ muscle: String, top: PrescribedSet, reason: String, outcome: DecisionOutcome?) -> CoachDecision {
        CoachDecision(name: name, muscle: muscle, target: top, sets: [top], reason: reason,
                      context: "last \(top.text), energy 6", source: "engine", outcome: outcome)
    }

    static func outcome(_ result: ExerciseOutcome, _ actual: String, hit: Bool = true) -> DecisionOutcome {
        DecisionOutcome(hit: hit, actualTop: actual, rir: 1, shortBy: hit ? 0 : 1, result: result)
    }

    static func make() -> Inputs {
        typealias G = GoldenScenario
        // (date, lifts logged that day)
        let days: [(Date, [String: String])] = [
            (G.date(11, 12, hour: G.lastSessionHour), G.loggedOn1112),
            (G.date(11, 3), [G.fly: "165x8, 165x7", G.triceps: "50x15, 57.5x11"]),
            (G.date(10, 28), [G.bench: "175x5, 185x6, 180x5", G.fly: "165x8, 155x8", G.laterals: "25x12, 25x9", G.triceps: "50x10"]),
            (G.date(10, 23), [G.fly: "160x10, 160x10", G.laterals: "25x11, 25x11", G.triceps: "50x10, 50x10"]),
            (G.date(10, 20), [G.bench: "185x6, 185x6, 180x5", G.fly: "160x9, 160x7", G.laterals: "25x10, 25x8", G.triceps: "50x9"])]

        let p = { (role: SetRole, w: Double, r: Int, rir: Int) in PrescribedSet(role: role, weight: w, reps: r, rir: rir, restSeconds: 90) }
        var sessions: [Workout] = []
        var exercises: [UUID: [Exercise]] = [:]
        var logged: [UUID: [WorkoutSet]] = [:]
        var docs: [Date: CoachReviewDocument] = [:]

        for (date, lifts) in days {
            var doc = CoachReviewDocument()
            doc.prescription = date == G.date(11, 12, hour: G.lastSessionHour) ? G.prescription1112 : []
            let reviewExercises: [ExerciseReview]
            if date == G.date(11, 12, hour: G.lastSessionHour) {
                doc.decisions = [
                    decision(G.bench, "Chest", top: p(.top, 185, 6, 2), reason: "Last 185x6@1 on 10/28, trend flat, hold the top set.",
                             outcome: outcome(.close, "185x5@1")),
                    decision(G.fly, "Chest", top: p(.straight, 165, 8, 2), reason: "165x8 and 165x7 on 11/3, repeat the weight.",
                             outcome: outcome(.close, "165x7@1")),
                    decision(G.laterals, "Shoulders", top: p(.straight, 25, 9, 2), reason: "25x12 then 25x9 on 10/28, 9 reps at the same weight.",
                             outcome: outcome(.hold, "25x9@2")),
                    decision(G.triceps, "Triceps", top: p(.straight, 52.5, 12, 2), reason: "50x15 then 57.5x11 on 11/3, 52.5 in between.",
                             outcome: outcome(.hold, "50x12@2"))]
                reviewExercises = [
                    ExerciseReview(name: G.bench, notes: "Top set 185x5 at RIR 1, one rep short of 6, counts as on target. First session back after 15 days.",
                                   outcome: .close, nextTarget: NextTarget(weight: 185, reps: 6, note: "retry the same target"), missAnalysis: nil,
                                   memoryNote: "Strong at 185 for 5-6. Retry 185x6 before adding load."),
                    ExerciseReview(name: G.fly, notes: "165x7 at RIR 1, one short of 8. Close.", outcome: .close,
                                   nextTarget: NextTarget(weight: 165, reps: 8, note: nil), missAnalysis: nil, memoryNote: nil),
                    ExerciseReview(name: G.laterals, notes: "25x9 twice at RIR 2 as planned.", outcome: .hold,
                                   nextTarget: NextTarget(weight: 25, reps: 10, note: nil), missAnalysis: nil, memoryNote: nil),
                    ExerciseReview(name: G.triceps, notes: "Did 50x12@2; planned 52.5 which the stack does not have.", outcome: .hold,
                                   nextTarget: NextTarget(weight: 50, reps: 13, note: nil), missAnalysis: nil, memoryNote: "Stack jumps 50 to 57.5.")]
                doc.review = SessionReview(
                    exercises: reviewExercises,
                    overallRead: "4 of 4 lifts on target after a 15 day break from bench. Fuel was low this week, so keep loads steady.",
                    recurringFlags: ["Triceps weight 52.5 does not exist on the stack"], createdAt: nil, aiAuthored: true)
            } else {
                doc.decisions = lifts.keys.sorted().map { name in
                    decision(name, G.muscleGroups[name] ?? "", top: p(.top, 100, 8, 2), reason: "Repeat last weight and add a rep.",
                             outcome: outcome(.hold, "100x8@2"))
                }
                doc.review = SessionReview(
                    exercises: lifts.keys.sorted().map { ExerciseReview(name: $0, notes: "Hit the planned top set, moving up next time.", outcome: .hold,
                                                                         nextTarget: NextTarget(weight: 100, reps: 9, note: nil), missAnalysis: nil, memoryNote: nil) },
                    overallRead: "Solid session, loads moved up where reps allowed.", recurringFlags: [], createdAt: nil, aiAuthored: true)
            }
            docs[date] = doc
            let w = workout(date, note: doc)
            sessions.append(w)
            var list: [Exercise] = []
            for (index, name) in G.order.enumerated() {
                guard let text = lifts[name] else { continue }
                let ex = Exercise.create(workoutId: w.id, name: name, muscleGroup: G.muscleGroups[name] ?? "", orderIndex: index,
                                         targetSets: 2, targetReps: nil, targetRir: nil, restSeconds: 90, coachNote: nil)
                list.append(ex)
                logged[ex.id] = G.sets(text).enumerated().map {
                    WorkoutSet.create(exerciseId: ex.id, setNumber: $0.offset + 1, weightLbs: $0.element.weight, reps: $0.element.reps, rir: $0.element.rir)
                }
            }
            exercises[w.id] = list
        }

        let history = G.historyForPlanRequest
        let coach = G.planContext()
        let draft = G.baselinePlan()
        let reviews = CoachReviewStore.latestReviews(from: sessions, workoutType: "Push", limit: CoachContextBuilder.reviewCount)
        let briefs = ExerciseBriefBuilder.briefs(sessions: sessions, exercises: exercises, loggedSets: logged)

        let goal = CoachGoal(exerciseName: G.bench, targetWeight: 205, targetReps: 3, deadline: G.date(12, 20),
                             steps: [CoachGoalStep(date: nil, text: "185x6 clean, then 190x5", weight: 190, reps: 5)])
        let points = GoalAssessor.topPoints(from: history.group(for: G.bench)?.sessions ?? [])
        let item = GoalPlanItem(
            goal: goal,
            assessment: GoalAssessor.assess(exercise: G.bench, targetWeight: 205, targetReps: 3, history: points, now: G.planRequestTime),
            step: goal.steps.first, stepIsToday: true)

        let week = FuelWeek(loggedDays: 7, avgKcal: 1302, avgProtein: 44, avgCarbs: 120, avgFat: 40,
                            avgTargetKcal: 1852, avgTargetProtein: 160, daysOnTarget: 0, daysWithTarget: 7)
        let fuel = CoachFuelSummary(
            yesterdayKcal: 1250, targetKcal: 1852, proteinG: 41, targetProteinG: 160, goal: "lose", weeklyRate: 0.5,
            today: FuelToday(kcalSoFar: 450, proteinSoFar: 20, targetKcal: 1852, targetProteinG: 160, timeLabel: "1:00pm", hasEntries: true),
            last7: week, weightTrend14: -1.1, weightTrend30: -0.8, carbsLast24h: 90, dataQuality: .good)

        let load = ["chest": MuscleLoad(thisWeekSets: 9, avgPrior3WeeksSets: 8, daysSince: 0),
                    "triceps": MuscleLoad(thisWeekSets: 8, avgPrior3WeeksSets: 7, daysSince: 0),
                    "shoulders": MuscleLoad(thisWeekSets: 6, avgPrior3WeeksSets: 6, daysSince: 0)]
        return Inputs(
            sessions: sessions, exercises: exercises, logged: logged, best: [:], library: library,
            rolling: "Push sessions are consistent: bench around 185 for 5-6, fly 165 for 7-8, laterals 25 for 9-12, triceps cable 50 to 57.5. "
                + "Recovery is fine, energy 6 on average, rests often run longer than prescribed on heavy sets.",
            reviews: reviews, memory: CoachMemoryIndex(workouts: sessions), briefs: briefs, muscleLoad: load, fuel: fuel,
            goalItems: [item], draft: draft, coach: coach, history: history)
    }
}

extension GoldenPrompt {

    static let service = CoachPromptService(validationService: ValidationService())

    /// The plan user message for the golden scenario, built the way `WorkoutSessionService` builds it.
    static func message(_ i: Inputs = make()) -> String {
        let draft = i.draft
        let recency = PlanDraftBuilder.recencyWarning(for: draft, coach: i.coach)
        let extras = CoachPromptService.PlanPromptExtras(
            focus: .hypertrophy, constraints: nil, draft: draft,
            estimatedMinutes: PlanDraftBuilder.estimatedMinutes(draft),
            reviews: i.reviews, recency: i.coach.recency, now: i.coach.now,
            recencyNote: recency?.promptNote,
            briefs: i.briefs, muscleLoad: i.muscleLoad, usualMinutes: 45,
            fuelBlock: service.fuelBlock(i.fuel), mealsBlock: nil,
            memory: i.memory, memoryLifts: [],
            goalsBlock: service.goalsBlock(i.goalItems, now: GoldenScenario.planRequestTime))
        return service.buildWorkoutRequestMessage(
            workoutType: "Push", time: 45, energy: 6, notes: nil, rollingSummary: i.rolling,
            recentSessions: i.sessions, recentSessionExercises: i.exercises, recentLoggedSets: i.logged,
            bestSets: i.best, exerciseLibrary: i.library, coach: extras)
    }
}

final class CoachPromptBudgetTests: XCTestCase {

    /// The user message of the OLD builder (coach v3: every fact in up to five blocks, 80 exercise names, rolling context)
    /// for the golden scenario, measured from the code as it was before the context diet: 8,917 characters.
    static let oldGoldenMessageCharacters = 8_917

    func testGoldenUserMessageIsAtMost60PercentOfTheOldOne() {
        let message = GoldenPrompt.message()
        print("NEW-MESSAGE-COUNT \(message.count) (old \(Self.oldGoldenMessageCharacters))")
        print("NEW-MESSAGE-BEGIN\n\(message)\nNEW-MESSAGE-END")
        XCTAssertLessThanOrEqual(Double(message.count), Double(Self.oldGoldenMessageCharacters) * 0.6, "\(message.count) characters")
    }

    func testGoldenUserMessageStillHasEverythingTheDecisionsNeed() {
        let message = GoldenPrompt.message()
        // The recency note leads.
        XCTAssertTrue(message.hasPrefix("NOTE: chest, shoulders and arms were trained about 5 hours ago; the app has already held or reduced those lifts."), message)
        // Each lift: last top set, planned vs did, the draft's top.
        for needle in ["185x5@1", "170x5@1", "planned 95x10@5, 150x10@2, 185x6@2, 170x7@2", "did 95x10@5, 150x10@2, 185x5@1, 170x5@1",
                       "165x7@1", "25x9@2", "50x12@2", "planned 52.5x12@2",
                       "top set 175x5@2", "set 25x9@2", "set 50x12@2"] {
            XCTAssertTrue(message.contains(needle), "missing \(needle)\n\(message)")
        }
        // Fuel numbers, the goal step, memory outcomes.
        for needle in ["FUEL: data good", "1302/1852 kcal", "P44/160", "205x3", "185x6 clean, then 190x5", "CLOSE (on target)", "-> 185x5@1"] {
            XCTAssertTrue(message.contains(needle), "missing \(needle)\n\(message)")
        }
        // Facts are not repeated block after block.
        XCTAssertFalse(message.contains("ROLLING CONTEXT"), "previous reviews exist")
        XCTAssertFalse(message.contains("EARLIER TREND"))
        XCTAssertFalse(message.contains("PRESCRIBED vs ACTUAL"))
        XCTAssertEqual(message.components(separatedBy: "FUEL: data good").count - 1, 1)
        XCTAssertFalse(message.contains("Back Squat"), "names are limited to the muscles of today's workout")
        XCTAssertFalse(message.contains("Lat Pulldown"))
    }

    func testExerciseNamesAreLimitedToTodaysMusclesAndCapped() {
        let message = GoldenPrompt.message()
        let line = message.components(separatedBy: "ATHLETE'S EXERCISE NAMES").last?
            .components(separatedBy: "\n").dropFirst().first ?? ""
        let names = line.components(separatedBy: "; ")
        XCTAssertLessThanOrEqual(names.count, CoachPromptService.libraryLimit)
        XCTAssertTrue(names.contains("Incline Dumbbell Press"), line)
        XCTAssertFalse(names.contains("Smith Machine Flat Bench Press"), "draft lifts are not repeated")
    }

    func testPreviousReviewsShowTheLatestInDetailAndTheOneBeforeInOneLine() {
        let message = GoldenPrompt.message()
        XCTAssertTrue(message.contains("[11/12] Push: 4 of 4 lifts on target"))
        XCTAssertTrue(message.contains("flags: Triceps weight 52.5 does not exist on the stack"))
        XCTAssertTrue(message.contains("[11/03] Push: Solid session, loads moved up where reps allowed."))
        XCTAssertFalse(message.contains("[10/28] Push"), "only two reviews are shown")
    }
}
