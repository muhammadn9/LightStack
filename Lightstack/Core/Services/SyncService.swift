import Foundation
import Network

/// Monitors connectivity via NWPathMonitor and coordinates sync
/// between local Core Data and remote Supabase.
/// Triggers OfflineQueueManager flush on reconnect.
/// @MainActor ensures all state mutations (isOnline) happen
/// on the main actor, preventing data races from concurrent callers.
@MainActor
final class SyncService: ObservableObject {

    @Published private(set) var isOnline: Bool = false

    private let monitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "lightstack.network.monitor", qos: .utility)
    private let offlineQueueManager: OfflineQueueManager

    init(offlineQueueManager: OfflineQueueManager) {
        self.offlineQueueManager = offlineQueueManager
        self.monitor = NWPathMonitor()
        startMonitoring()
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - Public

    /// Manually trigger a queue flush — called on sign-in and app foreground.
    func triggerFlush() {
        #if DEBUG
        // UI tests must never reach the network or drain their seeded queue (unless a fake remote is in use).
        if UITestMode.isActive && UITestMode.fakeRemoteMode == nil { return }
        #endif
        // The queue manager is single-flight: extra requests during a flush just
        // make it run another pass, so there is nothing to cancel or de-duplicate here.
        let manager = offlineQueueManager
        Task { await manager.flush() }
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
                    #if DEBUG
                    // The first path update after launch would act as a launch flush.
                    if UITestMode.isActive && UITestMode.skipLaunchFlush { return }
                    #endif
                    self.triggerFlush()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }
}
