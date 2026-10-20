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

    func testContextSkipsEmptyWorkoutsAndKeepsLastThreeCompleted() {
        seed(daysAgo: 0, sets: [])   // pending / abandoned: no logged sets
        for d in 1...4 { seed(daysAgo: d, sets: [(135, 10, 3)]) }
        seed(type: "Pull", daysAgo: 1, sets: [(95, 8, 2)])

        let ctx = builder.buildContext(userId: stack.userId, workoutType: "Push")
        XCTAssertEqual(ctx.recentSessions.count, 3)
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
        XCTAssertTrue(message.contains("Athlete note: left shoulder tweaky"))
        XCTAssertTrue(message.contains("note: plan only"))
        XCTAssertFalse(message.contains("Estimate target_weight"))
        XCTAssertFalse(message.contains("sets x"), "planned targets are no longer rendered")
    }

    func testPlanJSONWithSetTargetsParsesPerSet() throws {
        let json = """
        {"exercises":[{"name":"Bench Press","muscle_group":"Chest","sets":9,"rest_seconds":120,
          "coach_note":"Hit 8@2 -> +5 lb",
          "set_targets":[{"weight":"95","reps":"10","rir":"4"},{"weight":"135","reps":8,"rir":"2-3"},{"weight":"145","reps":"6","rir":"1"}]},
          {"name":"Curl","muscle_group":"Biceps","sets":3,"target_weight":"25 lbs","reps":"10-12","rir":"2"}],
         "coaching_notes":"x"}
        """
        let plan = try XCTUnwrap(WorkoutSessionService.plan(fromPlanJSON: json, workoutId: UUID(), sanitizeLabel: { $0 }))
        let bench = try XCTUnwrap(plan.exercises.first { $0.name == "Bench Press" })
        let targets = try XCTUnwrap(plan.setTargets[bench.id])
        XCTAssertEqual(bench.targetSets, 3, "sets follows set_targets.count")
        XCTAssertEqual(targets.map(\.prefillWeight), ["95", "135", "145"])
        XCTAssertEqual(targets.map(\.prefillReps), ["10", "8", "6"])
        XCTAssertEqual(targets.map(\.prefillRir), ["4", "2", "1"])
        XCTAssertEqual(bench.coachNoteParts.weight, "145 lbs")

        let curl = try XCTUnwrap(plan.exercises.first { $0.name == "Curl" })
        XCTAssertNil(plan.setTargets[curl.id])
    }

    func testPlanJSONWithoutSetTargetsParsesAsBefore() throws {
        let json = #"{"exercises":[{"name":"Squat","muscle_group":"Legs","sets":4,"target_weight":"185 lbs","reps":"5","rir":"2"}]}"#
        let plan = try XCTUnwrap(WorkoutSessionService.plan(fromPlanJSON: json, workoutId: UUID(), sanitizeLabel: { $0 }))
        XCTAssertTrue(plan.setTargets.isEmpty)
        XCTAssertEqual(plan.exercises.first?.targetSets, 4)
        XCTAssertEqual(plan.exercises.first?.targetReps, "5")
        XCTAssertEqual(plan.exercises.first?.coachNoteParts.weight, "185 lbs")
    }

    func testMalformedSetTargetsFallBackToSingleFields() throws {
        let json = #"{"exercises":[{"name":"Row","muscle_group":"Back","sets":3,"set_targets":"oops"}]}"#
        let plan = try XCTUnwrap(WorkoutSessionService.plan(fromPlanJSON: json, workoutId: UUID(), sanitizeLabel: { $0 }))
        XCTAssertEqual(plan.exercises.first?.targetSets, 3)
        XCTAssertTrue(plan.setTargets.isEmpty)
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
}
