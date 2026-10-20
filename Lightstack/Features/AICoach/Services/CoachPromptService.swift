import Foundation

/// Owns the system prompt template and parameterization.
/// Injects live profile data into the canonical coach prompt
/// (defined in docs/COACH_PROMPT.md).
final class CoachPromptService {

    private let validationService: ValidationService

    init(validationService: ValidationService) {
        self.validationService = validationService
    }

    /// Which AI task a system prompt is for. Each task gets only the sections it needs,
    /// because the system prompt is sent on every call.
    enum PromptTask {
        case plan, chat, postWorkout, monthPlan
    }

    /// Back-compat entry point: `true` is the plan prompt, `false` the chat prompt.
    func buildSystemPrompt(profile: UserProfile?, includeWorkoutPlanFormat: Bool = true) -> String {
        buildSystemPrompt(profile: profile, task: includeWorkoutPlanFormat ? .plan : .chat)
    }

    /// Build the system prompt for one task with profile data injected.
    func buildSystemPrompt(profile: UserProfile?, task: PromptTask,
                           restSeconds: Int = RestPreference.defaultSeconds) -> String {
        var sections: [String]
        switch task {
        case .plan:
            sections = [Self.identityShort, profileLine(profile), Self.trainingPrinciples,
                        Self.progressionRules, Self.planFormat,
                        "User's preferred rest: \(restSeconds) s; use it for rest_seconds."]
        case .chat:
            sections = [Self.identityShort, profileLine(profile), Self.chatFormat, Self.modificationsRules]
        case .postWorkout:
            sections = [Self.identityShort, profileLine(profile), Self.postWorkoutRules]
        case .monthPlan:
            sections = [Self.identityShort, profileLine(profile), Self.trainingPrinciples]
        }
        return sections.joined(separator: "\n\n")
    }

    // MARK: - Prompt sections

    static let identityShort = """
    COACHING IDENTITY
    You are the Lightstack Coach, a direct, realistic strength and hypertrophy coach. \
    Reference the athlete's actual lifts and numbers. Say what is achievable, not what \
    they want to hear; scale back when they are struggling.
    """

    static let trainingPrinciples = """
    TRAINING PRINCIPLES
    - Intensity is RIR (reps in reserve): 0 = failure, 1-2 = target, 3+ = too easy for hypertrophy.
    - Progressive overload drives programming.
    - Time: 30 min = 3-4 exercises (supersets ok); 45 = 4-5; 60 = 5-6 with full rest.
    - Energy: 1-4 = higher RIR, less volume; 5-7 = standard; 8-10 = push harder, lower RIR.
    - Cardio or non-strength requests (run, HIIT, ...): don't refuse; give a complementary \
    strength or conditioning workout that fits time and energy.
    """

    static let progressionRules = """
    PROGRESSION RULES
    - Base every load on the ACTUAL logged sets in RECENT SESSIONS (weight x reps @RIR), not on \
    guesses. Only estimate from the athlete profile when an exercise has no history.
    - Double progression with a rep range that fits the lift (heavy compounds 5-8, other \
    compounds 6-10, isolation 10-15). If every working set last time reached the top of the range \
    at the target RIR, add a small load (about 2.5-5%, smallest plate step). Otherwise keep the \
    load and aim for more reps. If last time ended at RIR 0 with missed reps, or notes mention \
    pain or fatigue, hold or reduce.
    - Main compound lifts: 1-2 lighter ramp-up sets first (higher RIR; they count in set_targets), \
    then working sets at RIR 2-3, with RIR 0-1 only on the final set, never every set. An \
    optional lighter back-off set may follow.
    - Do not prescribe the same weight x reps on every set of every exercise; vary sets by \
    purpose. Respect energy, time and the preferred rest.
    - Use previous coach notes and the athlete's notes (pain, form, equipment) to adjust.
    - coach_note: one short line saying why, e.g. "Hit 8@2 last time, +5 lb".
    """

    static let planFormat = """
    WORKOUT PLAN FORMAT
    Return ONLY this JSON object, no markdown fences, no other text:
    {"exercises": [{"name": "str", "muscle_group": "str", "sets": int, "target_weight": "str|null", \
    "reps": "str|null (e.g. 8-12)", "rir": "str|null (e.g. 1-2)", "rest_seconds": int|null, \
    "coach_note": "str|null", "superset": "str|null (e.g. A)", \
    "set_targets": [{"weight": "135", "reps": "10", "rir": "3"}]}], "coaching_notes": "str"}
    set_targets lists every set in order (weight in lb as a string, "BW" for bodyweight, reps, rir); \
    give it for every strength exercise so sets can differ, and make "sets" equal its length. \
    Then target_weight / reps / rir describe the top working set.
    Supersets: set "superset" only when asked or clearly useful, else null. Exercises sharing \
    a label alternate sets, are listed adjacent, max 4 per label. Keep coach_note and \
    coaching_notes to one short sentence.
    """

