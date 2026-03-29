import Foundation

/// Coordinates local + remote month plan data access.
/// Local-first reads with background remote sync.
final class MonthPlanRepository {

    private let localStorage: LocalStorageService
    private let supabaseService: SupabaseService

    init(localStorage: LocalStorageService, supabaseService: SupabaseService) {
        self.localStorage = localStorage
        self.supabaseService = supabaseService
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

    func fetchSessions(monthPlanId: UUID) -> [PlannedSession] {
        localStorage.fetchPlannedSessions(monthPlanId: monthPlanId)
            .map { PlannedSession(from: $0) }
    }

    // MARK: - Save

    func savePlan(_ plan: MonthPlan, sessions: [PlannedSession]) {
        localStorage.saveMonthPlan(plan)
        localStorage.savePlannedSessions(sessions, monthPlanId: plan.id)
        Task {
            do {
                try await supabaseService.insertMonthPlan(plan)
                try await supabaseService.insertPlannedSessions(sessions)
            } catch {
                print("MonthPlanRepository: Supabase insert failed: \(error.localizedDescription)")
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
                print("MonthPlanRepository: Supabase update failed: \(error.localizedDescription)")
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
