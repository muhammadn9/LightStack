import Foundation
import MetricKit
import os

/// Receives MetricKit crash / hang / CPU / disk diagnostics and daily metrics, and keeps short
/// summaries on the device (`DiagnosticsStore`). Nothing leaves the phone.
final class MetricKitCollector: NSObject, MXMetricManagerSubscriber {

    static let shared = MetricKitCollector(store: .shared)

    private let store: DiagnosticsStore
    private let logger = Logger(subsystem: "org.lightstack.app", category: "MetricKit")
    private var started = false

    init(store: DiagnosticsStore) {
        self.store = store
        super.init()
    }

    /// Call once at launch (not in UI-test mode). Also picks up payloads delivered while the app was closed.
    func start() {
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
        ingest(diagnostics: MXMetricManager.shared.pastDiagnosticPayloads)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        let entries = payloads.compactMap {
            DiagnosticPayloadParser.entry(fromMetricJSON: $0.jsonRepresentation(), received: $0.timeStampEnd)
        }
        guard !entries.isEmpty else { return }
        store.append(entries)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        ingest(diagnostics: payloads)
    }

    private func ingest(diagnostics payloads: [MXDiagnosticPayload]) {
        let entries = payloads.flatMap {
            DiagnosticPayloadParser.entries(fromDiagnosticJSON: $0.jsonRepresentation(), received: $0.timeStampEnd)
        }
        guard !entries.isEmpty else { return }
        store.append(entries)
        logger.info("stored \(entries.count) diagnostic entries")
    }
}
