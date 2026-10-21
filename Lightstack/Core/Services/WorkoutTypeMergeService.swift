import Foundation

/// Merges several spellings of one workout type ("Push", "push", "Push Day") into one name:
/// workouts, planned sessions, AI summaries and the profile's split days, locally first and then
/// through the offline queue.
final class WorkoutTypeMergeService {

    private let localStorage: LocalStorageService
    private let offlineQueueManager: OfflineQueueManager
    private let profileRepository: ProfileRepository

    init(
        localStorage: LocalStorageService,
        offlineQueueManager: OfflineQueueManager,
        profileRepository: ProfileRepository
    ) {
        self.localStorage = localStorage
        self.offlineQueueManager = offlineQueueManager
        self.profileRepository = profileRepository
    }

    /// Renames every workout type in `names` to `keep`. Returns how many workouts and planned
    /// sessions changed.
    @discardableResult
    func merge(userId: UUID, names: [String], keep: String) -> Int {
        let target = keep.trimmingCharacters(in: .whitespacesAndNewlines)
        let sources = Self.unique(names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter { !$0.isEmpty && $0 != target }
        guard !target.isEmpty, !sources.isEmpty else { return 0 }

        // (a) workouts
        let workoutIds = localStorage.renameWorkoutTypes(userId: userId, from: sources, to: target)
        for id in workoutIds {
            guard let entity = localStorage.fetchWorkout(id: id) else { continue }
            let workout = Workout(from: entity)
            offlineQueueManager.submit(.updateWorkout, payload: workout, recordKey: workout.id.uuidString)
        }

        // (b) planned sessions
        let sessions = localStorage.renamePlannedSessionTypes(userId: userId, from: sources, to: target)
        for session in sessions {
            offlineQueueManager.submit(.updatePlannedSession, payload: session, recordKey: session.id.uuidString)
        }

        // (c) + (d) AI summaries
        mergeSummaries(userId: userId, sources: sources, target: target)

        // (e) split days
        mergeSplitDays(userId: userId, sources: sources, target: target)

        return workoutIds.count + sessions.count
    }

    // MARK: - Summaries

    private func mergeSummaries(userId: UUID, sources: [String], target: String) {
        let involvedKeys = Set((sources + [target]).map { $0.lowercased() })
        let involved = localStorage.fetchAllContextSummaries(userId: userId).filter {
            involvedKeys.contains(($0.workoutType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        let models = involved.map { AIContextSummary(from: $0) }

        // Remote rows to remove: every merged-away spelling, whether or not it exists locally.
        var doomed = Self.unique(sources + models.map(\.workoutType)).filter { $0 != target }
        doomed.removeAll { $0.isEmpty }

        if let winner = models.max(by: {
            ($0.sessionsCovered, $0.lastUpdated) < ($1.sessionsCovered, $1.lastUpdated)
        }) {
            let existingKeep = models.first { $0.workoutType == target }
            let merged = AIContextSummary(
                id: existingKeep?.id ?? winner.id,
                userId: userId,
                workoutType: target,
                summaryText: winner.summaryText,
                sessionsCovered: winner.sessionsCovered,
                lastUpdated: winner.lastUpdated
            )
            localStorage.deleteContextSummaries(involved)
            localStorage.saveContextSummary(merged)
            offlineQueueManager.submit(
                .upsertContextSummary, payload: merged, recordKey: "\(userId.uuidString)|\(target)"
            )
        }
        offlineQueueManager.submitDeleteContextSummaries(types: doomed)
    }

    // MARK: - Split days

    private func mergeSplitDays(userId: UUID, sources: [String], target: String) {
        guard var profile = profileRepository.fetchProfileSync(userId: userId) else { return }
        let replaced = Set((sources + [target]).map { $0.lowercased() })
        var seen = Set<String>()
        var updated: [String] = []
        for day in profile.splitDays {
            let trimmed = day.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = replaced.contains(trimmed.lowercased()) ? target : day
            if seen.insert(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).inserted {
                updated.append(name)
            }
        }
        guard updated != profile.splitDays else { return }
        profile.splitDays = updated
        profileRepository.saveProfile(profile)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
