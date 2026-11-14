import XCTest
import Supabase
@testable import Lightstack

@MainActor
final class ProgressionContextTests: XCTestCase {

    private var stack: OutboxTestStack!
    private var workouts: WorkoutRepository!
    private var builder: CoachContextBuilder!
    private let prompts = CoachPromptService(validationService: ValidationService())

    override func setUp() {
        super.setUp()
        stack = OutboxTestStack()
        let validation = ValidationService()
        workouts = WorkoutRepository(localStorage: stack.storage, offlineQueueManager: stack.queue)
        let profiles = ProfileRepository(
            localStorage: stack.storage,
            supabaseService: SupabaseServiceFactory.unreachable(),
            offlineQueueManager: stack.queue
        )
        builder = CoachContextBuilder(profileRepository: profiles, workoutRepository: workouts,
                                      localStorage: stack.storage, validationService: validation)
    }

    /// Saves a workout of `type` `daysAgo` days back with one Bench exercise; `sets` are (weight, reps, rir).
    @discardableResult
    private func seed(type: String = "Push", daysAgo: Int, sets: [(Double, Int, Int?)],
                      userNote: String? = nil) -> Workout {
        var w = Workout.create(userId: stack.userId, workoutType: type, energyLevel: 5, timeAvailableMinutes: 45)
        w.date = Date(timeIntervalSinceNow: -Double(daysAgo) * 86_400)
        w.userNote = userNote
        workouts.createWorkout(w)
        let ex = Exercise.create(workoutId: w.id, name: "Bench Press", muscleGroup: "Chest", orderIndex: 0,
                                 targetSets: sets.count, targetReps: "8", targetRir: "2", restSeconds: 90,
                                 coachNote: "Target: 100 lbs — plan only")
        workouts.saveExercises([ex], workoutId: w.id)
        for (i, s) in sets.enumerated() {
            workouts.saveSet(WorkoutSet.create(exerciseId: ex.id, setNumber: i + 1, weightLbs: s.0, reps: s.1, rir: s.2),
                             exerciseId: ex.id)
        }
        return w
    }

    func testHistoryIndexKnowsALiftWasSkippedInTheNewestSession() {
        seed(daysAgo: 8, sets: [(135, 10, 3)])   // Bench
        var newer = Workout.create(userId: stack.userId, workoutType: "Push", energyLevel: 5, timeAvailableMinutes: 45)
        newer.date = Date(timeIntervalSinceNow: -86_400)
        workouts.createWorkout(newer)
        let fly = Exercise.create(workoutId: newer.id, name: "Cable Fly", muscleGroup: "Chest", orderIndex: 0,
                                  targetSets: 1, targetReps: "10", targetRir: "2", restSeconds: 60, coachNote: nil)
        workouts.saveExercises([fly], workoutId: newer.id)
        workouts.saveSet(WorkoutSet.create(exerciseId: fly.id, setNumber: 1, weightLbs: 40, reps: 10, rir: 2), exerciseId: fly.id)

        let ctx = builder.buildContext(userId: stack.userId, workoutType: "Push")
        let index = ExerciseHistoryIndex(sessions: ctx.recentSessions, exercises: ctx.recentSessionSets,
                                         loggedSets: ctx.recentLoggedSets, bestSets: ctx.bestSets)
        XCTAssertEqual(index.group(for: "Bench Press")?.skippedLastSession, true)
        XCTAssertEqual(index.group(for: "Cable Fly")?.skippedLastSession, false)
    }

    func testContextSkipsEmptyWorkoutsAndKeepsLastFiveCompleted() {
        seed(daysAgo: 0, sets: [])   // pending / abandoned: no logged sets
        for d in 1...6 { seed(daysAgo: d, sets: [(135, 10, 3)]) }
        seed(type: "Pull", daysAgo: 1, sets: [(95, 8, 2)])

        let ctx = builder.buildContext(userId: stack.userId, workoutType: "Push")
        XCTAssertEqual(ctx.recentSessions.count, 5)
        XCTAssertTrue(ctx.recentSessions.allSatisfy { $0.workoutType == "Push" })
        XCTAssertTrue(ctx.recentSessions.allSatisfy { !(ctx.recentSessionSets[$0.id] ?? []).isEmpty })
        XCTAssertEqual(ctx.recentSessions.map(\.id), ctx.recentSessions.sorted { $0.date > $1.date }.map(\.id))
    }

