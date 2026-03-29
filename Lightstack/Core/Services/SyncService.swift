import Foundation
import Network

/// Monitors connectivity via NWPathMonitor and coordinates sync
/// between local Core Data and remote Supabase.
/// Triggers OfflineQueueManager flush on reconnect.
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

    /// Manually trigger a queue flush — call on app foreground.
    func triggerFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            await self?.offlineQueueManager.flush()
        }
    }

    // MARK: - Private

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let nowOnline = path.status == .satisfied
            DispatchQueue.main.async {
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
