import Foundation
import CoreData
import os

/// What happened the last time the local store could not be opened. Persisted so the one-time
/// message and the Diagnostics screen can report it after the fact.
struct LocalStoreRecoveryEvent: Codable, Equatable, Identifiable {
    enum Outcome: String, Codable {
        /// Old files were set aside and a fresh empty store was created.
        case freshStore
        /// Even a fresh store could not be created; the app runs on an in-memory store.
        case inMemoryFallback
    }

    var id: String
    var date: Date
    var errorDescription: String
    /// Folder holding the set-aside files (nil when nothing could be moved).
    var quarantinePath: String?
    var movedFiles: [String]
    var outcome: Outcome
    /// True once the user has seen and dismissed the one-time message.
    var acknowledged: Bool

    var diagnosticSummary: String {
        let where_ = quarantinePath.map { " Old files kept in \($0)." } ?? ""
        return "Local store failed to load (\(errorDescription)); outcome: \(outcome.rawValue).\(where_)"
    }
}

/// Persists recovery events as JSON in Application Support (or a test directory).
final class LocalStoreRecoveryLog: @unchecked Sendable {
    static let shared = LocalStoreRecoveryLog(directory: LocalStoreRecoveryLog.defaultDirectory())

    private let fileURL: URL
    private let lock = NSLock()

    init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("store-recovery-events.json")
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("StoreQuarantine", isDirectory: true)
    }

    /// Newest first.
    func events() -> [LocalStoreRecoveryEvent] {
        lock.lock(); defer { lock.unlock() }
        return readLocked()
    }

    func record(_ event: LocalStoreRecoveryEvent) {
        lock.lock(); defer { lock.unlock() }
        writeLocked([event] + readLocked())
    }

    /// The newest event the user has not been told about yet.
    func unacknowledgedEvent() -> LocalStoreRecoveryEvent? {
        events().first { !$0.acknowledged }
    }

    func acknowledgeAll() {
        lock.lock(); defer { lock.unlock() }
        var all = readLocked()
        for i in all.indices { all[i].acknowledged = true }
        writeLocked(all)
    }

    private func readLocked() -> [LocalStoreRecoveryEvent] {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? Self.decoder.decode([LocalStoreRecoveryEvent].self, from: data) else { return [] }
        return list.sorted { $0.date > $1.date }
    }

    private func writeLocked(_ events: [LocalStoreRecoveryEvent]) {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? e.encode(Array(events.prefix(20))) { try? data.write(to: fileURL, options: .atomic) }
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

/// Loads the persistent store without ever crashing: retry once, then set the old files aside in a
/// timestamped quarantine folder (never deleted), create a fresh store, and finally fall back to an
/// in-memory store.
enum LocalStoreLoader {

    enum Result {
        case loaded
        case recovered(LocalStoreRecoveryEvent)
        /// A fresh store could not be created; running in memory. Blocking error screen territory.
        case unavailable(LocalStoreRecoveryEvent)
    }

    private static let logger = Logger(subsystem: "org.lightstack.app", category: "LocalStoreLoader")

    static func load(container: NSPersistentContainer,
                     quarantineRoot: URL,
                     log: LocalStoreRecoveryLog,
                     diagnostics: DiagnosticsStore,
                     now: Date = Date()) -> Result {
        guard let description = container.persistentStoreDescriptions.first else { return .loaded }

        var firstError = attemptLoad(container)
        if firstError == nil { return .loaded }
        logger.error("store failed to load, retrying: \(String(describing: firstError), privacy: .public)")

        // (a) One retry.
        if attemptLoad(container) == nil { return .loaded }
        let error = firstError ?? NSError(domain: "LocalStoreLoader", code: -1)
        firstError = nil

        // (b) Move the files aside, never delete.
        var quarantinePath: String?
        var moved: [String] = []
        if let storeURL = description.url, description.type == NSSQLiteStoreType {
            (quarantinePath, moved) = quarantine(storeURL: storeURL, root: quarantineRoot, now: now)
        }

        var event = LocalStoreRecoveryEvent(
            id: UUID().uuidString, date: now,
            errorDescription: String(error.localizedDescription.prefix(200)),
            quarantinePath: quarantinePath, movedFiles: moved,
            outcome: .freshStore, acknowledged: false)

        if attemptLoad(container) == nil {
            finish(event, log: log, diagnostics: diagnostics)
            return .recovered(event)
        }

        // Even a fresh store failed: run in memory.
        description.type = NSInMemoryStoreType
        description.url = nil
        event.outcome = .inMemoryFallback
        _ = attemptLoad(container)
        finish(event, log: log, diagnostics: diagnostics)
        return .unavailable(event)
    }

    private static func finish(_ event: LocalStoreRecoveryEvent, log: LocalStoreRecoveryLog, diagnostics: DiagnosticsStore) {
        logger.error("\(event.diagnosticSummary, privacy: .public)")
        log.record(event)
        diagnostics.append([DiagnosticEntry(id: "store-\(event.id)", date: event.date, kind: .storage,
                                            summary: event.diagnosticSummary)])
    }

    /// `loadPersistentStores` calls back synchronously (stores are not added asynchronously here).
    private static func attemptLoad(_ container: NSPersistentContainer) -> Error? {
        var failure: Error?
        container.loadPersistentStores { _, error in failure = error }
        return failure
    }

    private static func quarantine(storeURL: URL, root: URL, now: Date) -> (String?, [String]) {
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let folder = root.appendingPathComponent("Quarantine-\(formatter.string(from: now))-\(UUID().uuidString.prefix(6))",
                                                 isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var moved: [String] = []
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard fm.fileExists(atPath: source.path) else { continue }
            let target = folder.appendingPathComponent(source.lastPathComponent)
            do {
                try fm.moveItem(at: source, to: target)
                moved.append(source.lastPathComponent)
            } catch {
                logger.error("could not move \(source.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return (moved.isEmpty ? nil : folder.path, moved)
    }
}
