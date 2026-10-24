import Foundation

/// One stored crash / hang / CPU / disk diagnostic or metrics summary. Plain JSON on purpose:
/// MetricKit payloads cannot be built in tests, so parsing and storage work on this model only.
struct DiagnosticEntry: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case crash, hang, cpu, disk, metrics

        var label: String {
            switch self {
            case .crash: return "Crash"
            case .hang: return "Hang"
            case .cpu: return "CPU"
            case .disk: return "Disk writes"
            case .metrics: return "Metrics"
            }
        }
    }

    var id: String
    var date: Date
    var kind: Kind
    var appVersion: String?
    /// Exception / signal / duration in one line.
    var summary: String
    /// Top frames of the attributed thread (capped).
    var frames: [String]

    static let maxSummary = 300
    static let maxFrames = 12
    static let maxFrameLength = 200

    init(id: String, date: Date, kind: Kind, appVersion: String? = nil, summary: String, frames: [String] = []) {
        self.id = id
        self.date = date
        self.kind = kind
        self.appVersion = appVersion
        self.summary = String(summary.prefix(Self.maxSummary))
        self.frames = frames.prefix(Self.maxFrames).map { String($0.prefix(Self.maxFrameLength)) }
    }
}

/// Keeps the newest diagnostics as JSON in Application Support, capped by count and size.
/// Local only: nothing is uploaded; the owner shares the file from Settings -> Diagnostics.
final class DiagnosticsStore: @unchecked Sendable {

    static let shared = DiagnosticsStore(directory: DiagnosticsStore.defaultDirectory())

    static let defaultMaxEntries = 20
    static let defaultMaxBytes = 1_000_000

    private let fileURL: URL
    private let maxEntries: Int
    private let maxBytes: Int
    private let lock = NSLock()

    init(directory: URL, maxEntries: Int = DiagnosticsStore.defaultMaxEntries,
         maxBytes: Int = DiagnosticsStore.defaultMaxBytes) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("diagnostics.json")
        self.maxEntries = maxEntries
        self.maxBytes = maxBytes
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    /// Newest first.
    func load() -> [DiagnosticEntry] {
        lock.lock(); defer { lock.unlock() }
        return readLocked()
    }

    /// Merges new entries (same id replaces), then trims to the count and size caps, dropping the oldest.
    @discardableResult
    func append(_ new: [DiagnosticEntry]) -> [DiagnosticEntry] {
        lock.lock(); defer { lock.unlock() }
        var byId = [String: DiagnosticEntry]()
        for e in readLocked() { byId[e.id] = e }
        for e in new { byId[e.id] = e }
        var all = byId.values.sorted { $0.date > $1.date }
        if all.count > maxEntries { all = Array(all.prefix(maxEntries)) }
        while all.count > 1, (try? Self.encoder.encode(all).count) ?? 0 > maxBytes { all.removeLast() }
        if let data = try? Self.encoder.encode(all) {
            try? data.write(to: fileURL, options: .atomic)
        }
        return all
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Writes a copy named for sharing and returns its URL.
    func exportFile() -> URL? {
        lock.lock(); defer { lock.unlock() }
        let entries = readLocked()
        guard let data = try? Self.encoder.encode(entries) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lightstack-diagnostics.json")
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    private func readLocked() -> [DiagnosticEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? Self.decoder.decode([DiagnosticEntry].self, from: data) else { return [] }
        return entries.sorted { $0.date > $1.date }
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
