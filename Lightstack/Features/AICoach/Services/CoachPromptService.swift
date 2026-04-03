import Foundation

/// Owns the system prompt template and parameterization.
/// Injects live profile data into the canonical coach prompt
/// (defined in docs/COACH_PROMPT.md).
final class CoachPromptService {

    private let validationService: ValidationService

    init(validationService: ValidationService) {
        self.validationService = validationService
    }

    /// Build the full system prompt with profile data injected.
    func buildSystemPrompt(profile: UserProfile?) -> String {
        let name = sanitize(profile?.displayName ?? "Athlete")
        let age = profile?.age.map { String($0) } ?? "Unknown"
        let weight = profile?.weightLbs.map { String(format: "%.0f", $0) } ?? "Unknown"
        let height = profile?.heightInches.map { String(format: "%.0f", $0) } ?? "Unknown"
        let trainingAge = profile?.trainingAgeMonths.map { String($0) } ?? "Unknown"
        let goals = sanitize((profile?.primaryGoals ?? []).joined(separator: ", "))
        let avoid = sanitize((profile?.avoidExercises ?? []).joined(separator: ", "))
        let equip = formatEquipment(profile?.equipment ?? [:])
        let notes = sanitize(profile?.notesToCoach ?? "None")

        return """
        You are the Lightstack Coach — a personal strength and hypertrophy coach \
        with expertise in bodybuilding, powerbuilding, and physique-focused training.

        COACHING IDENTITY
        You treat every interaction as an ongoing coaching relationship, not a \
        one-time plan request. You remember what the athlete has done, reference \
        their specific lifts and numbers, and adjust every session based on their \
        history, recovery, and stated goals for today.

        Your tone is direct, realistic, and motivating. You tell the athlete what \
        is actually achievable — not what they want to hear. If a weight jump is \
        too aggressive, you say so. If they are having a rough week, you acknowledge \
        it and scale back intelligently.

        ATHLETE PROFILE
        - Name: \(name)
        - Age: \(age) | Weight: \(weight) lbs | Height: \(height) in
        - Training age: \(trainingAge) months
        - Primary goals: \(goals)
        - Exercises to avoid: \(avoid.isEmpty ? "None" : avoid)
        - Available equipment: \(equip)
        - Athlete notes: \(notes)

        TRAINING PRINCIPLES
        1. Use RIR (Reps In Reserve) as the intensity metric for all sets. \
        RIR 0 = absolute failure. RIR 1-2 = target working intensity. \
        RIR 3+ = too far from failure for hypertrophy stimulus.

        2. Progressive overload drives all programming decisions.

        3. Time scales the plan:
           - 30 min: 3-4 exercises, supersets allowed
           - 45 min: 4-5 exercises, standard rest
           - 60 min: 5-6 exercises, full rest periods

        4. Energy scales the intensity:
           - Low (1-4): higher RIR targets, reduced volume
           - Normal (5-7): standard programming
           - High (8-10): push harder, lower RIR targets

        WORKOUT TYPE HANDLING
        If the requested workout type is a cardio or non-strength session \
        (e.g., run, cycle, swim, HIIT, long run), do not refuse — instead \
        provide a complementary strength or conditioning workout that fits \
        the available time and energy level. Always respond with a workout table.

        WORKOUT PLAN FORMAT
        Always present the session plan as a markdown table:
        | Exercise | Sets | Target Weight | Reps | RIR | Rest |
        The athlete should be able to see the entire workout at a glance.

        PROGRESSION NOTE
        After reviewing completed sets, write a short progression note (3-5 sentences) \
        that summarizes what happened, what improved, and exactly what to target next \
        session for each main lift. This note is saved to their workout record.
        """
    }

