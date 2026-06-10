import Foundation
import os

/// Delegate for MonthPlanService async callbacks.
protocol MonthPlanServiceDelegate: AnyObject {
    func monthPlanServiceDidGeneratePlan(_ service: MonthPlanService, plan: MonthPlan, sessions: [PlannedSession])
    func monthPlanServiceDidFail(_ service: MonthPlanService, error: Error)
}

/// Owns month plan business logic: creating plans, generating sessions
/// via AI, updating completion status, and revising remaining sessions.
final class MonthPlanService {

    private let logger = Logger(subsystem: "org.lightstack.app", category: "MonthPlanService")

    weak var delegate: MonthPlanServiceDelegate?

    private let aiServiceManager: AIServiceManager
    private let coachPromptService: CoachPromptService
    private let coachContextBuilder: CoachContextBuilder
    private let monthPlanRepository: MonthPlanRepository
    private let validationService: ValidationService

    init(
        aiServiceManager: AIServiceManager,
        coachPromptService: CoachPromptService,
        coachContextBuilder: CoachContextBuilder,
        monthPlanRepository: MonthPlanRepository,
        validationService: ValidationService
    ) {
        self.aiServiceManager = aiServiceManager
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

        aiServiceManager.generateChat(
            systemPrompt: systemPrompt,
            messages: [ChatMessage(role: .user, content: userMessage)]
        ) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let responseText):
                // Log the raw response for debugging
                self.logger.debug("Raw AI response: \(responseText)")

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
                    // Provide more detailed error message
                    let extractedJSON = self.extractJSON(from: responseText)
                    let preview = String(extractedJSON.prefix(200))
                    self.logger.error("Failed to parse. Extracted JSON preview: \(preview)")

                    let error = NSError(
                        domain: "MonthPlanService", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Could not parse month plan. AI may have returned invalid format. Please try again."]
                    )
                    self.delegate?.monthPlanServiceDidFail(self, error: error)
                }

            case .failure(let error):
                self.logger.error("AI request failed: \(String(describing: error))")
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

        guard let data = jsonText.data(using: .utf8) else {
            logger.error("Failed to convert extracted JSON to Data")
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.error("Failed to parse JSON. Invalid JSON format.")
            if let parseError = try? JSONSerialization.jsonObject(with: data) {
                logger.debug("Parsed as: \(String(describing: type(of: parseError)))")
            }
            return nil
        }

        logger.debug("Successfully parsed JSON with keys: \(String(describing: json.keys))")

        let overview = json["overview"] as? String ?? ""

        guard let sessionsArray = json["sessions"] as? [[String: Any]] else {
            logger.error("Missing or invalid 'sessions' array. Found keys: \(String(describing: json.keys))")
            return nil
        }

        logger.debug("Found \(sessionsArray.count) sessions in response")

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

        for (index, sessionDict) in sessionsArray.enumerated() {
            guard let dateStr = sessionDict["date"] as? String,
                  let date = dateFormatter.date(from: dateStr),
                  let workoutType = sessionDict["workout_type"] as? String
            else {
                logger.debug("Skipping session \(index): missing required fields. Keys: \(String(describing: sessionDict.keys))")
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

        logger.debug("Successfully parsed \(sessions.count) sessions")

        guard !sessions.isEmpty else {
            logger.error("No valid sessions were parsed")
            return nil
        }

        return (plan, sessions)
    }

    // MARK: - Private

    private func extractJSON(from text: String) -> String {
        // Strip markdown code fences if present (various formats)
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code fences
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }

        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find the first { and last } to extract just the JSON object
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}")
        else {
            logger.error("Could not find JSON delimiters { } in response")
            return cleaned
        }

        let extracted = String(cleaned[start...end])
        logger.debug("Extracted JSON length: \(extracted.count) characters")
        return extracted
    }
}
