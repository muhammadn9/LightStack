import Foundation

/// Turns the JSON MetricKit gives for a diagnostic / metric payload (`jsonRepresentation()`) into
/// `DiagnosticEntry` values. Lenient: anything missing is skipped, never thrown.
enum DiagnosticPayloadParser {

    private static let sections: [(key: String, kind: DiagnosticEntry.Kind)] = [
        ("crashDiagnostics", .crash),
        ("hangDiagnostics", .hang),
        ("cpuExceptionDiagnostics", .cpu),
        ("diskWriteExceptionDiagnostics", .disk)
    ]

    /// `received` stamps entries (MetricKit does not date individual diagnostics).
    static func entries(fromDiagnosticJSON data: Data, received: Date) -> [DiagnosticEntry] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        var out = [DiagnosticEntry]()
        for (key, kind) in sections {
            guard let items = root[key] as? [[String: Any]] else { continue }
            for item in items {
                let meta = item["diagnosticMetaData"] as? [String: Any] ?? [:]
                let frames = topFrames(in: item["callStackTree"] as? [String: Any])
                let summary = summarize(kind: kind, meta: meta)
                let version = meta["appVersion"] as? String
                let id = stableId(kind: kind, received: received, summary: summary, frames: frames)
                out.append(DiagnosticEntry(id: id, date: received, kind: kind, appVersion: version,
                                           summary: summary, frames: frames))
            }
        }
        return out
    }

    /// A short "daily metrics" entry (foreground time, peak memory) from an `MXMetricPayload`.
    static func entry(fromMetricJSON data: Data, received: Date) -> DiagnosticEntry? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var parts = [String]()
        if let time = root["applicationTimeMetrics"] as? [String: Any],
           let fg = time["cumulativeForegroundTime"] as? String { parts.append("foreground \(fg)") }
        if let mem = root["memoryMetrics"] as? [String: Any],
           let peak = mem["peakMemoryUsage"] as? String { parts.append("peak memory \(peak)") }
        if let exits = root["applicationExitMetrics"] as? [String: Any],
           let bg = exits["backgroundExitData"] as? [String: Any] {
            let abnormal = (bg["cumulativeAbnormalExitCount"] as? Int) ?? 0
            let watchdog = (bg["cumulativeAppWatchdogExitCount"] as? Int) ?? 0
            if abnormal + watchdog > 0 { parts.append("abnormal exits \(abnormal), watchdog \(watchdog)") }
        }
        let summary = parts.isEmpty ? "Daily metrics" : "Daily metrics: " + parts.joined(separator: ", ")
        let version = (root["metaData"] as? [String: Any])?["appBuildVersion"] as? String
        return DiagnosticEntry(id: stableId(kind: .metrics, received: received, summary: summary, frames: []),
                               date: received, kind: .metrics, appVersion: version, summary: summary)
    }

    // MARK: - Helpers

    static func summarize(kind: DiagnosticEntry.Kind, meta: [String: Any]) -> String {
        func text(_ key: String) -> String? {
            if let s = meta[key] as? String, !s.isEmpty { return s }
            if let n = meta[key] as? NSNumber { return n.stringValue }
            return nil
        }
        var parts = [String]()
        switch kind {
        case .crash:
            if let t = text("exceptionType") { parts.append("exception \(t)") }
            if let c = text("exceptionCode") { parts.append("code \(c)") }
            if let s = text("signal") { parts.append("signal \(s)") }
            if let r = text("terminationReason") { parts.append(r) }
            if let m = text("objectiveCexceptionReason") ?? text("virtualMemoryRegionInfo") { parts.append(m) }
        case .hang:
            if let d = text("hangDuration") { parts.append("hung for \(d)") }
        case .cpu:
            if let d = text("totalCPUTime") { parts.append("CPU time \(d)") }
            if let d = text("totalSampledTime") { parts.append("over \(d)") }
        case .disk:
            if let d = text("writesCaused") { parts.append("wrote \(d)") }
        case .metrics:
            break
        }
        return parts.isEmpty ? kind.label : parts.joined(separator: ", ")
    }

    /// Follows the first sub-frame of the attributed (or first) thread, up to 8 frames.
    static func topFrames(in tree: [String: Any]?) -> [String] {
        guard let stacks = tree?["callStacks"] as? [[String: Any]], !stacks.isEmpty else { return [] }
        let stack = stacks.first(where: { ($0["threadAttributed"] as? Bool) == true }) ?? stacks[0]
        var frame = (stack["callStackRootFrames"] as? [[String: Any]])?.first
        var out = [String]()
        while let f = frame, out.count < 8 {
            let name = (f["binaryName"] as? String) ?? "?"
            let offset = (f["offsetIntoBinaryTextSegment"] as? NSNumber)?.intValue
            let symbol = f["symbol"] as? String
            var line = name
            if let symbol { line += " \(symbol)" }
            if let offset { line += " +\(offset)" }
            out.append(line)
            frame = (f["subFrames"] as? [[String: Any]])?.first
        }
        return out
    }

    /// Same input -> same id across launches, so re-reading past payloads never duplicates entries.
    static func stableId(kind: DiagnosticEntry.Kind, received: Date, summary: String, frames: [String]) -> String {
        var hash: UInt64 = 5381
        for byte in (summary + frames.joined(separator: "|")).utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return "\(kind.rawValue)-\(Int(received.timeIntervalSince1970))-\(String(hash, radix: 16))"
    }
}
