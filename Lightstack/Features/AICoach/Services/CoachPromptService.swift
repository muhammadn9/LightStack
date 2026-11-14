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
                        Self.decisionRules, Self.fuelRulesPlan, Self.planFormat,
                        "User's preferred rest: \(restSeconds) s (the app uses it as the floor for isolation and back-off rest)."]
        case .chat:
            sections = [Self.identityShort, profileLine(profile), Self.chatFormat, Self.fuelRulesChat, Self.modificationsRules]
        case .postWorkout:
            sections = [Self.identityShort, profileLine(profile), Self.postWorkoutRules, Self.fuelRulesPost]
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

    /// The coach reviews the app's draft and decides per lift; the app writes every number.
    static let decisionRules = """
    YOUR JOB: DECIDE ON THE APP'S DRAFT
    You are the coach reviewing the app's DRAFT PLAN. The app computes every weight and rep from the athlete's log, \
    so never write numbers for a lift that has history. Your job is the judgement the rules lack: the athlete's notes \
    (pain, form, equipment), conflicting signals, COACH MEMORY (what happened after your past calls), balance and \
    missing muscles, order, time fit and ACTIVE GOALS. Give ONE decision per lift:
    - as_planned: the draft as it is. This is the default; most lifts stay here.
    - push: one progression step beyond the draft. Only with clear evidence the lift is ready.
    - ease: lighter by "percent" (-2.5 to -15, default -5) for pain, fatigue, a recent miss or a form note.
    - goal_step: take today's step from ACTIVE GOALS for that lift.
    - swap: replace a draft lift ("replaces" = its exact draft name) with another movement. add: a new lift. \
    "starting_sets" ONLY for a swap or add that has no history in the context (2-3 work sets, 5-15 reps, RIR 2 or more, \
    weights below what the athlete lifts on similar movements). List lifts you remove in "dropped" with a reason. \
    "sets" optionally asks for a working-set count.
    The app refuses what its rules forbid and tells the athlete. When the NOTE says muscles were trained hours ago, or \
    FUEL is low, do not push (the app will refuse) and say so in the summary in one plain sentence.
    Every lift needs a "reason" of at most 18 words that cites specific evidence from the context: a number, date, note \
    or flag (for example "185x5@1 on 11/12, one rep short, repeat it"). Never generic phrases such as "progressing \
    strength" or "driving hypertrophy".
    Heavy compounds first; at most 10 hard sets per muscle; fit the time; keep the athlete's usual selection. A missing \
    muscle (for example rear delts on a pull day) is worth adding. Respect PREVIOUS REVIEWS (a "retry" or \
    "reduceAndRebuild" decision stands) and COACH MEMORY (repeat what worked, change what missed, say so in the reason). \
    Use the athlete's notes (pain, form, equipment) to choose exercises.
    The summary speaks to the athlete: 1-2 plain sentences, no hype, no em dashes.
    """

    /// How the plan call may use the FUEL and PRE-WORKOUT MEALS blocks.
    static let fuelRulesPlan = """
    FUEL AND MEALS
    Use FUEL and PRE-WORKOUT MEALS only to decide how hard to push today.
    - Be conservative (hold or slightly reduce top-set targets, do not progress) after a large high-fat meal within about 2 h of training, \
    very low carbs in the last 24 h, a deep deficit (7-day average more than 20% under target), low protein (average under 80% of target), \
    or weight dropping faster than 1.5x the goal rate.
    - Well fueled, on target, or in a gaining phase: normal progression is fine.
    - When fuel changed an exercise's decision, say so in that exercise's one-line reason.
    - Never moralise about food or give diet advice beyond "eating closer to your targets would help".
    - If FUEL says the data is unreliable, ignore the intake numbers.
    """

    /// How the chat may use the FUEL and PRE-WORKOUT MEALS blocks.
    static let fuelRulesChat = """
    FUEL AND MEALS
    When the athlete asks how to eat today, answer from the FUEL numbers and their targets (the day is not over, so judge what is left). \
    Use fuel and meals to judge how hard to train: be conservative after a heavy high-fat meal within about 2 h, very low carbs, \
    a deep deficit (more than 20% under target), low protein (under 80%) or fast weight loss; well fueled means normal progression. \
    Never moralise about food or give diet advice beyond "eating closer to your targets would help". \
    If FUEL says the data is unreliable, ignore the intake numbers.
    """

    /// How the post-workout review may use the FUEL and PRE-WORKOUT MEALS blocks.
    static let fuelRulesPost = """
    FUEL AND MEALS
    A miss soon after a heavy meal (within about 2 h) or on low fuel (deep deficit, low protein, fast weight loss) is a bad day, \
    not lost strength: say so, and keep the same target. Never moralise about food or give diet advice beyond \
    "eating closer to your targets would help". If FUEL says the data is unreliable, ignore the intake numbers.
    """

    static let planFormat = """
    WORKOUT PLAN FORMAT
    Return ONLY this JSON object, no markdown fences, no other text:
    {"summary": "str", "exercises": [{"name": "str", "decision": "as_planned|push|ease|goal_step|swap|add", "percent": number, \
    "sets": int, "replaces": "str", "reason": "str", "cue": "str", "superset": "str", "starting_sets": [{"type": "warmup|work", \
    "weight": number, "reps": int, "rir": int, "rest": int}]}], "dropped": [{"name": "str", "reason": "str"}], "coaching_notes": "str"}
    "exercises" is the FINAL ordered list. Leave out keys you do not need (no nulls): "percent" only with ease, "replaces" \
    only with swap, "cue" only for a known form issue, "starting_sets" only for a lift with no history. \
    Use the exact draft name for draft lifts; for a new lift reuse the athlete's name from ATHLETE'S EXERCISE NAMES \
    when it is the same movement. Never put "(per arm)" in a name. Keep coaching_notes to one short sentence.
    Supersets: set "superset" only when asked or clearly useful; same label alternates sets, adjacent, max 4.
    """

    /// Gemini `responseSchema` for the plan reply (see `planFormat`). Compact: optional keys are simply left out.
    static let planResponseSchema: AIResponseSchema = {
        func field(_ type: String) -> [String: Any] { ["type": type] }
        let startingSet: [String: Any] = [
            "type": "OBJECT",
            "properties": [
                "type": ["type": "STRING", "enum": ["warmup", "work"]] as [String: Any],
                "weight": field("NUMBER"), "reps": field("INTEGER"), "rir": field("INTEGER"), "rest": field("INTEGER")
            ] as [String: Any],
            "required": ["type", "weight", "reps", "rir"]
        ]
        let exercise: [String: Any] = [
            "type": "OBJECT",
            "properties": [
                "name": field("STRING"),
                "decision": ["type": "STRING", "enum": ["as_planned", "push", "ease", "goal_step", "swap", "add"]] as [String: Any],
                "percent": field("NUMBER"), "sets": field("INTEGER"), "replaces": field("STRING"),
                "reason": field("STRING"), "cue": field("STRING"), "superset": field("STRING"),
                "starting_sets": ["type": "ARRAY", "items": startingSet] as [String: Any]
            ] as [String: Any],
            "required": ["name", "decision", "reason"]
        ]
        let dropped: [String: Any] = [
            "type": "OBJECT",
            "properties": ["name": field("STRING"), "reason": field("STRING")] as [String: Any],
            "required": ["name", "reason"]
        ]
        let root: [String: Any] = [
            "type": "OBJECT",
            "properties": [
                "summary": field("STRING"),
                "exercises": ["type": "ARRAY", "items": exercise] as [String: Any],
                "dropped": ["type": "ARRAY", "items": dropped] as [String: Any],
                "coaching_notes": field("STRING")
            ] as [String: Any],
            "required": ["summary", "exercises"]
        ]
        return AIResponseSchema(root)
    }()

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
    "miss": {"cause": "lowEnergy|poorRecovery|painOrForm|strengthLoss|afterBreak|unknown", "decision": "retry|reduceAndRebuild|holdOrSwap", "reason": "str"}, \
    "memory_note": "max 100 chars: what to remember about this lift; rewrite the previous note"}], \
    "overall_read": "2-3 sentences", "recurring_flags": ["str"]}
    - Use the app's PRESCRIBED vs ACTUAL analysis; do not recompute it. notes: what happened, PR/hold/regression, form flags.
    - "miss" only for exercises marked MISSED. A miss is a learning moment: a single miss (a bad day, or a close \
    miss even with good energy) -> retry the same target; a second miss in a row, "too heavy" or a miss by 3+ reps \
    -> likely lost strength -> reduceAndRebuild (drop 5-10%); lighter than planned after the lift was skipped or \
    not done for 2+ weeks -> afterBreak (a rebuild, not lost strength) -> retry from today's weight; pain or form \
    -> holdOrSwap. Never call one miss "strength loss". Check PREVIOUS REVIEWS for repeats.
    - next_target: one specific goal per exercise, near what was lifted (within -15% to +5%).
    - memory_note: one short line per exercise, kept for future plans (what works, what misses, rest, cues). \
    Rewrite the PREVIOUS COACH NOTE with today's evidence instead of piling on; no quotes or line breaks.
    - GOAL HIT: when the message says an athlete goal was reached, congratulate them in overall_read.
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

    /// Build the user message requesting a workout plan. The app's draft comes first, one block per lift with the
    /// facts the decision needs (each fact once); session-level facts follow.
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
        coach: PlanPromptExtras? = nil
    ) -> String {
        let sanitizedType = sanitize(workoutType)
        let sanitizedNotes = notes.map { sanitize($0) } ?? ""
        let clampedTime = validationService.sanitizeInteger(time, min: 15, max: 120)
        let clampedEnergy = validationService.sanitizeInteger(energy, min: 1, max: 10)

        var blocks: [String] = []
        if let note = coach?.recencyNote, !note.isEmpty { blocks.append(note) }

        var header = "Today: \(sanitizedType), \(clampedTime) min available"
        if let usual = coach?.usualMinutes { header += " (usual \(usual) min)" }
        header += ", energy \(clampedEnergy)/10."
        if let coach { header += " Focus: \(Self.focusText(coach.focus))." }
        if !sanitizedNotes.isEmpty { header += "\nNotes: \(sanitizedNotes)" }
        if let constraints = clipped(coach?.constraints, 300) { header += "\nConstraints: \(constraints)" }
        blocks.append(header)

        let index = ExerciseHistoryIndex(
            sessions: recentSessions, exercises: recentSessionExercises, loggedSets: recentLoggedSets, bestSets: bestSets)
        let latest = recentSessions.first
        blocks.append(contentsOf: planBlocks(coach ?? PlanPromptExtras(), latest: latest, index: index, workoutType: sanitizedType,
                                             exerciseLibrary: exerciseLibrary, rollingSummary: rollingSummary,
                                             sessions: recentSessions, exercises: recentSessionExercises, logged: recentLoggedSets))
        blocks.append("Return the JSON: one decision per lift (default as_planned), a reason that cites evidence, and a short summary.")
        return blocks.joined(separator: "\n\n")
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
        userNote: String? = nil,
        previousNotes: [String: String] = [:],
        achievedGoals: [CoachGoal] = [],
        fuelBlock: String? = nil,
        mealsBlock: String? = nil
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
                lines.append("\nPRESCRIBED vs ACTUAL (analysed by the app; MISSED = top set short of plan; CLOSE = one rep short, counts as on target):")
                for a in prescribed { lines.append("- " + a.promptLine) }
            }
            if !analysis.skipped.isEmpty { lines.append("SKIPPED (prescribed, not done): " + analysis.skipped.joined(separator: ", ")) }
        }
        if let fuelBlock, !fuelBlock.isEmpty { lines.append("\n" + fuelBlock) }
        if let mealsBlock, !mealsBlock.isEmpty { lines.append("\n" + mealsBlock) }
        if !previousReviews.isEmpty {
            lines.append("\nPREVIOUS REVIEWS (newest first, same workout type):")
            lines.append(contentsOf: previousReviews.map { reviewLine($0) })
        }
        let noteLines = previousNotes.sorted { $0.key < $1.key }.compactMap { entry -> String? in
            clipped(entry.value, SessionAnalyzer.memoryNoteLimit).map { "- \(sanitize(entry.key)): \($0)" }
        }
        if !noteLines.isEmpty {
            lines.append("\nPREVIOUS COACH NOTE (your own, per exercise; rewrite as memory_note):")
            lines.append(contentsOf: noteLines)
        }
        if !achievedGoals.isEmpty {
            lines.append("\nGOAL HIT today: " + achievedGoals.map { "\(sanitize($0.exerciseName)) \($0.targetText)" }.joined(separator: "; ")
                + ". Congratulate the athlete in overall_read.")
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
        return InputSanitizer.clipAtWord(clean, limit: limit)
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

    // MARK: - Plan sections

    /// Everything the plan call gets beyond the history the message already carries.
    struct PlanPromptExtras {
        var focus: CoachFocus = .hypertrophy
        var constraints: String?
        var draft: [DraftExercise] = []
        var estimatedMinutes: Double?
        var reviews: [CoachReviewEntry] = []
        var recency: [String: MuscleRecency] = [:]
        var now: Date = Date()
        /// First line of the message when the workout's muscles were trained hours ago (`RecencyWarning.promptNote`).
        var recencyNote: String?
        /// Per-exercise briefs of the latest same-type session (style, effort, rest actually taken).
        var briefs: [ExerciseBrief] = []
        var muscleLoad: [String: MuscleLoad] = [:]
        var usualMinutes: Int?
        /// The FUEL block from `fuelBlock`; nil when there is no data or sharing is off.
        var fuelBlock: String?
        /// The PRE-WORKOUT MEALS block from `mealsBlock`; nil when there are no meals or sharing is off.
        var mealsBlock: String?
        /// The coach's past calls and notes; rendered as COACH MEMORY for the draft's exercises.
        var memory: CoachMemoryIndex = CoachMemoryIndex()
        /// Lifts outside the draft whose memory is still worth showing (goal lifts, lifts of this workout type).
        var memoryLifts: [CoachLiftRef] = []
        /// ACTIVE GOALS block from `goalsBlock`.
        var goalsBlock: String?
    }

    static func focusText(_ focus: CoachFocus) -> String {
        switch focus {
        case .hypertrophy: return "hypertrophy (top sets 6-10 reps, RIR 1-2)"
        case .strength: return "strength (top sets 3-6 reps, longer rest)"
        case .maintenance: return "maintenance (hold loads, keep volume low)"
        }
    }

    /// At most this many exercise names go into the prompt.
    static let libraryLimit = 25

    private func planBlocks(
        _ coach: PlanPromptExtras, latest: Workout?, index: ExerciseHistoryIndex, workoutType: String,
        exerciseLibrary: [String], rollingSummary: String?, sessions: [Workout], exercises: [UUID: [Exercise]],
        logged: [UUID: [WorkoutSet]]
    ) -> [String] {
        var out: [String] = []
        let latestDoc = latest.flatMap { CoachReviewDocument.parse($0.aiProgressionNote) }

        // The draft: one block per lift.
        if coach.draft.isEmpty {
            out.append("DRAFT PLAN: none (no log for this workout type yet). Build the plan yourself: every lift is an add with starting_sets.")
            if let latest, let list = exercises[latest.id], !list.isEmpty {
                var lines = ["LAST SESSION [\(DateFormatter.shortDate.string(from: latest.date))] \(sanitize(latest.workoutType)) (weight lb x reps @RIR):"]
                for ex in list {
                    let sets = (logged[ex.id] ?? []).sorted { $0.setNumber < $1.setNumber }
                    guard !sets.isEmpty else { continue }
                    let text = ex.trackingType == .cardio ? sets.map { formatCardioSet($0) } : sets.map { formatLoggedSet($0) }
                    var line = "- \(ex.name)\(Self.perArmTag(ex)): " + text.joined(separator: ", ")
                    if let cue = clipped(ex.coachNoteParts.message, 100) { line += " | note: \(cue)" }
                    lines.append(line)
                }
                out.append(lines.joined(separator: "\n"))
            }
        } else {
            var lines = ["DRAFT PLAN (the app's numbers are final for every lift with history\(coach.estimatedMinutes.map { "; about \(Int($0.rounded())) min" } ?? "")):"]
            for (i, d) in coach.draft.enumerated() {
                lines.append(contentsOf: liftBlock(i + 1, d, coach: coach, index: index, latestDoc: latestDoc))
            }
            out.append(lines.joined(separator: "\n"))
        }
        if let note = clipped(latest?.userNote, 200) { out.append("Athlete note after the last session: \(note)") }

        // Session level.
        if let muscles = musclesBlock(coach) { out.append(muscles) }
        if let fuel = coach.fuelBlock, !fuel.isEmpty { out.append(fuel) }
        if let meals = coach.mealsBlock, !meals.isEmpty { out.append(meals) }
        if let goals = coach.goalsBlock, !goals.isEmpty { out.append(goals) }
        if let memory = memoryBlock(coach.memory, draft: coach.draft, extra: coach.memoryLifts) { out.append(memory) }

        // Reviews of this workout type: the latest in detail, the one before in a line. The rolling summary is
        // background that only matters when there are no reviews.
        if let newest = coach.reviews.first {
            var review = "PREVIOUS REVIEWS (your own, newest first):\n" + reviewLine(newest)
            if coach.reviews.count > 1 { review += "\n" + reviewOneLine(coach.reviews[1]) }
            out.append(review)
        } else if let summary = rollingSummary, !summary.isEmpty {
            out.append("ROLLING CONTEXT (recent history summary):\n\(summary)")
        }

        if let names = libraryBlock(exerciseLibrary, coach: coach, workoutType: workoutType, sessions: sessions, exercises: exercises) {
            out.append(names)
        }
        return out
    }

    /// One lift: the draft's sets and why, last session planned vs did, the recent top sets, style and effort, memory.
    private func liftBlock(_ number: Int, _ d: DraftExercise, coach: PlanPromptExtras, index: ExerciseHistoryIndex,
                           latestDoc: CoachReviewDocument?) -> [String] {
        var lines: [String] = []
        let sets = d.result.sets.map { "\($0.role.label.lowercased()) \(String(format: "%g", $0.weight))x\($0.reps)@\($0.rir)" }
        let rests = d.result.sets.map { String($0.restSeconds) }.joined(separator: "/")
        lines.append("\(number). \(sanitize(d.name))\(d.isPerArm ? " (per arm)" : "") (\(d.muscleGroup)): " + sets.joined(separator: ", ") + " | rest \(rests) s")
        // The action part of the engine's line; the "Last: ..." half is shown below once.
        var why = d.result.evidenceLine
        if let arrow = why.range(of: " → ") { why = String(why[arrow.upperBound...]) }
        if !why.isEmpty { lines.append("   why: \(why)") }

        let group = index.group(for: d.name)
        if let last = group?.sessions.first {
            var line = "   last \(Self.trendDate.string(from: last.date)): "
            if let planned = latestDoc?.prescription(for: d.name) {
                line += "planned " + planned.sets.map(\.text).joined(separator: ", ") + "; "
            }
            line += "did " + last.sets.map { "\(String(format: "%g", $0.weight))x\($0.reps)" + ($0.rir.map { "@\($0)" } ?? "") }.joined(separator: ", ")
            lines.append(line)
        }
        var facts: [String] = []
        if let group, group.sessions.count >= 2 {
            let tops = group.sessions.prefix(4).reversed().compactMap { session -> String? in
                guard let top = ProgressionEngine.referenceTop(SetStyleDetector.splitWarmups(session.sets).working) else { return nil }
                return "\(Self.trendDate.string(from: session.date)) \(String(format: "%g", top.weight))x\(top.reps)"
            }
            if tops.count >= 2 { facts.append("tops " + tops.joined(separator: " · ")) }
        }
        if let brief = coach.briefs.first(where: { ExerciseNameResolver.isMatch($0.name, d.name) }) {
            let reps = brief.repLow == brief.repHigh ? "\(brief.repLow)" : "\(brief.repLow)-\(brief.repHigh)"
            facts.append("\(brief.style.label) (\(reps))")
            if let avg = brief.avgRIR { facts.append("avg RIR \(String(format: "%g", (avg * 10).rounded() / 10))") }
            if !brief.e1RMTrend.isEmpty { facts.append("e1RM " + brief.e1RMTrend.map(String.init).joined(separator: ">")) }
            if let rest = Self.restText(brief.rest) { facts.append(rest) }
        }
        if let best = group?.best { facts.append("best \(String(format: "%g", best.weight))x\(best.reps)") }
        if !facts.isEmpty { lines.append("   " + facts.joined(separator: ", ")) }

        let memory = coach.memory.memory(for: d.name, muscle: d.muscleGroup, limit: 3)
        if !memory.lines.isEmpty {
            lines.append("   memory: " + memory.lines.reversed().enumerated().map { memoryEntry($1, withReason: $0 == memory.lines.count - 1) }.joined(separator: " | "))
        }
        if let note = clipped(memory.note, SessionAnalyzer.memoryNoteLimit) { lines.append("   note: \(note)") }
        return lines
    }

    /// Muscles of the draft: hard sets this week against the weekly average, days since, and which were trained recently.
    private func musclesBlock(_ coach: PlanPromptExtras) -> String? {
        var lines: [String] = []
        var muscles: [String] = []
        for brief in coach.briefs {
            for muscle in brief.muscles where !muscles.contains(muscle) { muscles.append(muscle) }
        }
        let loadParts = muscles.prefix(8).compactMap { muscle -> String? in
            guard let load = coach.muscleLoad[muscle] else { return nil }
            let days = load.daysSince.map { "\($0)d" } ?? "28d+"
            return "\(sanitize(muscle)) \(Self.setCount(load.thisWeekSets))/\(Self.setCount(load.avgPrior3WeeksSets)) \(days)"
        }
        if !loadParts.isEmpty {
            lines.append("MUSCLE LOAD (hard sets this wk / weekly avg prior 3 wks, days since): " + loadParts.joined(separator: " · "))
        }
        let recent = coach.recency.filter { $0.value.hoursSince(coach.now) <= 3 * 24 }
            .sorted { $0.value.lastTrained > $1.value.lastTrained }
        if !recent.isEmpty {
            let parts = recent.map { muscle, r -> String in
                let hours = r.hoursSince(coach.now)
                let ago = hours < 48 ? "\(Int(hours.rounded())) h" : String(format: "%.1f d", hours / 24)
                return "\(muscle) \(ago) ago (\(r.hardSets) hard sets)"
            }
            lines.append("TRAINED RECENTLY (all workout types): " + parts.joined(separator: ", "))
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// Names the athlete already uses for lifts that share a muscle with today's workout, most used first.
    private func libraryBlock(_ names: [String], coach: PlanPromptExtras, workoutType: String, sessions: [Workout],
                              exercises: [UUID: [Exercise]]) -> String? {
        var muscles = Set(coach.draft.map { MuscleGroups.canonical(forExercise: $0.name, muscleGroup: $0.muscleGroup) })
        if muscles.isEmpty, let latest = sessions.first {
            muscles = Set((exercises[latest.id] ?? []).map { MuscleGroups.canonical(forExercise: $0.name, muscleGroup: $0.muscleGroup) })
        }
        muscles.formUnion(Self.muscles(forWorkoutType: workoutType))
        let inDraft = Set(coach.draft.map { $0.name.lowercased() })
        let relevant = names.map { sanitize($0) }.filter { name in
            guard !name.isEmpty, !inDraft.contains(name.lowercased()) else { return false }
            return muscles.isEmpty || muscles.contains(MuscleGroups.canonical(forExercise: name, muscleGroup: ""))
        }.prefix(Self.libraryLimit)
        guard !relevant.isEmpty else { return nil }
        return "ATHLETE'S EXERCISE NAMES (for new lifts only, most used first; reuse verbatim for the same movement):\n"
            + relevant.joined(separator: "; ")
    }

    /// The muscles a workout type usually trains (canonical names); empty when the type is not recognised.
    static func muscles(forWorkoutType type: String) -> Set<String> {
        let t = type.lowercased()
        var result = Set<String>()
        if t.contains("push") { result.formUnion(["chest", "shoulders", "triceps"]) }
        if t.contains("pull") { result.formUnion(["back", "biceps", "rear delts"]) }
        if t.contains("leg") || t.contains("lower") { result.formUnion(["quads", "hamstrings", "glutes", "calves", "legs"]) }
        if t.contains("upper") { result.formUnion(["chest", "back", "shoulders", "biceps", "triceps", "rear delts"]) }
        if t.contains("chest") { result.insert("chest") }
        if t.contains("back") { result.insert("back") }
        if t.contains("arm") { result.formUnion(["biceps", "triceps"]) }
        if t.contains("shoulder") { result.insert("shoulders") }
        return result
    }

    // MARK: - Goals

    /// ACTIVE GOALS: one line per goal with the app's e1RM numbers and today's step; nil with no goals.
    func goalsBlock(_ items: [GoalPlanItem], now: Date = Date()) -> String? {
        let shown = items.prefix(GoalPlanner.maxGoalsInPrompt)
        guard !shown.isEmpty else { return nil }
        var lines: [String] = []
        for item in shown {
            let goal = item.goal
            var line = "\(sanitize(goal.exerciseName)) \(goal.targetText)"
            if let deadline = goal.deadline { line += " by \(Self.goalDate.string(from: deadline))" }
            if let a = item.assessment {
                line += " (now ~\(String(format: "%.0f", a.currentE1RM)) e1RM, goal needs ~\(String(format: "%.0f", a.targetE1RM)))"
            } else {
                line += " (no logged history)"
            }
            line += "."
            if let step = item.step {
                var text = clipped(step.text, 140) ?? ""
                if text.isEmpty, let w = step.weight, let r = step.reps { text = "\(String(format: "%g", w))x\(r)" }
                if !text.isEmpty {
                    let label = item.stepIsToday ? "Today's step" : "Next step"
                    let when = item.stepIsToday ? "" : (CoachGoal.parseDay(step.date).map { " (\(Self.goalDate.string(from: $0)))" } ?? "")
                    line += " \(label)\(when): \(text)"
                    if !text.hasSuffix(".") { line += "." }
                }
            }
            if item.attemptToday, let a = item.assessment {
                line += " Attempt day: warm-up ladder " + a.ladder.map(\.text).joined(separator: ", ")
                    + " (the last is the attempt; the rails allow up to \(String(format: "%g", goal.targetWeight)))."
            }
            lines.append("- " + line)
        }
        return "ACTIVE GOALS:\n" + lines.joined(separator: "\n") + "\nBuild toward them within the rails."
    }

    private static let goalDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM/dd"
        return f
    }()

    // MARK: - Memory

    /// COACH MEMORY for lifts that are NOT in the draft (goal lifts, other lifts of this workout type): the draft's own
    /// lifts carry their memory inside their blocks. nil when nothing is left.
    func memoryBlock(_ memory: CoachMemoryIndex, draft: [DraftExercise], extra: [CoachLiftRef] = [],
                     limit: Int = 3, maxLifts: Int = 6) -> String? {
        guard !memory.isEmpty else { return nil }
        var lines: [String] = []
        var shown = 0
        var seen: [(String, Date)] = []
        for lift in extra where !draft.contains(where: { ExerciseNameResolver.isMatch($0.name, lift.name) }) {
            if shown >= maxLifts { break }
            let m = memory.memory(for: lift.name, muscle: lift.muscle, limit: limit)
            guard !m.lines.isEmpty || m.note != nil else { continue }
            shown += 1
            let name = sanitize(lift.name)
            if !m.lines.isEmpty {
                lines.append("- \(name): " + m.lines.reversed().enumerated().map { memoryEntry($1, withReason: $0 == m.lines.count - 1) }.joined(separator: " | "))
                for l in m.lines { seen.append((l.decision.name, l.date)) }
            } else {
                lines.append("- \(name):")
            }
            if let note = clipped(m.note, SessionAnalyzer.memoryNoteLimit) { lines.append("  note: \(note)") }
            // Same-muscle lifts, unless that call is already shown above or belongs to a lift in the draft.
            for related in m.related
            where !draft.contains(where: { ExerciseNameResolver.isMatch($0.name, related.decision.name) })
                && !seen.contains(where: { ExerciseNameResolver.isMatch($0.0, related.decision.name) && $0.1 == related.date }) {
                seen.append((related.decision.name, related.date))
                lines.append("- \(sanitize(related.decision.name)) (same muscle, other lift): " + memoryEntry(related, withReason: true))
            }
        }
        guard !lines.isEmpty else { return nil }
        return "COACH MEMORY, other lifts (your past calls -> what happened):\n" + lines.joined(separator: "\n")
    }

    /// `10/28 210x5@1 -> 210x4@0 MISS`, with the coach's reason in quotes when asked: `... "e1RM up, +5"`.
    private func memoryEntry(_ line: CoachMemoryLine, withReason: Bool) -> String {
        let d = line.decision
        var text = "\(Self.trendDate.string(from: line.date)) \(d.target.text)"
        if let move = d.move, move != CoachMove.asPlanned.rawValue { text += " [\(move)]" }
        if withReason, let reason = clipped(d.reason, 100) { text += " \"\(reason)\"" }
        if let outcome = d.outcome {
            let verdict = outcome.result == .close ? "CLOSE (on target)" : (outcome.hit ? "HIT" : "MISS")
            text += " -> \(outcome.actualTop) \(verdict)"
        }
        return text
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

    // MARK: - Fuel

    /// The compact FUEL block (about 60-90 tokens, under 400 characters); nil with nothing to say.
    /// ```
    /// FUEL: data good (6/7 days logged)
    /// Today by 8:10am: 450/2400 kcal, P35/180 so far (day not over); Carbs last 24h: 180 g
    /// 7d avg of logged days: 2150/2400 kcal, P150/180 C220 F70; on target 4/6 days
    /// Weight: -0.6 lb/wk (14d), -0.4 lb/wk (30d); goal lose 0.5 lb/wk
    /// Yesterday: 2450/2600 kcal, P150/180
    /// ```
    func fuelBlock(_ fuel: CoachFuelSummary?) -> String? {
        guard let fuel else { return nil }
        func n(_ value: Double) -> String { String(format: "%.0f", value) }
        func pair(_ value: Double, _ target: Double?) -> String { target.map { "\(n(value))/\(n($0))" } ?? n(value) }
        var lines: [String] = []

        if let week = fuel.last7 {
            let head = "FUEL: data \(fuel.dataQuality.rawValue) (\(week.loggedDays)/7 days logged)"
            lines.append(fuel.dataQuality == .unreliable ? head + ": ignore the intake numbers." : head)
        } else {
            lines.append(fuel.dataQuality == .unreliable ? "FUEL: data unreliable (0/7 days logged): ignore the intake numbers." : "FUEL:")
        }
        if let today = fuel.today {
            var line: String
            if today.hasEntries {
                line = "Today by \(today.timeLabel): \(pair(today.kcalSoFar, today.targetKcal)) kcal, "
                    + "P\(pair(today.proteinSoFar, today.targetProteinG)) so far (day not over)"
            } else {
                line = "Today by \(today.timeLabel): nothing logged yet (day not over)"
            }
            if let carbs = fuel.carbsLast24h { line += "; Carbs last 24h: \(n(carbs)) g" }
            lines.append(line)
        }
        if let week = fuel.last7 {
            var line = "7d avg of logged days: \(pair(week.avgKcal, week.avgTargetKcal)) kcal, "
                + "P\(pair(week.avgProtein, week.avgTargetProtein)) C\(n(week.avgCarbs)) F\(n(week.avgFat))"
            if week.daysWithTarget > 0 { line += "; on target \(week.daysOnTarget)/\(week.daysWithTarget) days" }
            lines.append(line)
        }
        var weight: [String] = []
        if let t = fuel.weightTrend14 { weight.append(String(format: "%+.1f lb/wk (14d)", t)) }
        if let t = fuel.weightTrend30 { weight.append(String(format: "%+.1f lb/wk (30d)", t)) }
        var goalText: String?
        if let goal = fuel.goal, !goal.isEmpty {
            goalText = "goal \(goal)"
            if let rate = fuel.weeklyRate, rate > 0, goal != "maintain" { goalText = (goalText ?? "") + " \(String(format: "%g", rate)) lb/wk" }
        }
        if !weight.isEmpty {
            lines.append("Weight: " + weight.joined(separator: ", ") + (goalText.map { "; " + $0 } ?? ""))
        } else if let goalText {
            lines.append("Goal: " + goalText.replacingOccurrences(of: "goal ", with: ""))
        }
        if let kcal = fuel.yesterdayKcal {
            var line = "Yesterday: \(pair(kcal, fuel.targetKcal)) kcal"
            if let protein = fuel.proteinG { line += ", P\(pair(protein, fuel.targetProteinG))" }
            lines.append(line)
        }
        return lines.count > 1 ? lines.joined(separator: "\n") : nil
    }

    /// The PRE-WORKOUT MEALS block (about 25 tokens per meal); nil with no meals.
    /// ```
    /// PRE-WORKOUT MEALS (newest first):
    /// - 2.0h before: burger, fries (+1 more) — 1100 kcal P40 C95 F60
    /// ```
    func mealsBlock(_ meals: PreWorkoutMeals?) -> String? {
        guard let meals, !meals.meals.isEmpty else { return nil }
        var lines = ["PRE-WORKOUT MEALS (newest first):"]
        for meal in meals.meals {
            var names = meal.foods.map { sanitize($0) }.filter { !$0.isEmpty }.map { String($0.prefix(24)) }
            if names.isEmpty { names = ["food"] }
            var foods = names.joined(separator: ", ")
            if meal.moreCount > 0 { foods += " (+\(meal.moreCount) more)" }
            lines.append("- \(String(format: "%.1f", meal.hoursBefore))h before: \(foods) — \(String(format: "%.0f", meal.kcal)) kcal "
                + "P\(String(format: "%.0f", meal.protein)) C\(String(format: "%.0f", meal.carbs)) F\(String(format: "%.0f", meal.fat))")
        }
        return lines.joined(separator: "\n")
    }

    /// One line for an older review: date, type and the overall read.
    private func reviewOneLine(_ entry: CoachReviewEntry) -> String {
        let date = Self.trendDate.string(from: entry.date)
        let read = entry.document.review.flatMap { clipped($0.overallRead, 120) } ?? "(no review)"
        return "[\(date)] \(sanitize(entry.workoutType)): \(read)"
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