    func testRenderedHistoryHasActualPerSetDataAndNotes() {
        seed(daysAgo: 3, sets: [(135, 10, 3), (155, 8, 2), (165, 6, 1)], userNote: "left shoulder tweaky")
        let ctx = builder.buildContext(userId: stack.userId, workoutType: "Push")
        let message = prompts.buildWorkoutRequestMessage(
            workoutType: "Push", time: 45, energy: 6, notes: nil,
            rollingSummary: ctx.rollingSummary, recentSessions: ctx.recentSessions,
            recentSessionExercises: ctx.recentSessionSets, recentLoggedSets: ctx.recentLoggedSets,
            bestSets: ctx.bestSets)
        XCTAssertTrue(message.contains("Bench Press: 135x10@3, 155x8@2, 165x6@1"), message)
        XCTAssertTrue(message.contains("Athlete note after the last session: left shoulder tweaky"), message)
        XCTAssertTrue(message.contains("note: plan only"))
        XCTAssertFalse(message.contains("Estimate target_weight"))
        XCTAssertFalse(message.contains("sets x"), "planned targets are no longer rendered")
    }

    func testPostWorkoutMessageIncludesPreviousSummary() {
        let ex = Exercise.create(workoutId: UUID(), name: "Bench Press", muscleGroup: "Chest", orderIndex: 0,
                                 targetSets: 1, targetReps: nil, targetRir: nil, restSeconds: nil, coachNote: nil)
        let sets = [ex.id: [WorkoutSet.create(exerciseId: ex.id, setNumber: 1, weightLbs: 155, reps: 8, rir: 2)]]
        let with = prompts.buildPostWorkoutMessage(workoutType: "Push", exercises: [ex], sets: sets,
                                                   previousSummary: "Bench 150x8@2, next 155.")
        XCTAssertTrue(with.contains("Previous rolling summary: Bench 150x8@2, next 155."))
        XCTAssertTrue(with.contains("Bench Press: 155x8@2"))
        let without = prompts.buildPostWorkoutMessage(workoutType: "Push", exercises: [ex], sets: sets)
        XCTAssertFalse(without.contains("Previous rolling summary"))
    }

    // MARK: - Coach brief

