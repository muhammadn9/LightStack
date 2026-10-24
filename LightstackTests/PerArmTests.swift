import XCTest
import CoreData
@testable import Lightstack

final class PerArmTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "PerArmTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func exercise(_ name: String = "Single Arm Cable Row", perArm: Bool) -> Exercise {
        Exercise(id: UUID(), workoutId: UUID(), localId: nil, name: name, muscleGroup: "Back", orderIndex: 0,
                 targetSets: 3, targetReps: "10", targetRir: nil, restSeconds: nil, coachNote: nil,
                 syncStatus: .pending, isPerArm: perArm)
    }

    private func sets(_ exerciseId: UUID) -> [WorkoutSet] {
        [WorkoutSet.create(exerciseId: exerciseId, setNumber: 1, weightLbs: 25, reps: 10, rir: 2),
         WorkoutSet.create(exerciseId: exerciseId, setNumber: 2, weightLbs: 25, reps: 8, rir: 1)]
    }

    // MARK: Volume

    func testPerArmVolumeCountsBothSides() {
        let normal = exercise(perArm: false)
        let perArm = exercise(perArm: true)
        XCTAssertEqual(normal.volume(of: sets(normal.id)), 25 * 10 + 25 * 8)
        XCTAssertEqual(perArm.volume(of: sets(perArm.id)), (25 * 10 + 25 * 8) * 2)
    }

    func testSessionVolumeDoublesPerArmExercise() {
        let perArm = exercise(perArm: true)
        let normal = exercise("Row", perArm: false)
        let logged = [perArm.id: sets(perArm.id), normal.id: sets(normal.id)]
        let stats = WorkoutStatsService(localStorage: LocalStorageService(inMemory: true))
        XCTAssertEqual(stats.sessionVolume(exercises: [perArm, normal], loggedSets: logged), 450 * 2 + 450)
    }

    func testProgressLiftTrendFlagsPerArm() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        let cal = ProgressStats.weekCalendar(c)
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 12)) ?? Date()
        let sets = [LoggedSet(date: now, exerciseName: "Single Arm Row", weightLbs: 50, reps: 8, isPerArm: true)]
        XCTAssertEqual(ProgressStats.liftTrends(sets, now: now, calendar: cal).first?.isPerArm, true)
        XCTAssertEqual(LiftFormat.lb(50, perArm: true), "50 lb / arm")
        XCTAssertEqual(LiftFormat.lb(50), "50 lb")
    }

    // MARK: AI context

    func testPostWorkoutMessageLabelsPerArm() {
        let service = CoachPromptService(validationService: ValidationService())
        let perArm = exercise("DB Curl", perArm: true)
        let normal = exercise("Barbell Row", perArm: false)
        let message = service.buildPostWorkoutMessage(
            workoutType: "Pull", exercises: [perArm, normal],
            sets: [perArm.id: sets(perArm.id), normal.id: sets(normal.id)])
        XCTAssertTrue(message.contains("DB Curl (per arm):"), message)
        XCTAssertTrue(message.contains("Barbell Row:"), message)
        XCTAssertFalse(message.contains("Barbell Row (per arm)"))
    }

    // MARK: Supabase coding

    func testEncodingAlwaysIncludesKey() throws {
        let off = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(exercise(perArm: false))) as? [String: Any]
        XCTAssertEqual(off?["is_per_arm"] as? Bool, false)
        let on = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(exercise(perArm: true))) as? [String: Any]
        XCTAssertEqual(on?["is_per_arm"] as? Bool, true)
    }

    func testDecodingWithoutKeyDefaultsFalse() throws {
        let json = """
        {"id":"\(UUID())","workout_id":"\(UUID())","local_id":null,"name":"Bench","muscle_group":"Chest",
         "order_index":0,"target_sets":3,"target_reps":"8","target_rir":"2","rest_seconds":90,"coach_note":null,
         "superset_group_id":null}
        """
        XCTAssertFalse(try JSONDecoder().decode(Exercise.self, from: Data(json.utf8)).isPerArm)
        let withKey = json.replacingOccurrences(of: "\"superset_group_id\":null", with: "\"superset_group_id\":null,\"is_per_arm\":true")
        XCTAssertTrue(try JSONDecoder().decode(Exercise.self, from: Data(withKey.utf8)).isPerArm)
    }

    func testCoreDataRoundTrip() throws {
        let storage = LocalStorageService(inMemory: true)
        let ex = exercise(perArm: true)
        let entity = CDExercise(context: storage.context)
        ex.applyToCoreData(entity)
        XCTAssertTrue(Exercise(from: entity).isPerArm)
    }

    // MARK: Default by name

    func testAutoSuggestFromName() {
        for name in ["Single Arm Cable Row", "single-arm pec fly", "One Arm Row", "Unilateral Press", "Alternating DB Curl"] {
            XCTAssertTrue(PerArmPreference.suggestsPerArm(name), name)
            XCTAssertTrue(PerArmPreference.defaultValue(for: name, defaults: defaults), name)
        }
        XCTAssertFalse(PerArmPreference.defaultValue(for: "Barbell Bench Press", defaults: defaults))
    }

    func testRememberedValueWinsAndMatchesNameVariants() {
        PerArmPreference.remember(true, for: "Dumbbell Curl", defaults: defaults)
        XCTAssertTrue(PerArmPreference.defaultValue(for: "Dumbbell Curls", defaults: defaults))
        XCTAssertTrue(PerArmPreference.defaultValue(for: "DB curl", defaults: defaults))
        XCTAssertFalse(PerArmPreference.defaultValue(for: "Barbell Curl", defaults: defaults))
        // The user can turn off an auto-suggested lift and that sticks.
        PerArmPreference.remember(false, for: "Single Arm Cable Row", defaults: defaults)
        XCTAssertFalse(PerArmPreference.defaultValue(for: "Single Arm Cable Row", defaults: defaults))
    }

    // MARK: Lightweight migration (v3 -> v4)

    func testMigratesV3StoreToV4WithPerArmFalse() throws {
        let bundle = Bundle(for: LocalStorageService.self)
        let v3URL = try XCTUnwrap(bundle.url(forResource: "Lightstack 3", withExtension: "mom", subdirectory: "Lightstack.momd"))
        let v3Model = try XCTUnwrap(NSManagedObjectModel(contentsOf: v3URL))
        XCTAssertNil(v3Model.entitiesByName["CDExercise"]?.attributesByName["isPerArm"])

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("Lightstack.sqlite")
        let workoutId = UUID(), exerciseId = UUID()

        do {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: v3Model)
            let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
            let ctx = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            ctx.persistentStoreCoordinator = coordinator
            try ctx.performAndWait {
                let w = NSEntityDescription.insertNewObject(forEntityName: "CDWorkout", into: ctx)
                w.setValue(workoutId, forKey: "id"); w.setValue(UUID(), forKey: "userId")
                w.setValue(Date(), forKey: "date"); w.setValue("Pull", forKey: "workoutType")
                w.setValue(Date(), forKey: "createdAt")
                let e = NSEntityDescription.insertNewObject(forEntityName: "CDExercise", into: ctx)
                e.setValue(exerciseId, forKey: "id"); e.setValue("Row", forKey: "name")
                e.setValue("Back", forKey: "muscleGroup"); e.setValue(w, forKey: "workout")
                try ctx.save()
            }
            try coordinator.remove(store)
        }

        let container = NSPersistentContainer(name: "Lightstack")
        let desc = NSPersistentStoreDescription(url: storeURL)
        desc.shouldMigrateStoreAutomatically = true
        desc.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [desc]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError, "Migration failed: \(String(describing: loadError))")

        let exercises = try container.viewContext.fetch(CDExercise.fetchRequest() as NSFetchRequest<CDExercise>)
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises.first?.id, exerciseId)
        XCTAssertEqual(exercises.first?.name, "Row")
        XCTAssertEqual(exercises.first?.isPerArm, false)
        XCTAssertEqual(exercises.first?.workout?.id, workoutId)
    }
}
