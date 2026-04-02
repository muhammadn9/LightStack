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

    func fetchActivePlan(userId: UUID) -> MonthPlan? {
        guard let cdEntity = localStorage.fetchActiveMonthPlan(userId: userId) else {
            return nil
        }
        let plan = MonthPlan(from: cdEntity)
        Task {
            try? await syncPlanFromRemote(userId: userId)
        }
        return plan
    }

    func fetchActivePlans(userId: UUID) -> [MonthPlan] {
        localStorage.fetchActiveMonthPlans(userId: userId).map { MonthPlan(from: $0) }
    }

    func deletePlan(_ plan: MonthPlan) {
        localStorage.deleteMonthPlan(id: plan.id)
    }

    func fetchSessions(monthPlanId: UUID) -> [PlannedSession] {
        localStorage.fetchPlannedSessions(monthPlanId: monthPlanId)
            .map { PlannedSession(from: $0) }
    }

    // MARK: - Save

    func savePlan(_ plan: MonthPlan, sessions: [PlannedSession]) {
        localStorage.saveMonthPlan(plan)
        localStorage.savePlannedSessions(sessions, monthPlanId: plan.id)
        Task {
            // Separate do/catch blocks: only enqueue the operation that actually failed.
            // If insertMonthPlan succeeds but insertPlannedSessions fails, enqueueing
            // the plan would cause a PK conflict on retry — so they must be tracked separately.
            do {
                try await supabaseService.insertMonthPlan(plan)
            } catch {
                await offlineQueueManager.enqueue(.insertMonthPlan, payload: plan)
            }
            do {
                try await supabaseService.insertPlannedSessions(sessions)
            } catch {
                await offlineQueueManager.enqueue(.insertPlannedSessions, payload: sessions)
            }
        }
    }

    // MARK: - Update

    func markSessionCompleted(_ session: PlannedSession, workoutId: UUID) {
        var updated = session
        updated.completed = true
        updated.workoutId = workoutId
        localStorage.updatePlannedSession(updated)
        Task {
            do {
                try await supabaseService.updatePlannedSession(updated)
            } catch {
                await offlineQueueManager.enqueue(.updatePlannedSession, payload: updated)
            }
        }
    }

    // MARK: - Private

    private func syncPlanFromRemote(userId: UUID) async throws {
        guard let remotePlan = try await supabaseService.fetchActiveMonthPlan(userId: userId) else {
            return
        }
        localStorage.saveMonthPlan(remotePlan)
        let remoteSessions = try await supabaseService.fetchPlannedSessions(monthPlanId: remotePlan.id)
        if !remoteSessions.isEmpty {
            localStorage.savePlannedSessions(remoteSessions, monthPlanId: remotePlan.id)
        }
    }
}
