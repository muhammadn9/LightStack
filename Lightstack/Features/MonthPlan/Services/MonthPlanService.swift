import Foundation

/// Delegate for MonthPlanService async callbacks.
protocol MonthPlanServiceDelegate: AnyObject {
    func monthPlanServiceDidGeneratePlan(_ service: MonthPlanService, plan: MonthPlan, sessions: [PlannedSession])
    func monthPlanServiceDidFail(_ service: MonthPlanService, error: Error)
}

/// Owns month plan business logic: creating plans, generating sessions
/// via AI, updating completion status, and revising remaining sessions.
final class MonthPlanService {

    weak var delegate: MonthPlanServiceDelegate?

    private let geminiService: GeminiService
    private let coachPromptService: CoachPromptService
    private let coachContextBuilder: CoachContextBuilder
    private let monthPlanRepository: MonthPlanRepository
    private let validationService: ValidationService

    init(
        geminiService: GeminiService,
        coachPromptService: CoachPromptService,
        coachContextBuilder: CoachContextBuilder,
        monthPlanRepository: MonthPlanRepository,
        validationService: ValidationService
    ) {
        self.geminiService = geminiService
        self.coachPromptService = coachPromptService
        self.coachContextBuilder = coachContextBuilder
        self.monthPlanRepository = monthPlanRepository
        self.validationService = validationService
    }

    /// Generate a month plan via AI and save it.
    func generatePlan(
        userId: UUID,
        targetGoal: String,
        startDate: Date,
        daysPerWeek: Int
    ) {
        let endDate = Calendar.current.date(byAdding: .month, value: 1, to: startDate) ?? startDate

        let context = coachContextBuilder.buildContext(userId: userId)
        let systemPrompt = coachPromptService.buildSystemPrompt(profile: context.profile)
        let userMessage = coachPromptService.buildMonthPlanRequestMessage(
            targetGoal: targetGoal,
            daysPerWeek: daysPerWeek,
            startDate: startDate,
            endDate: endDate
        )

        geminiService.generateChatAsync(
            systemPrompt: systemPrompt,
            messages: [ChatMessage(role: .user, content: userMessage)]
        ) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let responseText):
                if let (plan, sessions) = self.parseMonthPlanResponse(
                    responseText,
                    userId: userId,
                    startDate: startDate,
                    endDate: endDate,
                    targetGoal: targetGoal
                ) {
                    self.monthPlanRepository.savePlan(plan, sessions: sessions)
                    self.delegate?.monthPlanServiceDidGeneratePlan(self, plan: plan, sessions: sessions)
                } else {
                    let error = NSError(
                        domain: "MonthPlanService", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Could not parse month plan from AI response"]
                    )
                    self.delegate?.monthPlanServiceDidFail(self, error: error)
                }

            case .failure(let error):
                self.delegate?.monthPlanServiceDidFail(self, error: error)
            }
        }
    }

    // MARK: - Parse Response

    /// Defensive JSON parsing of the AI response format.
    func parseMonthPlanResponse(
        _ text: String,
        userId: UUID,
        startDate: Date,
        endDate: Date,
        targetGoal: String
    ) -> (MonthPlan, [PlannedSession])? {
        // Try to extract JSON from the response (AI may include markdown code fences)
        let jsonText = extractJSON(from: text)

        guard let data = jsonText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let overview = json["overview"] as? String ?? ""

        guard let sessionsArray = json["sessions"] as? [[String: Any]] else {
            return nil
        }

        let plan = MonthPlan.create(
            userId: userId,
            title: String(targetGoal.prefix(50)),
            targetGoal: targetGoal,
            startDate: startDate,
            endDate: endDate,
            aiOverview: overview
        )

        var sessions: [PlannedSession] = []
        let dateFormatter = DateFormatter.dateOnly

        for sessionDict in sessionsArray {
            guard let dateStr = sessionDict["date"] as? String,
                  let date = dateFormatter.date(from: dateStr),
                  let workoutType = sessionDict["workout_type"] as? String
            else {
                continue
            }

            let focusNote = sessionDict["focus_note"] as? String
            let isRestDay = sessionDict["is_rest_day"] as? Bool ?? false

            let session = PlannedSession.create(
                monthPlanId: plan.id,
                userId: userId,
                plannedDate: date,
                workoutType: workoutType,
                focusNote: focusNote,
                isRestDay: isRestDay
            )
            sessions.append(session)
        }

        guard !sessions.isEmpty else { return nil }

        return (plan, sessions)
    }

    // MARK: - Private

    private func extractJSON(from text: String) -> String {
        // Strip markdown code fences if present
        var cleaned = text
        if cleaned.contains("```json") {
            cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        }
        if cleaned.contains("```") {
            cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        }

        // Find the first { and last }
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}")
        else {
            return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return String(cleaned[start...end])
    }
}
