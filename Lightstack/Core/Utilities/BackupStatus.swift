import Foundation

/// What the Settings "backup status" row shows. Derived from the outbox, never stored.
enum BackupStatus: Equatable {
    case signedOut
    case backingUp
    case waiting(count: Int)
    case allBackedUp(lastBackup: Date?)

    static func derive(pending: Int, failed: Int, isFlushing: Bool, signedOut: Bool,
                       lastSuccessfulFlush: Date?) -> BackupStatus {
        if signedOut { return .signedOut }
        let waiting = pending + failed
        if waiting > 0 { return isFlushing ? .backingUp : .waiting(count: waiting) }
        return .allBackedUp(lastBackup: lastSuccessfulFlush)
    }

    var title: String {
        switch self {
        case .signedOut: return "Signed out \u{2014} not backing up"
        case .backingUp: return "Backing up\u{2026}"
        case .waiting(let n): return "\(n) \(n == 1 ? "change" : "changes") waiting to back up"
        case .allBackedUp: return "All changes backed up"
        }
    }

    func subtitle(now: Date = Date()) -> String? {
        switch self {
        case .allBackedUp(let last?):
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .full
            return "Last backed up \(f.localizedString(for: last, relativeTo: now))"
        case .signedOut: return "Tap to sign in again"
        case .waiting: return "Tap to back up now"
        default: return nil
        }
    }

    var systemImage: String {
        switch self {
        case .signedOut: return "exclamationmark.icloud"
        case .backingUp: return "arrow.triangle.2.circlepath.icloud"
        case .waiting: return "icloud.and.arrow.up"
        case .allBackedUp: return "checkmark.icloud"
        }
    }
}

/// Live backup status for the UI. Refreshes whenever the outbox reports a change.
@MainActor
final class BackupStatusModel: ObservableObject {
    @Published private(set) var status: BackupStatus = .allBackedUp(lastBackup: nil)
    @Published private(set) var sessionExpired = false

    /// Called (on the main actor) when an upload pass hit an auth error.
    var onAuthFailure: (@MainActor () -> Void)?

    private let queue: OfflineQueueManager
    private let expiry: SessionExpiryTracker
    private var refreshing = false
    private var refreshAgain = false

    init(queue: OfflineQueueManager, expiry: SessionExpiryTracker) {
        self.queue = queue
        self.expiry = expiry
        Task { [weak self] in
            await queue.setObservers(onChange: { [weak self] in
                Task { @MainActor in self?.refresh() }
            }, onAuthFailure: { [weak self] in
                Task { @MainActor in self?.onAuthFailure?() }
            })
            await self?.refreshNow()
        }
    }

    func refresh() {
        if refreshing { refreshAgain = true; return }
        Task { await refreshNow() }
    }

    func refreshNow() async {
        refreshing = true
        repeat {
            refreshAgain = false
            let snap = await queue.snapshot()
            let expired = expiry.isExpired
            sessionExpired = expired
            status = BackupStatus.derive(pending: snap.pending, failed: snap.failed, isFlushing: snap.isFlushing,
                                         signedOut: expired, lastSuccessfulFlush: snap.lastSuccessfulFlush)
        } while refreshAgain
        refreshing = false
    }
}
