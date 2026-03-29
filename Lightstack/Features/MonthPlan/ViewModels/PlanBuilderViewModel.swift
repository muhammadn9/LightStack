import Foundation

/// Manages the plan builder conversation state.
/// Collects user inputs (goal, timeline, schedule) and triggers
/// AI plan generation through MonthPlanService.
final class PlanBuilderViewModel: ObservableObject, MonthPlanServiceDelegate {

    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false
    @Published var targetGoal = ""
    @Published var daysPerWeek = 4
    @Published var planGenerated = false
    @Published var errorMessage: String?

    var generatedPlan: MonthPlan?
    var generatedSessions: [PlannedSession] = []

    private let monthPlanService: MonthPlanService
    private let validationService: ValidationService
    private var userId: UUID?

    init(monthPlanService: MonthPlanService, validationService: ValidationService) {
        self.monthPlanService = monthPlanService
        self.validationService = validationService
        monthPlanService.delegate = self
    }

    func setUserId(_ id: UUID) {
        self.userId = id
    }

    /// Start the plan generation with current inputs.
    func generatePlan() {
        guard let userId = userId else { return }
        let sanitizedGoal = validationService.sanitize(targetGoal)
        guard !sanitizedGoal.isEmpty else {
            errorMessage = "Please enter a training goal."
            return
        }

        isGenerating = true
        errorMessage = nil

        let userMessage = ChatMessage(role: .user, content: "My goal: \(sanitizedGoal). I want to train \(daysPerWeek) days per week.")
        messages.append(userMessage)

        let coachMessage = ChatMessage(role: .coach, content: "Building your personalized month plan. This may take a moment...")
        messages.append(coachMessage)

        monthPlanService.generatePlan(
            userId: userId,
            targetGoal: sanitizedGoal,
            startDate: Date(),
            daysPerWeek: daysPerWeek
        )
    }

    // MARK: - MonthPlanServiceDelegate

    func monthPlanServiceDidGeneratePlan(_ service: MonthPlanService, plan: MonthPlan, sessions: [PlannedSession]) {
        isGenerating = false
        generatedPlan = plan
        generatedSessions = sessions
        planGenerated = true

        let trainingDays = sessions.filter { !$0.isRestDay }.count
        let restDays = sessions.filter { $0.isRestDay }.count
        let overview = plan.aiOverview ?? "Plan generated successfully."

        let successMessage = ChatMessage(
            role: .coach,
            content: "Your plan is ready! \(trainingDays) training days and \(restDays) rest days over the next month.\n\n\(overview)"
        )
        messages.append(successMessage)
    }

    func monthPlanServiceDidFail(_ service: MonthPlanService, error: Error) {
        isGenerating = false
        errorMessage = error.localizedDescription

        let errorMsg = ChatMessage(
            role: .coach,
            content: "Sorry, I had trouble generating your plan. Please try again. (\(error.localizedDescription))"
        )
        messages.append(errorMsg)
    }
}