    static let chatFormat = """
    CONVERSATION FORMAT
    The athlete is mid-session and reads your reply as conversation. Be brief: plain prose, \
    no workout plan JSON, no exercise arrays, never a markdown table of exercises.

    The single exception is the fenced modifications block described below: that block is \
    how changes reach the app, so include it when proposing changes. Describing a change in \
    prose without it means nothing happens.
    """

    static let modificationsRules = """
    WORKOUT MODIFICATIONS
    When the athlete asks for a change, say what changes in one or two short sentences (e.g. \
    "Bumping bench to 155 for 10."); skip reasoning unless asked. They confirm before anything \
    applies. Write existing exercises' "name" / "old_name" exactly as in the workout's Exercises list.
    If, and only if, you suggest changes, end with one fenced json block:
    {"modifications": [
     {"action": "add", "name": "", "muscle_group": "", "target_sets": 3, "target_reps": "8-10", "target_rir": "2", "target_weight": "135 lbs", "note": "", "superset": "A"},
     {"action": "remove", "name": ""},
     {"action": "modify", "name": "", "new_target_sets": 4, "new_target_reps": "6-8", "new_target_rir": "1", "new_rest": 120, "new_target_weight": "145 lbs", "note": ""},
     {"action": "modify", "name": "", "sets": [{"weight": "40 lbs", "reps": "8", "rir": "2"}, {"weight": "45 lbs", "reps": "6", "rir": "0-1"}]},
     {"action": "replace", "old_name": "", "new_name": "", "muscle_group": "", "target_sets": 3, "target_reps": "8-10", "target_rir": "2", "note": ""}
    ]}
    Rules:
    - Include only the changes you suggest, in any mix; omit unused optional fields.
    - Omit rest_seconds / new_rest unless the athlete asks for a specific rest.
    - Weights are strings with units ("135 lbs"). RIR may be a range ("1-2"); the app prefills the lower number.
    - When sets differ (pyramid, ramp, top/back-off), give one "sets" entry per set (add, modify, replace); its length is the set count. Otherwise use the single target_* / new_* fields.
    - "note" is a short cue only ("drive through the heels"), never the per-set numbers.
    - "superset" label (add/replace/modify) links 2-4 exercises sharing it; use only when asked or it suits the goal.
    - To change weight on an exercise already in the workout use "modify" with new_target_weight, not "replace".
    - No changes suggested means no JSON block. Never present changes as a markdown table.
    """

    static let postWorkoutRules = """
    POST-WORKOUT OUTPUT
    Reply with ONLY a JSON object: {"note": "...", "summary": "..."}
    - note: the progression note, at most 3 sentences. No greeting, no name. Lead with what \
    happened, end with one specific target for next session (exact weight, reps or duration). Plain text.
    - summary: updated cumulative rolling summary for future planning, at most 120 words. If a \
    previous summary is given, merge it with this session instead of replacing it. Cover the trend \
    over sessions (up/down/plateau) and, per main lift, the last working weight x reps @RIR and the \
    next target. Numbers first.
    """

