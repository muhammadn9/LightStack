import Foundation

/// Merges several spellings of one exercise into a single name: local rename,
/// PR rebuild, then the cloud rename through the offline queue.
final class ExerciseMergeService {

    private let localStorage: LocalStorageService
    private let offlineQueueManager: OfflineQueueManager
    private let prRepository: PRRepository

    init(
        localStorage: LocalStorageService,
        offlineQueueManager: OfflineQueueManager,
        prRepository: PRRepository
    ) {
        self.localStorage = localStorage
        self.offlineQueueManager = offlineQueueManager
        self.prRepository = prRepository
    }

    /// Renames every exercise named in `names` to `keep`. Returns how many exercise
    /// records changed.
    @discardableResult
    func merge(userId: UUID, names: [String], keep: String) -> Int {
        let sources = names.filter { $0 != keep }
        let ids = localStorage.renameExercises(userId: userId, from: sources, to: keep)
        guard !ids.isEmpty else { return 0 }

        // Old names lose their PRs (no sets left under them); the kept name gets
        // a PR rebuilt from the combined history.
        for name in sources {
            prRepository.recalculatePR(userId: userId, exerciseName: name)
        }
        prRepository.recalculatePR(userId: userId, exerciseName: keep)

        offlineQueueManager.submit(.renameExercises, payload: RenameExercisesPayload(ids: ids, name: keep))
        return ids.count
    }
}
