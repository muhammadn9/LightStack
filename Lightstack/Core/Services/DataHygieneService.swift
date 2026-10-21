import Foundation
import os

/// One-time (per version, per user) cleanup of data that earlier builds left messy:
/// exact-duplicate workouts, never-started plans, and duplicate / orphan / junk-named PRs.
/// Everything goes through the normal repositories, so it syncs through the offline queue.
final class DataHygieneService {

    /// Bump to run the cleanup again on every install.
    static let version = 1

    private static let logger = Logger(subsystem: "org.lightstack.app", category: "DataHygiene")

    private let localStorage: LocalStorageService
    private let duplicates: DuplicateWorkoutCleanup
    private let stale: StaleWorkoutCleanup
    private let prRepository: PRRepository
    private let defaults: UserDefaults
    /// The plan waiting to start / workout being logged in memory (WorkoutSessionService).
    private let currentPendingId: () -> UUID?
    /// Ids that must never be deleted (the live session, including one saved for relaunch).
    private let protectedWorkoutIds: () -> Set<UUID>

    init(
        localStorage: LocalStorageService,
        workoutRepository: WorkoutRepository,
        prRepository: PRRepository,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() },
        currentPendingId: @escaping () -> UUID? = { nil },
        protectedWorkoutIds: @escaping () -> Set<UUID> = { [] }
    ) {
        self.currentPendingId = currentPendingId
        self.localStorage = localStorage
        self.prRepository = prRepository
        self.defaults = defaults
        self.protectedWorkoutIds = protectedWorkoutIds
        self.duplicates = DuplicateWorkoutCleanup(
            localStorage: localStorage, workoutRepository: workoutRepository, prRepository: prRepository
        )
        self.stale = StaleWorkoutCleanup(localStorage: localStorage, workoutRepository: workoutRepository, now: now)
    }

    struct Summary: Equatable {
        var duplicateWorkoutsRemoved = 0
        var unstartedPlansRemoved = 0
        var prs = PRRepository.CleanupSummary()
    }

    private func flagKey(_ userId: UUID) -> String { "lightstack.dataHygiene.v\(Self.version).\(userId.uuidString)" }

    func hasRun(userId: UUID) -> Bool { defaults.bool(forKey: flagKey(userId)) }

    /// Runs the cleanup once per user per version. Returns nil when it already ran.
    @discardableResult
    func runIfNeeded(userId: UUID) -> Summary? {
        guard !hasRun(userId: userId) else { return nil }
        let summary = run(userId: userId)
        defaults.set(true, forKey: flagKey(userId))
        return summary
    }

    /// Runs the cleanup now (ignores the flag). Safe to repeat.
    func run(userId: UUID) -> Summary {
        var summary = Summary()
        let protected = protectedWorkoutIds()
        // Order matters: remove duplicate sessions and stale plans first, then PR cleanup
        // works from the sets that remain.
        summary.duplicateWorkoutsRemoved = duplicates.removeExactDuplicates(userId: userId, protecting: protected)
        summary.unstartedPlansRemoved = stale.removeUnstartedPlans(
            userId: userId, keeping: currentPendingId(), protecting: protected
        )
        summary.prs = prRepository.cleanUpRecords(userId: userId)
        Self.logger.info("""
            hygiene: dupWorkouts=\(summary.duplicateWorkoutsRemoved) plans=\(summary.unstartedPlansRemoved) \
            orphanPRs=\(summary.prs.orphansRemoved) swept=\(summary.prs.namesSwept)
            """)
        if summary.duplicateWorkoutsRemoved + summary.unstartedPlansRemoved > 0 {
            NotificationCenter.default.post(name: .syncRestoreDidChangeLocalData, object: nil)
        }
        return summary
    }
}
