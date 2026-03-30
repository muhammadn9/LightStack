import Foundation
import Network

/// Monitors connectivity via NWPathMonitor and coordinates sync
/// between local Core Data and remote Supabase.
/// Triggers OfflineQueueManager flush on reconnect.
/// @MainActor ensures all state mutations (isOnline, flushTask) happen
/// on the main actor, preventing data races from concurrent callers.
@MainActor
final class SyncService: ObservableObject {

    @Published private(set) var isOnline: Bool = false

    private let monitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "lightstack.network.monitor", qos: .utility)
    private let offlineQueueManager: OfflineQueueManager
    private var flushTask: Task<Void, Never>?

    init(offlineQueueManager: OfflineQueueManager) {
        self.offlineQueueManager = offlineQueueManager
        self.monitor = NWPathMonitor()
        startMonitoring()
    }

    deinit {
        monitor.cancel()
        flushTask?.cancel()
    }

    // MARK: - Public

    /// Manually trigger a queue flush — called on sign-in and app foreground.
    func triggerFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            await self?.offlineQueueManager.flush()
        }
    }

    // MARK: - Private

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let nowOnline = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = nowOnline
                if nowOnline && wasOffline {
                    self.triggerFlush()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }
}