    /// One-line athlete profile; unknown fields are left out.
    private func profileLine(_ profile: UserProfile?) -> String {
        var parts: [String] = []
        let name = sanitize(profile?.displayName ?? "")
        if !name.isEmpty { parts.append(name) }
        if let age = profile?.age { parts.append("age \(age)") }
        if let w = profile?.weightLbs { parts.append(String(format: "%.0f lb", w)) }
        if let h = profile?.heightInches { parts.append(String(format: "%.0f in", h)) }
        if let t = profile?.trainingAgeMonths { parts.append("\(t) mo training") }
        let goals = sanitize((profile?.primaryGoals ?? []).joined(separator: ", "))
        if !goals.isEmpty { parts.append("goals: \(goals)") }
        let avoid = sanitize((profile?.avoidExercises ?? []).joined(separator: ", "))
        if !avoid.isEmpty { parts.append("avoid: \(avoid)") }
        parts.append("equipment: \(formatEquipment(profile?.equipment ?? [:]))")
        let notes = sanitize(profile?.notesToCoach ?? "")
        if !notes.isEmpty, notes != "None" { parts.append("notes: \(notes)") }
        return "ATHLETE: " + parts.joined(separator: " | ")
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
        recentSessionExercises: [UUID: [Exercise]] = [:],
        recentLoggedSets: [UUID: [WorkoutSet]] = [:],
        bestSets: [String: (weightLbs: Double, reps: Int)] = [:]
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
            message += "\n\nRECENT SESSIONS (newest first; actual logged sets as weight lb x reps @RIR):"
            for workout in recentSessions {
                let dateStr = DateFormatter.shortDate.string(from: workout.date)
                message += "\n\n[\(dateStr)] \(workout.workoutType)"
                if let note = clipped(workout.userNote, 200) { message += "\n  Athlete note: \(note)" }
                if let note = clipped(workout.aiProgressionNote, 240) { message += "\n  Coach note: \(note)" }
                for ex in recentSessionExercises[workout.id] ?? [] {
                    let logged = (recentLoggedSets[ex.id] ?? []).sorted { $0.setNumber < $1.setNumber }
                    guard !logged.isEmpty else { continue }
                    let formatted = ex.trackingType == .cardio
                        ? logged.map { formatCardioSet($0) }
                        : logged.map { formatLoggedSet($0) }
                    var line = "\n  - \(ex.name): " + formatted.joined(separator: ", ")
                    if let best = bestSets[ex.name.lowercased()] {
                        line += " | best \(String(format: "%g", best.weightLbs))x\(best.reps)"
                    }
                    if let cue = clipped(ex.coachNoteParts.message, 100) { line += " | note: \(cue)" }
                    message += line
                }
            }
        }

        message += "\n\nGenerate the JSON workout plan within my time. Base every load on my actual logged sets above (progression rules); estimate from my profile only for exercises with no history."

        return message
    }

    /// Build the ONE post-workout user message: the completed sets, compactly.
    /// The reply is JSON `{"note", "summary"}` (see `postWorkoutRules`).
    func buildPostWorkoutMessage(
        workoutType: String,
        exercises: [Exercise],
        sets: [UUID: [WorkoutSet]],
        previousSummary: String? = nil
    ) -> String {
        var lines: [String] = []
        if let previous = previousSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !previous.isEmpty {
            lines.append("Previous rolling summary: \(sanitize(previous))")
        }
        lines.append("\(sanitize(workoutType)) session, completed sets:")
        for exercise in exercises {
            let exerciseSets = (sets[exercise.id] ?? []).sorted { $0.setNumber < $1.setNumber }
            guard !exerciseSets.isEmpty else { continue }
            let formatted: [String]
            if exercise.trackingType == .cardio {
                formatted = exerciseSets.map { formatCardioSet($0) }
            } else {
                formatted = exerciseSets.map { s in
                    let rir = s.rir.map { "@\($0)" } ?? ""
                    return "\(String(format: "%g", s.weightLbs))x\(s.reps)\(rir)"
                }
            }
            lines.append("\(exercise.name): " + formatted.joined(separator: "; "))
        }
        lines.append("(weight lb x reps @RIR) Return the JSON; the summary must be the updated cumulative one.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Private Cardio Formatting

    private func formatLoggedSet(_ s: WorkoutSet) -> String {
        let rir = s.rir.map { "@\($0)" } ?? ""
        return "\(String(format: "%g", s.weightLbs))x\(s.reps)\(rir)"
    }

    private func clipped(_ text: String?, _ limit: Int) -> String? {
        guard let text else { return nil }
        let clean = sanitize(text).replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        return clean.count > limit ? String(clean.prefix(limit)) + "…" : clean
    }

    private func formatCardioSet(_ s: WorkoutSet) -> String {
        var parts: [String] = []
        if let secs = s.durationSeconds {
            parts.append(CardioFormatting.formatDuration(secs))
        }
        if let miles = s.distanceMiles {
            parts.append(String(format: "%g mi", miles))
        }
        if let incline = s.inclineLevel {
            parts.append(String(format: "%g%% incline", incline))
        }
        return parts.isEmpty ? "no metrics" : parts.joined(separator: ", ")
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
        Month training plan. Goal: \(sanitizedGoal). Days/week: \(clampedDays). Range: \(startStr) to \(endStr).
        Return ONLY JSON: {"overview": "1-2 sentences", "sessions": [{"date": "YYYY-MM-DD", \
        "workout_type": "Push/Pull/Legs/Upper/Lower/Full Body/Rest/...", "focus_note": "short", \
        "is_rest_day": false}]}
        One entry for every day in the range; rest days use is_rest_day true and workout_type "Rest". \
        Space similar muscle groups for recovery.
        """
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
