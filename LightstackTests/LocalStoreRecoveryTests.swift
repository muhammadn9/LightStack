import XCTest
import CoreData
@testable import Lightstack

final class LocalStoreRecoveryTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("store-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private struct Harness {
        let storage: LocalStorageService
        let log: LocalStoreRecoveryLog
        let diagnostics: DiagnosticsStore
        let quarantine: URL
    }

    private func load(storeURL: URL) -> Harness {
        let quarantine = dir.appendingPathComponent("quarantine", isDirectory: true)
        let log = LocalStoreRecoveryLog(directory: quarantine)
        let diagnostics = DiagnosticsStore(directory: dir.appendingPathComponent("diag", isDirectory: true))
        let storage = LocalStorageService(storeURL: storeURL, quarantineRoot: quarantine,
                                          recoveryLog: log, diagnostics: diagnostics)
        return Harness(storage: storage, log: log, diagnostics: diagnostics, quarantine: quarantine)
    }

    private func assertFreshStoreUsable(_ storage: LocalStorageService, file: StaticString = #filePath, line: UInt = #line) throws {
        let id = UUID()
        let workout = CDWorkout(context: storage.context)
        workout.id = id
        workout.userId = UUID()
        workout.date = Date()
        workout.workoutType = "Push"
        workout.createdAt = Date()
        try storage.context.save()
        XCTAssertNotNil(storage.fetchWorkout(id: id), file: file, line: line)
    }

    private func quarantinedFolder(_ h: Harness) throws -> URL {
        let items = try FileManager.default.contentsOfDirectory(at: h.quarantine, includingPropertiesForKeys: nil)
        return try XCTUnwrap(items.first { $0.lastPathComponent.hasPrefix("Quarantine-") })
    }

    func testCorruptFileIsQuarantinedAndFreshStoreWorks() throws {
        let url = dir.appendingPathComponent("Lightstack.sqlite")
        let garbage = Data((0..<4096).map { UInt8($0 % 251) })
        try garbage.write(to: url)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: url.path + "-wal"))

        let h = load(storeURL: url)

        guard case .recovered(let event) = h.storage.loadResult else { return XCTFail("expected recovery") }
        XCTAssertEqual(event.outcome, .freshStore)
        let folder = try quarantinedFolder(h)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("Lightstack.sqlite")), garbage)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("Lightstack.sqlite-wal")), Data("wal".utf8))
        XCTAssertEqual(Set(event.movedFiles), ["Lightstack.sqlite", "Lightstack.sqlite-wal"])
        try assertFreshStoreUsable(h.storage)
        XCTAssertEqual(h.log.events().count, 1)
        XCTAssertEqual(h.log.unacknowledgedEvent()?.id, event.id)
        XCTAssertEqual(h.diagnostics.load().first?.kind, .storage)
        h.log.acknowledgeAll()
        XCTAssertNil(h.log.unacknowledgedEvent())
    }

    func testIncompatibleStoreIsQuarantined() throws {
        let url = dir.appendingPathComponent("Lightstack.sqlite")
        // A valid Core Data store whose CDWorkout.id is an Integer: lightweight migration cannot map it to a UUID.
        let entity = NSEntityDescription()
        entity.name = "CDWorkout"
        let attr = NSAttributeDescription()
        attr.name = "id"
        attr.attributeType = .integer64AttributeType
        attr.isOptional = true
        entity.properties = [attr]
        let oldModel = NSManagedObjectModel()
        oldModel.entities = [entity]
        do {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: oldModel)
            let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: nil)
            try coordinator.remove(store)
        }
        let original = try Data(contentsOf: url)

        let h = load(storeURL: url)

        guard case .recovered = h.storage.loadResult else { return XCTFail("expected recovery") }
        let folder = try quarantinedFolder(h)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("Lightstack.sqlite")), original)
        try assertFreshStoreUsable(h.storage)
    }

    func testHealthyStoreIsUntouched() throws {
        let url = dir.appendingPathComponent("Lightstack.sqlite")
        do {
            let first = load(storeURL: url)
            try assertFreshStoreUsable(first.storage)
            guard case .loaded = first.storage.loadResult else { return XCTFail("first load should be clean") }
        }
        let second = load(storeURL: url)
        guard case .loaded = second.storage.loadResult else { return XCTFail("healthy store must not be quarantined") }
        XCTAssertTrue(second.log.events().isEmpty)
    }

    func testUnwritableLocationFallsBackToMemory() throws {
        // A store path inside a directory that does not exist and cannot be created (a file is in the way).
        let blocker = dir.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)
        let url = blocker.appendingPathComponent("sub/Lightstack.sqlite")

        let h = load(storeURL: url)

        guard case .unavailable(let event) = h.storage.loadResult else { return XCTFail("expected in-memory fallback") }
        XCTAssertEqual(event.outcome, .inMemoryFallback)
        try assertFreshStoreUsable(h.storage)
        XCTAssertEqual(h.log.events().first?.outcome, .inMemoryFallback)
    }
}