    /// Build the user message requesting a workout plan.
    /// Optionally includes rolling summary and recent session data.
    func buildWorkoutRequestMessage(
        workoutType: String,
        time: Int,
        energy: Int,
        notes: String?,
        rollingSummary: String? = nil,
        recentSessions: [Workout] = [],
        recentSessionExercises: [UUID: [Exercise]] = [:]
    ) -> String {
        let sanitizedType = sanitize(workoutType)
        let sanitizedNotes = notes.map { sanitize($0) } ?? ""
        let clampedTime = validationService.sanitizeInteger(time, min: 15, max: 120)
        let clampedEnergy = validationService.sanitizeInteger(energy, min: 1, max: 10)

        var message = """
        Today's session:
        - Workout type: \(sanitizedType)
        - Time available: \(clampedTime) minutes
        - Energy level: \(clampedEnergy)/10
        """

        if !sanitizedNotes.isEmpty {
            message += "\n- Notes: \(sanitizedNotes)"
        }

        if let summary = rollingSummary, !summary.isEmpty {
            message += "\n\nROLLING CONTEXT (recent history summary):\n\(summary)"
        }

        if !recentSessions.isEmpty {
            message += "\n\nRECENT SESSIONS:"
            for workout in recentSessions {
                let dateStr = DateFormatter.shortDate.string(from: workout.date)
                message += "\n\n[\(dateStr)] \(workout.workoutType)"
                if let exercises = recentSessionExercises[workout.id] {
                    for ex in exercises {
                        let weight = ex.coachNote ?? "bodyweight"
                        message += "\n  - \(ex.name): \(ex.targetSets ?? 0) sets x \(ex.targetReps ?? "?") reps (\(weight))"
                    }
                }
            }
        }

        message += """

        \nGenerate a complete workout plan in table format:
        | Exercise | Sets | Target Weight | Reps | RIR | Rest |

        Include a muscle group label for each exercise. \
        Base the weights on reasonable estimates for my profile. \
        Keep the plan within my time constraint.
        """

        return message
    }

    /// Build user message for post-session progression note request.
    func buildPostSessionMessage(
        exercises: [Exercise],
        sets: [UUID: [WorkoutSet]]
    ) -> String {
        var lines = ["Here are the completed sets from today's session:\n"]

        for exercise in exercises {
            lines.append("**\(exercise.name)** (\(exercise.muscleGroup))")
            let exerciseSets = (sets[exercise.id] ?? []).sorted { $0.setNumber < $1.setNumber }
            for s in exerciseSets {
                lines.append("  Set \(s.setNumber): \(String(format: "%.1f", s.weightLbs)) lbs x \(s.reps) reps @ RIR \(s.rir)")
            }
            lines.append("")
        }

        lines.append("Write a progression note (3-5 sentences) summarizing this session and setting specific targets for next time.")

        return lines.joined(separator: "\n")
    }

    /// Build user message for month plan generation.
    func buildMonthPlanRequestMessage(
        targetGoal: String,
        daysPerWeek: Int,
        startDate: Date,
        endDate: Date
    ) -> String {
        let sanitizedGoal = sanitize(targetGoal)
        let clampedDays = validationService.sanitizeInteger(daysPerWeek, min: 1, max: 7)
        let startStr = DateFormatter.dateOnly.string(from: startDate)
        let endStr = DateFormatter.dateOnly.string(from: endDate)

        return """
        Generate a month-long training plan.

        GOAL: \(sanitizedGoal)
        TRAINING DAYS PER WEEK: \(clampedDays)
        DATE RANGE: \(startStr) to \(endStr)

        Return the plan as JSON with this exact format:
        {
          "overview": "A 2-3 sentence overview of the plan approach and periodization strategy.",
          "sessions": [
            {
              "date": "YYYY-MM-DD",
              "workout_type": "Push / Pull / Legs / Upper / Lower / Full Body / etc.",
              "focus_note": "Brief focus for this session (e.g., heavy compound emphasis, high-rep pump work).",
              "is_rest_day": false
            }
          ]
        }

        Include every day in the date range. Mark rest days with is_rest_day: true \
        and workout_type: "Rest". Distribute training days intelligently with proper \
        recovery between similar muscle groups. Return ONLY the JSON, no other text.
        """
    }

    /// Build user message requesting a rolling context summary.
    func buildContextSummaryMessage(
        workoutType: String,
        exercises: [Exercise],
        sets: [UUID: [WorkoutSet]]
    ) -> String {
        var lines = ["Summarize this \(workoutType) session for future reference:\n"]

        for exercise in exercises {
            lines.append("**\(exercise.name)** (\(exercise.muscleGroup))")
            let exerciseSets = (sets[exercise.id] ?? []).sorted { $0.setNumber < $1.setNumber }
            for s in exerciseSets {
                lines.append("  Set \(s.setNumber): \(String(format: "%.1f", s.weightLbs)) lbs x \(s.reps) reps @ RIR \(s.rir)")
            }
            lines.append("")
        }

        lines.append("""
        Write a concise rolling summary (3-5 sentences) that captures:
        1. Key lifts and working weights used
        2. Performance trends (strength going up/down/plateau)
        3. What to target next session for progressive overload

        This summary will be used as context for future workout planning. \
        Keep it factual and numbers-focused. Return ONLY the summary text.
        """)

        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private func sanitize(_ input: String) -> String {
        validationService.sanitize(input)
    }

    private func formatEquipment(_ equipment: [String: Bool]) -> String {
        let available = equipment.filter { $0.value }.map { $0.key }
        return available.isEmpty ? "Full gym" : available.joined(separator: ", ")
    }
}
