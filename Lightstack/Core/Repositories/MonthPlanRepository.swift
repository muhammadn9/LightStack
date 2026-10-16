import Foundation

/// Coordinates local + remote month plan data access.
/// Local-first reads with background remote sync.
final class MonthPlanRepository {

    private let localStorage: LocalStorageService
    private let supabaseService: SupabaseService
    private let offlineQueueManager: OfflineQueueManager

    init(
        localStorage: LocalStorageService,
        supabaseService: SupabaseService,
        offlineQueueManager: OfflineQueueManager
    ) {
        self.localStorage = localStorage
        self.supabaseService = supabaseService
        self.offlineQueueManager = offlineQueueManager
    }

    // MARK: - Fetch

    /// The active plan from the local store. Cloud plans arrive through `SyncRestoreService`
    /// (which honours tombstones and unuploaded local changes); this read no longer returns
    /// early or pulls on its own, so a fresh device gets its plan from the restore.
    func fetchActivePlan(userId: UUID) -> MonthPlan? {
        localStorage.fetchActiveMonthPlan(userId: userId).map { MonthPlan(from: $0) }
    }

    func fetchActivePlans(userId: UUID) -> [MonthPlan] {
        localStorage.fetchActiveMonthPlans(userId: userId).map { MonthPlan(from: $0) }
    }

    /// Deletes the plan locally and in the cloud (planned sessions cascade there);
    /// tombstones record the plan and each of its sessions.
    func deletePlan(_ plan: MonthPlan) {
        let sessionIds = localStorage.fetchPlannedSessions(monthPlanId: plan.id).compactMap(\.id)
        localStorage.deleteMonthPlan(id: plan.id)
        offlineQueueManager.submit(.deleteMonthPlan, payload: DeleteMonthPlanPayload(planId: plan.id))
        offlineQueueManager.submitTombstones(.monthPlan, ids: [plan.id])
        offlineQueueManager.submitTombstones(.plannedSession, ids: sessionIds)
    }

    func fetchSessions(monthPlanId: UUID) -> [PlannedSession] {
        localStorage.fetchPlannedSessions(monthPlanId: monthPlanId)
            .map { PlannedSession(from: $0) }
    }

    // MARK: - Save

    func savePlan(_ plan: MonthPlan, sessions: [PlannedSession]) {
        localStorage.saveMonthPlan(plan)
        localStorage.savePlannedSessions(sessions, monthPlanId: plan.id)
        // Plan before its sessions (FK); the queue also sorts parents first.
        offlineQueueManager.submit(.insertMonthPlan, payload: plan, recordKey: plan.id.uuidString)
        if !sessions.isEmpty {
            offlineQueueManager.submit(.insertPlannedSessions, payload: sessions)
        }
    }

    // MARK: - Update

    func markSessionCompleted(_ session: PlannedSession, workoutId: UUID) {
        var updated = session
        updated.completed = true
        updated.workoutId = workoutId
        localStorage.updatePlannedSession(updated)
        offlineQueueManager.submit(.updatePlannedSession, payload: updated, recordKey: updated.id.uuidString)
    }
}
