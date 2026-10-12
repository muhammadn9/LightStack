import XCTest
import Supabase
@testable import Lightstack

final class ExerciseNameResolverTests: XCTestCase {

    private func assertSame(_ names: [String], file: StaticString = #filePath, line: UInt = #line) {
        let groups = ExerciseNameResolver.duplicateGroups(among: names)
        XCTAssertEqual(groups.count, 1, "Expected one group for \(names), got \(groups)", file: file, line: line)
        XCTAssertEqual(groups.first?.count, names.count, "Not all grouped: \(groups)", file: file, line: line)
    }

    private func assertDifferent(_ a: String, _ b: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(ExerciseNameResolver.isMatch(a, b),
                       "\(a) and \(b) should not match (\(ExerciseNameResolver.similarity(a, b)))",
                       file: file, line: line)
    }

    func testLegCurlVariantsGroup() {
        assertSame(["Leg curl machine", "Leg hamstring curl", "Leg hamstring curl machine",
                    "Hamstring curl machine", "Seated Hamstring curl"])
    }

    func testInclineSmithPressVariantsGroup() {
        assertSame(["Incline smith chest press", "Incline Smith Machine Press", "Incline Smith machine Chest Press"])
    }

    func testLatPulldownVariantsGroup() {
        assertSame(["Cable lat pull down machine", "Cable lat pulldown machine", "Lat Pulldown Machine",
                    "Cable lat pulldown", "Seated cable lat pulldown machine"])
    }

    func testHipAdductionVariantsGroup() {
        assertSame(["Hip adduction", "Hip Adductor Machine"])
    }

    func testLegExtensionVariantsGroup() {
        assertSame(["Leg Extension", "Leg extension machine", "Seated Leg extension machine"])
    }

    func testPluralAndCaseVariantsMatch() {
        XCTAssertTrue(ExerciseNameResolver.isMatch("leg extensions", "Leg Extension"))
    }

    func testDifferentExercisesDoNotMatch() {
        assertDifferent("Barbell curl", "Dumbbell curl")
        assertDifferent("Leg press", "Leg extension")
        assertDifferent("Incline dumbbell press", "Flat dumbbell press")
        assertDifferent("Hip adduction", "Hip abduction")
        assertDifferent("Bench press", "Overhead press")
    }

    func testSuggestionsRankAndExcludeExactName() {
        let known = ["Leg Extension", "Leg press", "Leg extension machine", "Bench Press"]
        let result = ExerciseNameResolver.suggestions(for: "leg extensions", among: known)
        XCTAssertEqual(Set(result), ["Leg Extension", "Leg extension machine"])
        // The exact (case-insensitive) name is never suggested back to itself.
        XCTAssertFalse(ExerciseNameResolver.suggestions(for: "Leg Extension", among: known).contains("Leg Extension"))
        XCTAssertTrue(ExerciseNameResolver.suggestions(for: "Squat", among: known).isEmpty)
        XCTAssertTrue(ExerciseNameResolver.suggestions(for: "  ", among: known).isEmpty)
    }

    func testSeparateGroupsStaySeparate() {
        let groups = ExerciseNameResolver.duplicateGroups(among: [
            "Leg Extension", "Barbell curl", "Leg extension machine", "Dumbbell curl", "Bench Press"
        ])
        XCTAssertEqual(groups, [["Leg Extension", "Leg extension machine"]])
    }
}

final class ExerciseRenameTests: XCTestCase {

    private var storage: LocalStorageService!
    private var prRepo: PRRepository!
    private let userId = UUID()

    override func setUp() {
        super.setUp()
        storage = LocalStorageService(inMemory: true)
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://example.invalid") ?? URL(fileURLWithPath: "/"),
            supabaseKey: "test"
        )
        let supabase = SupabaseService(client: client)
        prRepo = PRRepository(
            localStorage: storage,
            supabaseService: supabase,
            offlineQueueManager: OfflineQueueManager(supabaseService: supabase)
        )
    }

    private func log(_ name: String, sets: [(Double, Int)], user: UUID? = nil) -> Exercise {
        let workout = Workout.create(userId: user ?? userId, workoutType: "Legs", energyLevel: nil, timeAvailableMinutes: nil)
        storage.saveWorkout(workout)
        let exercise = Exercise.create(
            workoutId: workout.id, name: name, muscleGroup: "Legs", orderIndex: 0,
            targetSets: sets.count, targetReps: "10", targetRir: nil, restSeconds: 60, coachNote: nil
        )
        storage.saveExercises([exercise], workoutId: workout.id)
        for (index, entry) in sets.enumerated() {
            let set = WorkoutSet.create(exerciseId: exercise.id, setNumber: index + 1,
                                        weightLbs: entry.0, reps: entry.1, rir: nil)
            storage.saveSet(set, exerciseId: exercise.id)
        }
        return exercise
    }

    func testRenameChangesOnlyListedNamesForThisUser() {
        let a = log("Leg extension machine", sets: [(100, 10)])
        let b = log("Leg Extension", sets: [(90, 10)])
        let other = log("Bench Press", sets: [(135, 8)])
        let stranger = UUID()
        _ = log("Leg extension machine", sets: [(50, 10)], user: stranger)

        let changed = storage.renameExercises(userId: userId, from: ["Leg extension machine", "Leg Extension"],
                                              to: "Leg Extension")
        XCTAssertEqual(Set(changed), [a.id])
        let stats = storage.fetchExerciseNameStats(userId: userId)
        XCTAssertEqual(stats.map(\.name).sorted(), ["Bench Press", "Leg Extension"])
        XCTAssertEqual(stats.first { $0.name == "Leg Extension" }?.setCount, 2)
        XCTAssertEqual(stats.first { $0.name == "Leg Extension" }?.workoutCount, 2)
        _ = (b, other)
        // Another user's data is untouched.
        XCTAssertEqual(storage.fetchExerciseNameStats(userId: stranger).map(\.name), ["Leg extension machine"])
    }

    func testPRsRecalculatedForKeptNameAndStaleOnesRemoved() {
        _ = log("Leg extension machine", sets: [(150, 10)])
        _ = log("Leg Extension", sets: [(90, 10)])
        prRepo.recalculateAllPRs(userId: userId)
        XCTAssertNotNil(prRepo.fetchPR(userId: userId, exerciseName: "Leg extension machine"))

        storage.renameExercises(userId: userId, from: ["Leg extension machine", "Leg Extension"], to: "Leg Extension")
        prRepo.recalculatePR(userId: userId, exerciseName: "Leg extension machine")
        prRepo.recalculatePR(userId: userId, exerciseName: "Leg Extension")

        XCTAssertNil(prRepo.fetchPR(userId: userId, exerciseName: "Leg extension machine"))
        let kept = prRepo.fetchPR(userId: userId, exerciseName: "Leg Extension")
        XCTAssertEqual(kept?.weightLbs, 150)
        XCTAssertEqual(prRepo.fetchAllPRs(userId: userId).count, 1)
    }

    func testRenameToSameNameIsNoOp() {
        _ = log("Leg Extension", sets: [(90, 10)])
        XCTAssertTrue(storage.renameExercises(userId: userId, from: ["Leg Extension"], to: "Leg Extension").isEmpty)
    }
}
