import Foundation

/// Rest days: local save first, then the cloud write goes through the offline queue.
final class RestDayRepository {

    private let localStorage: LocalStorageService
    private let offlineQueueManager: OfflineQueueManager

    init(localStorage: LocalStorageService, offlineQueueManager: OfflineQueueManager) {
        self.localStorage = localStorage
        self.offlineQueueManager = offlineQueueManager
    }

    func isRestDay(userId: UUID, date: Date) -> Bool {
        localStorage.isRestDay(userId: userId, date: date)
    }

    /// Marks the day as a rest day (no-op if it already is).
    func addRestDay(userId: UUID, date: Date) {
        guard let restDay = localStorage.addRestDay(userId: userId, date: date) else { return }
        offlineQueueManager.submit(.upsertRestDay, payload: restDay, recordKey: restDay.id.uuidString)
    }

    /// Unmarks the day. The remote row is deleted and a tombstone recorded.
    func removeRestDay(userId: UUID, date: Date) {
        let removed = localStorage.removeRestDay(userId: userId, date: date)
        for restDay in removed {
            offlineQueueManager.submit(.deleteRestDay, payload: DeleteRestDayPayload(id: restDay.id, date: restDay.date))
        }
        offlineQueueManager.submitTombstones(.restDay, ids: removed.map(\.id))
    }
}