    /// Logged sets for one exercise: (weight, reps, rir, seconds after `start`).
    private func timedSets(_ specs: [(Double, Int, Int?, Double)],
                           start: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> [WorkoutSet] {
        let id = UUID()
        return specs.enumerated().map { i, spec in
            var s = WorkoutSet.create(exerciseId: id, setNumber: i + 1, weightLbs: spec.0, reps: spec.1, rir: spec.2)
            s.recordedAt = start.addingTimeInterval(spec.3)
            return s
        }
    }

    func testRestStatsDropIdenticalTimestampsAndLongBreaks() {
        let sets = timedSets([(100, 8, 2, 0), (100, 8, 2, 0), (100, 8, 2, 120), (100, 8, 2, 800)])
        let stats = ExerciseBriefBuilder.restStats([BriefSession(date: Date(), sets: sets, inSuperset: false, prescription: nil)])
        XCTAssertEqual(stats.samples, 1, "0 s and 680 s gaps are dropped")
        XCTAssertEqual(stats.heavyActual, 120)
        XCTAssertNil(stats.lightActual)
    }

    func testRestStatsSkipSupersets() {
        let sets = timedSets([(100, 8, 2, 0), (100, 8, 2, 90), (100, 8, 2, 180)])
        let stats = ExerciseBriefBuilder.restStats([BriefSession(date: Date(), sets: sets, inSuperset: true, prescription: nil)])
        XCTAssertTrue(stats.isEmpty)
        XCTAssertNil(stats.heavyActual)
    }

    func testRestStatsSplitHeavyAndLightWithPrescribedRest() {
        let sets = timedSets([(200, 5, 1, 0), (120, 12, 2, 200), (120, 12, 2, 290), (120, 12, 2, 380)])
        let rx = ExercisePrescription(name: "Bench Press", muscleGroup: "Chest", sets: [
            PrescribedSet(role: .top, weight: 200, reps: 5, rir: 1, restSeconds: 150),
            PrescribedSet(role: .straight, weight: 120, reps: 12, rir: 2, restSeconds: 60),
            PrescribedSet(role: .straight, weight: 120, reps: 12, rir: 2, restSeconds: 60),
            PrescribedSet(role: .straight, weight: 120, reps: 12, rir: 2, restSeconds: 60)
        ])
        let stats = ExerciseBriefBuilder.restStats([BriefSession(date: Date(), sets: sets, inSuperset: false, prescription: rx)])
        XCTAssertEqual(stats.samples, 3)
        XCTAssertEqual(stats.heavyActual, 200)
        XCTAssertEqual(stats.heavyPrescribed, 150)
        XCTAssertEqual(stats.lightActual, 90)
        XCTAssertEqual(stats.lightPrescribed, 60)
    }

    func testStyleBucketsFollowMedianTopSetReps() {
        XCTAssertEqual(LiftStyle.from(medianReps: 5), .heavyLow)
        XCTAssertEqual(LiftStyle.from(medianReps: 6), .heavyLow)
        XCTAssertEqual(LiftStyle.from(medianReps: 7), .moderate)
        XCTAssertEqual(LiftStyle.from(medianReps: 11), .moderate)
        XCTAssertEqual(LiftStyle.from(medianReps: 12), .lightHigh)

        let older = BriefSession(date: Date(timeIntervalSinceNow: -7 * 86_400),
                                 sets: timedSets([(195, 6, 2, 0), (195, 6, 2, 150)]), inSuperset: false, prescription: nil)
        let newer = BriefSession(date: Date(timeIntervalSinceNow: -1 * 86_400),
                                 sets: timedSets([(200, 5, 1, 0), (200, 5, 1, 150)]), inSuperset: false, prescription: nil)
        let brief = ExerciseBriefBuilder.build(name: "Bench Press", muscleGroup: "Chest", sessions: [newer, older])
        XCTAssertEqual(brief?.style, .heavyLow)
        XCTAssertEqual(brief?.repLow, 5)
        XCTAssertEqual(brief?.repHigh, 6)
        XCTAssertEqual(brief?.lastTop, HistorySet(200, 5, rir: 1))
        XCTAssertEqual(brief?.avgRIR, 1)
        XCTAssertEqual(brief?.e1RMTrend, [234, 233], "oldest to newest")
        XCTAssertEqual(brief?.primaryMuscles, ["mid chest"])
    }

    func testMuscleLoadCountsHardSetsWithSecondaryHalf() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func workout(daysAgo: Double) -> (Workout, Exercise, [WorkoutSet]) {
            var w = Workout.create(userId: stack.userId, workoutType: "Push", energyLevel: 5, timeAvailableMinutes: 45)
            w.date = now.addingTimeInterval(-daysAgo * 86_400)
            let ex = Exercise.create(workoutId: w.id, name: "Bench Press", muscleGroup: "Chest", orderIndex: 0,
                                     targetSets: 3, targetReps: "8", targetRir: "2", restSeconds: 90, coachNote: nil)
            let sets = (1...3).map { WorkoutSet.create(exerciseId: ex.id, setNumber: $0, weightLbs: 135, reps: 8, rir: 2) }
            return (w, ex, sets)
        }
        let all = [workout(daysAgo: 2.5), workout(daysAgo: 10), workout(daysAgo: 40)]
        let load = MuscleLoadBuilder.build(
            workouts: all.map { $0.0 },
            exercises: Dictionary(uniqueKeysWithValues: all.map { ($0.0.id, [$0.1]) }),
            loggedSets: Dictionary(uniqueKeysWithValues: all.map { ($0.1.id, $0.2) }),
            now: now)
        XCTAssertEqual(load["mid chest"], MuscleLoad(thisWeekSets: 3, avgPrior3WeeksSets: 1, daysSince: 2))
        XCTAssertEqual(load["triceps"]?.thisWeekSets, 1.5)
        XCTAssertEqual(load["triceps"]?.avgPrior3WeeksSets, 0.5)
        XCTAssertNil(load["quads"])
    }

    func testContextCarriesBriefsAndMuscleLoad() {
        seed(daysAgo: 3, sets: [(135, 10, 3), (155, 8, 2), (165, 6, 1)])
        let ctx = builder.buildContext(userId: stack.userId, workoutType: "Push")
        XCTAssertEqual(ctx.briefs.map { $0.name }, ["Bench Press"])
        XCTAssertNotNil(ctx.muscleLoad["mid chest"])
        XCTAssertNil(ctx.fuel, "no fuel closure injected")
    }
}
