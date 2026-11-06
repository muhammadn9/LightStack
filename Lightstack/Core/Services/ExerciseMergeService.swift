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
        defer { ExerciseMergeAliases.remember(sources, mergedInto: keep) }
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

/// Remembers which names were merged away, so the coach's next proposal of
/// "Leg extension machine" lands on the kept "Leg Extension" instead of recreating it.
enum ExerciseMergeAliases {
    static let key = "lightstack.exerciseMergeAliases.v1"

    static func remember(_ mergedAway: [String], mergedInto keep: String, defaults: UserDefaults = .standard) {
        let target = keep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        var stored = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
        for name in mergedAway {
            let alias = ExerciseNameResolver.normalizedKey(name)
            guard !alias.isEmpty, alias != ExerciseNameResolver.normalizedKey(target) else { continue }
            stored[alias] = target
        }
        // Keeping a name that was itself merged away earlier un-merges it.
        stored.removeValue(forKey: ExerciseNameResolver.normalizedKey(target))
        defaults.set(stored, forKey: key)
    }

    /// The kept name for a merged-away one, following chains of merges.
    static func resolve(_ name: String, defaults: UserDefaults = .standard) -> String? {
        guard let stored = defaults.dictionary(forKey: key) as? [String: String] else { return nil }
        var current = name
        var found: String?
        for _ in 0..<5 {
            guard let next = stored[ExerciseNameResolver.normalizedKey(current)] else { break }
            found = next
            current = next
        }
        return found
    }
}
