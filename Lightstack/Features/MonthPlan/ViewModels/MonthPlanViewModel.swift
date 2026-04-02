import Foundation

/// Manages month plan state: loading plan data, calendar layout,
/// session completion tracking, and plan progress.
final class MonthPlanViewModel: ObservableObject {

    @Published var activePlan: MonthPlan?
    @Published var sessions: [PlannedSession] = []
    @Published var selectedDate: Date?
    @Published var isLoading = false
    @Published var allPlans: [MonthPlan] = []
    @Published var canCreateNewPlan: Bool = true

    private let monthPlanRepository: MonthPlanRepository
    private var userId: UUID?

    init(monthPlanRepository: MonthPlanRepository) {
        self.monthPlanRepository = monthPlanRepository
    }

    func setUserId(_ id: UUID) {
        self.userId = id
    }

    func loadPlan() {
        loadPlans()
    }

    func loadPlans() {
        guard let userId = userId else { return }
        isLoading = true
        let plans = monthPlanRepository.fetchActivePlans(userId: userId)
        allPlans = plans
        activePlan = plans.first
        canCreateNewPlan = plans.count < 5
        if let plan = activePlan {
            sessions = monthPlanRepository.fetchSessions(monthPlanId: plan.id)
        }
        isLoading = false
    }

    func selectPlan(_ plan: MonthPlan) {
        activePlan = plan
        sessions = monthPlanRepository.fetchSessions(monthPlanId: plan.id)
    }

    func addPlan(_ plan: MonthPlan, sessions newSessions: [PlannedSession]) {
        allPlans.insert(plan, at: 0)
        activePlan = plan
        sessions = newSessions
        canCreateNewPlan = allPlans.count < 5
    }

    func deletePlan(_ plan: MonthPlan) {
        monthPlanRepository.deletePlan(plan)
        allPlans.removeAll { $0.id == plan.id }
        if activePlan?.id == plan.id {
            activePlan = allPlans.first
            if let next = activePlan {
                sessions = monthPlanRepository.fetchSessions(monthPlanId: next.id)
            } else {
                sessions = []
            }
        }
        canCreateNewPlan = allPlans.count < 5
    }

    /// Reload plan data (e.g., after plan generation).
    func reload(plan: MonthPlan, sessions newSessions: [PlannedSession]) {
        addPlan(plan, sessions: newSessions)
    }

    /// Group sessions by week for calendar display.
    func sessionsForWeek(_ weekOffset: Int) -> [PlannedSession] {
        guard let plan = activePlan else { return [] }
        let calendar = Calendar.current
        guard let weekStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: plan.startDate) else {
            return []
        }
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return []
        }
        return sessions.filter { $0.plannedDate >= weekStart && $0.plannedDate < weekEnd }
    }

    /// Mark a planned session as completed.
    func markSessionCompleted(session: PlannedSession, workoutId: UUID) {
        monthPlanRepository.markSessionCompleted(session, workoutId: workoutId)
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index].completed = true
            sessions[index].workoutId = workoutId
        }
    }

    /// Today's planned session.
    var todaySession: PlannedSession? {
        let today = Calendar.current.startOfDay(for: Date())
        return sessions.first { Calendar.current.isDate($0.plannedDate, inSameDayAs: today) }
    }

    /// Progress: completed / total training days.
    var completedCount: Int {
        sessions.filter { $0.completed && !$0.isRestDay }.count
    }

    var totalTrainingDays: Int {
        sessions.filter { !$0.isRestDay }.count
    }

    var progressFraction: Double {
        guard totalTrainingDays > 0 else { return 0 }
        return Double(completedCount) / Double(totalTrainingDays)
    }

    /// All dates in the plan's month for calendar layout.
    var calendarDates: [Date] {
        guard let plan = activePlan else { return [] }
        let calendar = Calendar.current
        var dates: [Date] = []
        var current = calendar.startOfDay(for: plan.startDate)
        let end = calendar.startOfDay(for: plan.endDate)

        while current <= end {
            dates.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current.addingTimeInterval(86400)
        }
        return dates
    }

    /// Get the planned session for a specific date.
    func session(for date: Date) -> PlannedSession? {
        sessions.first { Calendar.current.isDate($0.plannedDate, inSameDayAs: date) }
    }
}
