import XCTest
import CoreData
@testable import Lightstack

/// Guards the v1 -> v2 (supersetGroupId) lightweight migration. A failed migration
/// makes LocalStorageService fatalError on launch, so this must really run.
final class CoreDataMigrationTests: XCTestCase {

    private func modelURLs() throws -> (momd: URL, v1: URL, v2: URL) {
        let bundle = Bundle(for: LocalStorageService.self)
        let momd = try XCTUnwrap(bundle.url(forResource: "Lightstack", withExtension: "momd"),
                                 "Lightstack.momd missing from app bundle \(bundle.bundlePath)")
        let listing = (try? FileManager.default.contentsOfDirectory(atPath: momd.path)) ?? []
        guard let v1 = bundle.url(forResource: "Lightstack", withExtension: "mom", subdirectory: "Lightstack.momd"),
              let v2 = bundle.url(forResource: "Lightstack 2", withExtension: "mom", subdirectory: "Lightstack.momd")
        else {
            XCTFail("Could not find both moms in Lightstack.momd. Contents: \(listing)")
            throw NSError(domain: "Migration", code: 1)
        }
        return (momd, v1, v2)
    }

    func testMigratesV1StoreToCurrentModel() throws {
        let urls = try modelURLs()
        let v1Model = try XCTUnwrap(NSManagedObjectModel(contentsOf: urls.v1))
        XCTAssertNil(v1Model.entitiesByName["CDExercise"]?.attributesByName["supersetGroupId"], "v1 must not have the attribute")
        let v2Model = try XCTUnwrap(NSManagedObjectModel(contentsOf: urls.v2))
        XCTAssertNotNil(v2Model.entitiesByName["CDExercise"]?.attributesByName["supersetGroupId"])

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("Lightstack.sqlite")

        let workoutId = UUID(), exerciseId = UUID(), setId = UUID()

        // 1. Build a v1 store on disk.
        do {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: v1Model)
            let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
            let ctx = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            ctx.persistentStoreCoordinator = coordinator
            try ctx.performAndWait {
                let w = NSEntityDescription.insertNewObject(forEntityName: "CDWorkout", into: ctx)
                w.setValue(workoutId, forKey: "id"); w.setValue(UUID(), forKey: "userId")
                w.setValue(Date(), forKey: "date"); w.setValue("Push", forKey: "workoutType")
                w.setValue(Date(), forKey: "createdAt")
                let e = NSEntityDescription.insertNewObject(forEntityName: "CDExercise", into: ctx)
                e.setValue(exerciseId, forKey: "id"); e.setValue("Bench", forKey: "name")
                e.setValue("Chest", forKey: "muscleGroup"); e.setValue(w, forKey: "workout")
                let s = NSEntityDescription.insertNewObject(forEntityName: "CDWorkoutSet", into: ctx)
                s.setValue(setId, forKey: "id"); s.setValue(1, forKey: "setNumber")
                s.setValue(135.0, forKey: "weightLbs"); s.setValue(8, forKey: "reps"); s.setValue(2, forKey: "rir")
                s.setValue(Date(), forKey: "recordedAt")
                s.setValue(e, forKey: "exercise")
                try ctx.save()
            }
            try coordinator.remove(store)
        }

        // 2. Open it with the current model, auto-migrating like the app does.
        let container = NSPersistentContainer(name: "Lightstack")
        let desc = NSPersistentStoreDescription(url: storeURL)
        desc.shouldMigrateStoreAutomatically = true
        desc.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [desc]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError, "Migration failed: \(String(describing: loadError))")

        // 3. Data intact, new attribute nil.
        let ctx = container.viewContext
        let exercises = try ctx.fetch(CDExercise.fetchRequest() as NSFetchRequest<CDExercise>)
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises.first?.id, exerciseId)
        XCTAssertEqual(exercises.first?.name, "Bench")
        XCTAssertNil(exercises.first?.supersetGroupId)
        XCTAssertEqual(exercises.first?.workout?.id, workoutId)
        XCTAssertEqual(exercises.first?.sets?.count, 1)
        let sets = try ctx.fetch(CDWorkoutSet.fetchRequest() as NSFetchRequest<CDWorkoutSet>)
        XCTAssertEqual(sets.first?.id, setId)
        XCTAssertEqual(sets.first?.reps, 8)
    }
}
