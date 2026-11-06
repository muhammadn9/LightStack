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
    /// - Parameter aiSetsWeights: the plan prompt for coach v3 (the coach writes every number) when true,
    ///   the v2 review prompt (the app writes the numbers) when false.
    func buildSystemPrompt(profile: UserProfile?, task: PromptTask,
                           restSeconds: Int = RestPreference.defaultSeconds,
                           aiSetsWeights: Bool = CoachPreferences.aiSetsWeights) -> String {
        var sections: [String]
        switch task {
        case .plan:
            if aiSetsWeights {
                sections = [Self.identityShort, profileLine(profile), Self.trainingPrinciples,
                            Self.writeRules, Self.planFormatV3,
                            "User's preferred rest: \(restSeconds) s (a default for isolation and back-off sets; you set rest per set)."]
            } else {
                sections = [Self.identityShort, profileLine(profile), Self.trainingPrinciples,
                            Self.reviewRules, Self.planFormat,
                            "User's preferred rest: \(restSeconds) s (the floor for isolation and back-off rest)."]
            }
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
    - An exercise marked "(per arm)" is single-side: its weights are per arm, not totals (25 lb per arm = 50 lb moved).
    - Cardio or non-strength requests (run, HIIT, ...): don't refuse; give a complementary \
    strength or conditioning workout that fits time and energy.
    """

    /// Coach v3: the coach writes every set. The app only enforces wide safety rails.
    static let writeRules = """
    YOUR JOB: WRITE TODAY'S PLAN
    You choose every exercise, set, weight (lb), rep, RIR and rest. The app checks each exercise against wide safety rails; \
    an exercise outside them is replaced by the app's rule-based baseline, so stay inside:
    - Top weight at most +10% over that lift's last top set (small lifts: one increment).
    - Never an estimated 1RM above the recent best +5%.
    - More than 14 days since the lift: no increase; more than 28 days: start 5-10% lighter.
    - RIR 0 on at most one set per exercise; most working sets RIR 1-2.
    Structure: warm-ups (type "warmup") only where you judge the working weight needs them, usually the first heavy compound. \
    2-4 working sets. No back-off unless it serves today's goal. Isolation 2-3 sets. Never pad sets.
    Use the BRIEF (rep style, last RIR, e1RM trend, rest actually taken: long rests mean hard sets, muscle load, fuel). \
    Each exercise gets one "reason" (max 15 words) naming the evidence.
    Heavy compounds first; at most 10 hard sets per muscle; fit the time; keep the athlete's usual exercise selection \
    (the APP BASELINE is the rule-based reference, not a limit). Balance movements and muscles; a missing one (e.g. rear delts on a pull day) is worth adding.
    Respect PREVIOUS REVIEWS: a "retry" or "reduceAndRebuild" decision stands. ROLLING CONTEXT is background only. \
    Use the athlete's notes (pain, form, equipment) to choose exercises.
    """

    static let planFormatV3 = """
    WORKOUT PLAN FORMAT
    Return ONLY this JSON object, no markdown fences, no other text:
    {"summary": "str, 1-2 sentences", "exercises": [{"name": "str", "muscle_group": "str", "superset": "str|null (e.g. A)", \
    "cue": "str|null", "reason": "str", "sets": [{"type": "warmup|work", "weight": number (0 = bodyweight), "reps": int, \
    "rir": int, "rest": int (seconds)}]}], "coaching_notes": "str"}
    "exercises" is the final ordered list. "cue" only for a known form issue. Keep coaching_notes to one short sentence. \
    Names: use the athlete's existing name from ATHLETE'S EXERCISE NAMES verbatim when it is the same movement; \
    only invent a new name for a genuinely new movement. Never put "(per arm)" in a name.
    Supersets: set "superset" only when asked or clearly useful; same label alternates sets, adjacent, max 4.
    """

    /// Gemini `responseSchema` for the coach v3 plan reply (see `planFormatV3`).
    static let planResponseSchema: AIResponseSchema = {
        func field(_ type: String, nullable: Bool = false) -> [String: Any] {
            var f: [String: Any] = ["type": type]
            if nullable { f["nullable"] = true }
            return f
        }
        let setType: [String: Any] = ["type": "STRING", "enum": ["warmup", "work"]]
        let setProperties: [String: Any] = [
            "type": setType, "weight": field("NUMBER"), "reps": field("INTEGER"),
            "rir": field("INTEGER"), "rest": field("INTEGER")
        ]
        let setItem: [String: Any] = [
            "type": "OBJECT", "properties": setProperties, "required": ["type", "weight", "reps", "rir", "rest"]
        ]
        let exerciseProperties: [String: Any] = [
            "name": field("STRING"), "muscle_group": field("STRING"),
            "superset": field("STRING", nullable: true), "cue": field("STRING", nullable: true),
            "reason": field("STRING"),
            "sets": ["type": "ARRAY", "items": setItem] as [String: Any]
        ]
        let exerciseItem: [String: Any] = [
            "type": "OBJECT", "properties": exerciseProperties, "required": ["name", "muscle_group", "reason", "sets"]
        ]
        let root: [String: Any] = [
            "type": "OBJECT",
            "properties": [
                "summary": field("STRING"),
                "exercises": ["type": "ARRAY", "items": exerciseItem] as [String: Any],
                "coaching_notes": field("STRING")
            ] as [String: Any],
            "required": ["summary", "exercises"]
        ]
        return AIResponseSchema(root)
    }()

    static let reviewRules = """
    YOUR JOB: REVIEW THE DRAFT
    The app already wrote a DRAFT plan from the athlete's last session and your own earlier reviews: \
    per main lift a warm-up (first lifts only), Set 1, ONE top set and a back-off; isolation 2 sets; \
    rest prescribed per set. The app owns every weight, rep and RIR: do no load arithmetic. \
    Review the STRUCTURE like a real coach; do not rubber-stamp it. Check:
    1. Order: heavy compounds first.
    2. Balance: too much of one movement or muscle, or a missing one (e.g. rear delts on a pull day).
    3. Volume: 6-10 hard sets per muscle per session at most.
    4. Recovery: days since each muscle was trained (given); recently trained muscles get less.
    5. Energy, sleep and fuel, time available, constraints.
    6. Would a coach recommend this structure for the athlete's focus?
    Use the BRIEF (lift style, effort, rest actually taken, muscle load, fuel) when judging the plan.
    Return concrete edits, each with a reason; if the draft is sound say so with no changes. \
    Respect PREVIOUS REVIEWS: a "retry" or "reduceAndRebuild" decision stands, and recurring flags should be addressed.
    ROLLING CONTEXT is background only; never restate its numbers as the plan. Use the athlete's notes (pain, form, equipment) to choose exercises.
    """

    static let planFormat = """
    WORKOUT PLAN FORMAT
    Return ONLY this JSON object, no markdown fences, no other text:
    {"review": {"verdict": "sound|adjusted", "summary": "str, 1-2 sentences", "changes": [{"type": "reorder|swap|drop|add|setCount|loadAdjust", \
    "exercise": "str", "detail": "str", "reason": "str", "sets": int|null, "percent": number|null}]}, \
    "exercises": [{"name": "str", "muscle_group": "str", "coach_note": "str|null", "cue": "str|null", "rest_seconds": int|null, \
    "superset": "str|null (e.g. A)", "set_targets": [{"weight": "135", "reps": "10", "rir": "3"}]}], "coaching_notes": "str"}
    "exercises" is the FINAL ordered list: each draft exercise you keep (exact draft name) plus new ones. \
    set_targets ONLY for NEW exercises with no history (weight in lb as a string, "BW" for bodyweight): \
    3 sets for a main lift (Set 1, top set, back-off), 2 for isolation, never RIR 0-1 on every set; \
    for kept exercises the app fills the numbers.
    Change types: reorder (reflect it in the list order), swap ("exercise" is replaced by the lift named in detail), \
    drop, add, setCount ("sets" = working sets; never add heavy sets), loadAdjust ("percent" -15 to 5).
    Names: for every exercise (kept, swapped or added), use the athlete's existing name from ATHLETE'S EXERCISE NAMES verbatim \
    when it is the same movement; only invent a new name for a genuinely new movement. Never put "(per arm)" in a name.
    "cue" only for a known form issue. Keep coach_note and coaching_notes to one short sentence. \
    Supersets: set "superset" only when asked or clearly useful; same label alternates sets, adjacent, max 4.
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
    POST-WORKOUT REVIEW
    Reply with ONLY a JSON object:
    {"exercises": [{"name": "str (as given)", "notes": "1-3 sentences", "outcome": "pr|hold|regression|missed|new", \
    "next_target": {"weight": number, "reps": int, "note": "short goal"}, \
    "miss": {"cause": "lowEnergy|poorRecovery|painOrForm|strengthLoss|afterBreak|unknown", "decision": "retry|reduceAndRebuild|holdOrSwap", "reason": "str"}}], \
    "overall_read": "2-3 sentences", "recurring_flags": ["str"]}
    - Use the app's PRESCRIBED vs ACTUAL analysis; do not recompute it. notes: what happened, PR/hold/regression, form flags.
    - "miss" only for exercises marked MISSED. A miss is a learning moment: a single miss (a bad day, or a close \
    miss even with good energy) -> retry the same target; a second miss in a row, "too heavy" or a miss by 3+ reps \
    -> likely lost strength -> reduceAndRebuild (drop 5-10%); lighter than planned after the lift was skipped or \
    not done for 2+ weeks -> afterBreak (a rebuild, not lost strength) -> retry from today's weight; pain or form \
    -> holdOrSwap. Never call one miss "strength loss". Check PREVIOUS REVIEWS for repeats.
    - next_target: one specific goal per exercise, near what was lifted (within -15% to +5%).
    - overall_read: session quality, energy, patterns. recurring_flags: issues seen across sessions \
    (skipped exercises, form, repeated misses).
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
        bestSets: [String: (weightLbs: Double, reps: Int)] = [:],
        exerciseLibrary: [String] = [],
        coach: PlanPromptExtras? = nil,
        aiSetsWeights: Bool = CoachPreferences.aiSetsWeights
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
        if let coach {
            message += "\n- Focus: \(Self.focusText(coach.focus))"
            if let constraints = clipped(coach.constraints, 300) { message += "\n- Constraints: \(constraints)" }
        }

        if let summary = rollingSummary, !summary.isEmpty {
            message += "\n\nROLLING CONTEXT (recent history summary):\n\(summary)"
        }

        // Most-used first (the caller sorts by set count); capped to keep the prompt small.
        let libraryNames = exerciseLibrary.map { sanitize($0) }.filter { !$0.isEmpty }.prefix(80)
        if !libraryNames.isEmpty {
            message += "\n\nATHLETE'S EXERCISE NAMES (most used first; reuse verbatim for the same movement):\n"
                + libraryNames.joined(separator: "; ")
        }

        if let latest = recentSessions.first {
            let index = ExerciseHistoryIndex(
                sessions: recentSessions, exercises: recentSessionExercises,
                loggedSets: recentLoggedSets, bestSets: bestSets)

            message += "\n\nLAST SESSION (every set in order, as weight lb x reps @RIR):"
            let dateStr = DateFormatter.shortDate.string(from: latest.date)
            message += "\n\n[\(dateStr)] \(latest.workoutType)"
            if let note = clipped(latest.userNote, 200) { message += "\n  Athlete note: \(note)" }
            for ex in recentSessionExercises[latest.id] ?? [] {
                let logged = (recentLoggedSets[ex.id] ?? []).sorted { $0.setNumber < $1.setNumber }
                guard !logged.isEmpty else { continue }
                let formatted = ex.trackingType == .cardio
                    ? logged.map { formatCardioSet($0) }
                    : logged.map { formatLoggedSet($0) }
                var line = "\n  - \(ex.name)\(Self.perArmTag(ex)): " + formatted.joined(separator: ", ")
                if ex.trackingType != .cardio, let best = index.group(for: ex.name)?.best {
                    line += " | all-time best \(String(format: "%g", best.weight))x\(best.reps)"
                }
                if let cue = clipped(ex.coachNoteParts.message, 100) { line += " | note: \(cue)" }
                message += line
            }

            let trendGroups = index.groups.filter { $0.sessions.count >= 2 }
            if !trendGroups.isEmpty {
                message += "\n\nEARLIER TREND PER EXERCISE (oldest to newest, same-lift names merged, working and warm-up sets as weight x reps, \"top\" = heaviest set of a pyramid/top-set day):"
                let perArmGroups = Set(recentSessionExercises.values.flatMap { $0 }
                    .filter(\.isPerArm).compactMap { index.group(for: $0.name)?.displayName })
                for group in trendGroups {
                    message += "\n  - \(group.displayName)\(perArmGroups.contains(group.displayName) ? " (per arm)" : ""): "
                        + ExerciseHistoryIndex.trendLine(for: group.sessions) { Self.trendDate.string(from: $0) }
                }
            }
        }

        if let coach {
            message += planReviewSections(coach, latest: recentSessions.first, logged: recentLoggedSets,
                                          exercises: recentSessionExercises, aiSetsWeights: aiSetsWeights)
        }

        if coach != nil, aiSetsWeights {
            return message + "\n\nWrite today's plan and return the JSON: the final ordered exercise list, each exercise with your sets (type, weight lb, reps, RIR, rest) and a one-line reason naming the evidence. The APP BASELINE is a reference, not a limit; stay inside the safety rails."
        }
        if coach != nil {
            return message + "\n\nReview the DRAFT PLAN against your checklist and return the JSON: the final ordered exercise list plus your review. Keep every draft exercise you do not change, by its exact name; give set_targets only for new exercises."
        }

        message += "\n\nGenerate the JSON workout plan within my time. Choose and order exercises from my usual selection for this workout type. The app fills in sets, weights, reps and RIR for exercises I have history for (give them \"sets\": 3 and a short coach_note); give set_targets only for new exercises."

        return message
    }

    /// Build the ONE post-workout user message: the completed sets, compactly, plus (when the app has
    /// analysed them) prescribed vs actual per exercise, the athlete's context and past reviews.
    /// The reply is the review JSON (see `postWorkoutRules`).
    func buildPostWorkoutMessage(
        workoutType: String,
        exercises: [Exercise],
        sets: [UUID: [WorkoutSet]],
        previousSummary: String? = nil,
        analysis: SessionAnalysis? = nil,
        previousReviews: [CoachReviewEntry] = [],
        userNote: String? = nil
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
            lines.append("\(exercise.name)\(Self.perArmTag(exercise)): " + formatted.joined(separator: "; "))
        }
        lines.append("(weight lb x reps @RIR)")
        if let analysis {
            lines.append("Energy today: \(analysis.energy)/10.")
            if let note = clipped(userNote ?? analysis.userNote, 300) { lines.append("Athlete note: \(note)") }
            let prescribed = analysis.exercises.filter { $0.prescribedTop != nil }
            if !prescribed.isEmpty {
                lines.append("\nPRESCRIBED vs ACTUAL (analysed by the app; MISSED = top set short of plan):")
                for a in prescribed { lines.append("- " + a.promptLine) }
            }
            if !analysis.skipped.isEmpty { lines.append("SKIPPED (prescribed, not done): " + analysis.skipped.joined(separator: ", ")) }
        }
        if !previousReviews.isEmpty {
            lines.append("\nPREVIOUS REVIEWS (newest first, same workout type):")
            lines.append(contentsOf: previousReviews.map { reviewLine($0) })
        }
        lines.append("\nReturn the review JSON.")
        return lines.joined(separator: "\n")
    }

    /// " (per arm)" after the name of a single-side exercise, so its weights are not read as totals.
    static func perArmTag(_ exercise: Exercise) -> String {
        exercise.isPerArm ? " (per arm)" : ""
    }

    // MARK: - Private Cardio Formatting

    private static let trendDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd"
        return f
    }()

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

    // MARK: - Plan review sections

    /// Everything the plan call gets beyond the history the message already carries.
    struct PlanPromptExtras {
        var focus: CoachFocus = .hypertrophy
        var constraints: String?
        var draft: [DraftExercise] = []
        var estimatedMinutes: Double?
        var reviews: [CoachReviewEntry] = []
        var recency: [String: MuscleRecency] = [:]
        var now: Date = Date()
        /// Compact per-exercise brief from `briefBlock`, appended after the draft.
        var briefBlock: String?
    }

    static func focusText(_ focus: CoachFocus) -> String {
        switch focus {
        case .hypertrophy: return "hypertrophy (top sets 6-10 reps, RIR 1-2)"
        case .strength: return "strength (top sets 3-6 reps, longer rest)"
        case .maintenance: return "maintenance (hold loads, keep volume low)"
        }
    }

    private func planReviewSections(
        _ coach: PlanPromptExtras, latest: Workout?, logged: [UUID: [WorkoutSet]], exercises: [UUID: [Exercise]],
        aiSetsWeights: Bool
    ) -> String {
        var out = ""

        // Recency
        let recent = coach.recency.filter { $0.value.hoursSince(coach.now) <= 7 * 24 }
            .sorted { $0.value.lastTrained > $1.value.lastTrained }
        out += "\n\nDAYS SINCE EACH MUSCLE WAS TRAINED (all workout types; unlisted = 7+ days):"
        if recent.isEmpty { out += "\n  none in the last week" }
        for (muscle, r) in recent {
            out += "\n  - \(muscle): \(String(format: "%.1f", r.hoursSince(coach.now) / 24)) d (\(r.hardSets) hard sets)"
        }

        // Past reviews
        if !coach.reviews.isEmpty {
            out += "\n\nPREVIOUS REVIEWS (your own, newest first):"
            for entry in coach.reviews { out += "\n" + reviewLine(entry) }
        }

        // Prescribed vs actual for the last session
        if let latest, let doc = CoachReviewDocument.parse(latest.aiProgressionNote), !doc.prescription.isEmpty {
            out += "\n\nLAST SESSION PRESCRIBED vs ACTUAL:"
            for p in doc.prescription {
                let ex = (exercises[latest.id] ?? []).first { ExerciseNameResolver.isMatch($0.name, p.name) }
                let did = ex.map { (logged[$0.id] ?? []).sorted { $0.setNumber < $1.setNumber }.map { formatLoggedSet($0) } } ?? []
                let planned = p.sets.map { "\($0.role.label.lowercased()) \($0.text)" }.joined(separator: ", ")
                out += "\n  - \(sanitize(p.name)): planned [\(planned)] | did [\(did.isEmpty ? "not done" : did.joined(separator: ", "))]"
            }
        }

        // Draft
        out += aiSetsWeights
            ? "\n\nAPP BASELINE (rule-based; use as a reference):"
            : "\n\nDRAFT PLAN (computed by the app from the last session and your targets; review it):"
        if coach.draft.isEmpty {
            out += aiSetsWeights
                ? "\n  none: no same-type history yet, so build the plan from scratch (2-4 working sets for main lifts, 2-3 for isolation)."
                : "\n  none: no same-type history yet, so build the plan from scratch with set_targets for every exercise (3 sets for main lifts, 2 for isolation)."
        }
        for (i, d) in coach.draft.enumerated() {
            let sets = d.result.sets.map { "\($0.role.label.lowercased()) \(String(format: "%g", $0.weight))x\($0.reps)@\($0.rir)" }
            let rests = d.result.sets.map { String($0.restSeconds) }.joined(separator: "/")
            out += "\n  \(i + 1). \(sanitize(d.name)) (\(d.muscleGroup)): " + sets.joined(separator: " · ") + " | rest \(rests) s"
            out += "\n     why: \(d.result.rationale)"
        }
        if let minutes = coach.estimatedMinutes {
            out += "\n  Estimated length of the \(aiSetsWeights ? "baseline" : "draft"): ~\(Int(minutes.rounded())) min."
        }
        if let brief = coach.briefBlock, !brief.isEmpty { out += "\n\n" + brief }
        return out
    }

    // MARK: - Brief

    /// The compact BRIEF block (about 60 tokens per exercise): usual session length, fuel, muscle load
    /// and one line per planned exercise. Parts without data are left out; nil when nothing is left.
    func briefBlock(briefs: [ExerciseBrief], muscleLoad: [String: MuscleLoad],
                    fuel: CoachFuelSummary?, usualMinutes: Int?) -> String? {
        var lines: [String] = []

        var header: [String] = []
        if let usualMinutes { header.append("USUAL SESSION: \(usualMinutes) min (recent median).") }
        if let fuel, let text = Self.fuelText(fuel) { header.append("FUEL: \(text)") }
        if !header.isEmpty { lines.append(header.joined(separator: " ")) }

        var muscles: [String] = []
        for brief in briefs {
            for muscle in brief.muscles where !muscles.contains(muscle) { muscles.append(muscle) }
        }
        let loadParts = muscles.prefix(8).compactMap { muscle -> String? in
            guard let load = muscleLoad[muscle] else { return nil }
            let days = load.daysSince.map { "\($0)d" } ?? "28d+"
            return "\(sanitize(muscle)) \(Self.setCount(load.thisWeekSets))/\(Self.setCount(load.avgPrior3WeeksSets)) \(days)"
        }
        if !loadParts.isEmpty {
            lines.append("MUSCLE LOAD (hard sets this wk / weekly avg prior 3 wks, days since): " + loadParts.joined(separator: " · "))
        }

        if !briefs.isEmpty {
            lines.append("BRIEF (style, last top, e1RM trend, set-to-set rest actual vs prescribed heavy | light, muscles):")
            for brief in briefs { lines.append("- " + briefLine(brief)) }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func briefLine(_ brief: ExerciseBrief) -> String {
        let reps = brief.repLow == brief.repHigh ? "\(brief.repLow)" : "\(brief.repLow)-\(brief.repHigh)"
        var parts = ["\(brief.style.label) (\(reps))"]
        parts.append("last " + Self.setText(brief.lastTop))
        if let avg = brief.avgRIR { parts.append("avg RIR \(String(format: "%g", (avg * 10).rounded() / 10))") }
        if !brief.e1RMTrend.isEmpty { parts.append("e1RM " + brief.e1RMTrend.map(String.init).joined(separator: ">")) }
        if let rest = Self.restText(brief.rest) { parts.append(rest) }
        if let base = brief.baselineTop {
            parts.append("draft top \(String(format: "%g", base.weight))x\(base.reps)@\(base.rir)")
        }
        let muscleText = brief.muscles.map { sanitize($0) }.joined(separator: "+")
        if !muscleText.isEmpty { parts.append(muscleText) }
        return "\(sanitize(brief.name)): " + parts.joined(separator: ", ")
    }

    private static func setText(_ set: HistorySet) -> String {
        "\(String(format: "%g", set.weight))x\(set.reps)" + (set.rir.map { "@\($0)" } ?? "")
    }

    private static func setCount(_ value: Double) -> String {
        String(format: "%g", (value * 2).rounded() / 2)
    }

    private static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func restSide(_ actual: Int?, _ prescribed: Int?) -> String {
        guard let actual else { return "-" }
        return clock(actual) + (prescribed.map { " (rx \(clock($0)))" } ?? "")
    }

    /// "rest 2:50 (rx 2:00) | 1:30 (rx 1:30)": heavy then light; nil with no samples.
    private static func restText(_ rest: RestStats) -> String? {
        guard !rest.isEmpty, rest.heavyActual != nil || rest.lightActual != nil else { return nil }
        if rest.lightActual == nil { return "rest " + restSide(rest.heavyActual, rest.heavyPrescribed) }
        return "rest " + restSide(rest.heavyActual, rest.heavyPrescribed) + " | " + restSide(rest.lightActual, rest.lightPrescribed)
    }

    /// "yesterday 2450/2600 kcal, protein 150/180 g; goal lose 0.5 lb/wk." or nil with nothing to say.
    static func fuelText(_ fuel: CoachFuelSummary) -> String? {
        func amount(_ value: Double?, _ target: Double?) -> String? {
            guard let value else { return nil }
            let v = String(format: "%.0f", value)
            return target.map { "\(v)/\(String(format: "%.0f", $0))" } ?? v
        }
        var intake: [String] = []
        if let kcal = amount(fuel.yesterdayKcal, fuel.targetKcal) { intake.append("yesterday \(kcal) kcal") }
        if let protein = amount(fuel.proteinG, fuel.targetProteinG) { intake.append("protein \(protein) g") }
        var text = intake.joined(separator: ", ")
        if let goal = fuel.goal, !goal.isEmpty {
            var goalText = "goal \(goal)"
            if let rate = fuel.weeklyRate, rate > 0, goal != "maintain" { goalText += " \(String(format: "%g", rate)) lb/wk" }
            text += text.isEmpty ? goalText : "; " + goalText
        }
        return text.isEmpty ? nil : text + "."
    }

    /// One block per past review: overall read, per-exercise outcome/decision/target, flags.
    private func reviewLine(_ entry: CoachReviewEntry) -> String {
        let date = Self.trendDate.string(from: entry.date)
        guard let review = entry.document.review else { return "[\(date)] \(sanitize(entry.workoutType)): (no review)" }
        var line = "[\(date)] \(sanitize(entry.workoutType)): \(clipped(review.overallRead, 220) ?? "")"
        for ex in review.exercises {
            var part = "\n    - \(sanitize(ex.name)): \(ex.outcome.rawValue)"
            if let m = ex.missAnalysis { part += " [\(m.cause.rawValue) -> \(m.decision.rawValue)]" }
            if let t = ex.nextTarget { part += ", next \(t.text)" }
            if let note = clipped(ex.notes, 110) { part += " | \(note)" }
            line += part
        }
        if !review.recurringFlags.isEmpty {
            line += "\n    flags: " + review.recurringFlags.compactMap { clipped($0, 100) }.joined(separator: "; ")
        }
        let reasons = entry.document.inSessionReasons
        if !reasons.isEmpty {
            line += "\n    athlete said: " + reasons.sorted { $0.key < $1.key }
                .compactMap { k, v in clipped(v, 60).map { "\(sanitize(k)) \($0)" } }.joined(separator: "; ")
        }
        return line
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
