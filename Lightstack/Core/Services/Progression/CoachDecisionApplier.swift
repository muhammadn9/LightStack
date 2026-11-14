import Foundation

/// Everything the decision applier and the checks need besides the coach's reply.
struct PlanDecisionContext {
    var workoutId: UUID
    var draft: [DraftExercise]
    var history: ExerciseHistoryIndex
    var coach: PlanCoachContext
    var energy: Int
    var feedback: SessionFeedback? = nil
    /// Minutes available today.
    var timeMinutes: Int
    var goalItems: [GoalPlanItem] = []
    /// The coach's past calls and how they went (a lift whose last outcome was a miss may not be pushed).
    var memory: CoachMemoryIndex = CoachMemoryIndex()
    var canonicalName: (String) -> ExerciseNameResolver.Canonical = { ExerciseNameResolver.canonicalName(for: $0, existing: []) }
    var sanitizeLabel: (String) -> String = { InputSanitizer.sanitizeLabel($0) }
}

/// One lift of the plan while it is being assembled and checked.
struct PlanLift {
    var exercise: Exercise
    var targets: [SetTarget]
    /// The engine's draft for the lift; nil for a lift with no history.
    var draft: DraftExercise?
    var decision: LiftDecision
    var cue: String?
    var superset: String?
    /// The engine's "Last: 185×5@1 → hold 185×5" line; "" for a lift with no history.
    var evidenceLine: String
    /// The engine's longer text (shown under the targets).
    var rationale: String
    var hasHistory: Bool { draft != nil }

    var top: SetTarget? {
        targets.first { $0.resolvedRole == .top && $0.isWarmup != true } ?? targets.last { $0.isWarmup != true }
    }
    var workingCount: Int { targets.filter { $0.isWarmup != true }.count }
}

/// The plan after the coach's decisions were applied and the checks ran.
struct AppliedPlan {
    var exercises: [Exercise]
    var setTargets: [UUID: [SetTarget]]
    /// Keyed by exercise id, one entry per exercise in the plan.
    var evidence: [UUID: ExerciseEvidence]
    /// Human-readable list of what the app did (for the debug screen).
    var adjustments: [String]
    var review: CoachPlanReview
    /// Per exercise: the label and the reason shown.
    var reasons: [CoachExerciseReason]
    /// Set when the workout's primary muscles were trained hard hours ago.
    var recencyWarning: RecencyWarning?
}

/// "The coach decides, the engine sets the numbers."
///
/// The coach's reply is one decision per lift. For a lift with history the numbers always come from `ProgressionEngine`:
/// `as_planned` is the draft, `push` / `goal_step` ask the engine for one more step, `ease` asks it to build around a
/// lighter top set. A decision the rules forbid is downgraded to `as_planned` and says why. Lifts with no history use
/// the coach's starting sets when they pass a conservative check, else a default. `PlanChecks` then runs over the
/// whole plan and repairs anything that fails.
enum CoachDecisionApplier {

    static let easeRange: ClosedRange<Double> = 2.5...15
    static let defaultEasePercent = 5.0
    /// A starting set may be at most this much heavier than the athlete's top weight on a similar lift.
    static let similarLiftTolerance = 1.3

    // MARK: - Entry point

    /// - Parameter reply: the coach's reply; nil when the AI call failed or its reply was unusable (the plan is then
    ///   the engine's draft, labelled as such).
    static func apply(reply: CoachPlanReply?, context ctx: PlanDecisionContext) -> AppliedPlan {
        var adjustments: [String] = []
        var priorNotes: [String: [String]] = [:]
        var consumed = Set<Int>()           // indexes of draft lifts that have a lift in the plan
        var replaced = Set<Int>()           // draft lifts swapped out
        var lifts: [PlanLift] = []
        var dropped: [LiftDecision] = []

        // 1. The coach's list, in its order.
        for entry in reply?.entries ?? [] {
            let raw = ctx.sanitizeLabel(entry.name)
            guard !raw.isEmpty else { continue }
            // The athlete's own spelling of the lift ("Bench Press" for "Barbell Bench Press") when they have one.
            let name = ctx.canonicalName(raw).name
            if let index = ctx.draft.indices.first(where: { !consumed.contains($0) && ExerciseNameResolver.isMatch(ctx.draft[$0].name, name) }) {
                consumed.insert(index)
                var lift = draftLift(ctx.draft[index], entry: entry, ctx: ctx, adjustments: &adjustments, priorNotes: &priorNotes)
                lift.superset = entry.superset
                lifts.append(lift)
                continue
            }
            // A name that is not in the draft.
            if lifts.contains(where: { ExerciseNameResolver.isMatch($0.exercise.name, name) }) { continue }
            let replacesIndex = (entry.move == .swap ? entry.replaces : nil).flatMap { target in
                ctx.draft.indices.first { !consumed.contains($0) && ExerciseNameResolver.isMatch(ctx.draft[$0].name, target) }
            }
            if let replacesIndex { consumed.insert(replacesIndex); replaced.insert(replacesIndex) }
            var lift = newLift(entry: entry, name: raw, replacing: replacesIndex.map { ctx.draft[$0] }, ctx: ctx,
                               firstHeavy: !lifts.contains { $0.draft?.allowedWarmups == true || $0.targets.contains { $0.isWarmup == true } },
                               adjustments: &adjustments)
            lift.superset = entry.superset
            lifts.append(lift)
        }

        // 2. Lifts the coach dropped on purpose.
        for drop in reply?.dropped ?? [] {
            guard let index = ctx.draft.indices.first(where: { !consumed.contains($0) && ExerciseNameResolver.isMatch(ctx.draft[$0].name, drop.name) })
            else { continue }
            consumed.insert(index)
            let d = ctx.draft[index]
            let reason = drop.reason.map { InputSanitizer.sanitizeSentence($0, limit: 200) } ?? ""
            dropped.append(LiftDecision(name: d.name, move: .drop, reason: reason, draftTop: topText(d.result.topSet), finalTop: nil))
            adjustments.append("\(d.name): dropped by the coach (\(reason))")
        }

        // 3. Draft lifts the coach neither listed nor dropped stay as planned, next to their old neighbour.
        for index in ctx.draft.indices where !consumed.contains(index) {
            let lift = draftLift(ctx.draft[index], entry: nil, ctx: ctx, adjustments: &adjustments, priorNotes: &priorNotes)
            var position = 0
            if let previous = ctx.draft[..<index].lastIndex(where: { prior in
                lifts.contains { ExerciseNameResolver.isMatch($0.exercise.name, prior.name) }
            }), let at = lifts.firstIndex(where: { ExerciseNameResolver.isMatch($0.exercise.name, ctx.draft[previous].name) }) {
                position = at + 1
            }
            lifts.insert(lift, at: min(position, lifts.count))
        }

        // 4. Heavy compounds first (unless supersets pin the order).
        var safeguards: [String] = []
        let ordered = lifts.map(\.exercise)
        if lifts.allSatisfy({ $0.superset == nil }), let moved = PlanDraftBuilder.heavyFirst(ordered) {
            let order = moved.exercises.map(\.id)
            lifts.sort { (order.firstIndex(of: $0.exercise.id) ?? 0) < (order.firstIndex(of: $1.exercise.id) ?? 0) }
            safeguards.append("Moved \(moved.names.joined(separator: ", ")) ahead of lighter work (heavy compounds go first)")
        }

        // 5. The checks run over the finished plan and repair what fails.
        let checks = PlanChecks.run(&lifts, context: ctx, priorNotes: priorNotes, adjustments: &adjustments)

        // 6. Assemble.
        var exercises = lifts.map(\.exercise)
        let groupIds = SupersetGroup.groupIds(forLabels: lifts.map(\.superset))
        for i in exercises.indices { exercises[i].supersetGroupId = groupIds[i] }
        for i in exercises.indices { exercises[i].orderIndex = i }
        exercises = SupersetGroup.normalized(exercises)
        var byId: [UUID: PlanLift] = [:]
        for lift in lifts { byId[lift.exercise.id] = lift }
        let finalLifts = exercises.compactMap { byId[$0.id] }
        for i in exercises.indices { exercises[i].targetSets = finalLifts[i].targets.count }

        var targets: [UUID: [SetTarget]] = [:]
        var evidence: [UUID: ExerciseEvidence] = [:]
        var reasons: [CoachExerciseReason] = []
        for (i, lift) in finalLifts.enumerated() {
            let ex = exercises[i]
            targets[ex.id] = lift.targets
            let group = ctx.history.group(for: ex.name)
            evidence[ex.id] = Self.evidence(for: lift, group: group, adjustments: adjustmentsFor(lift.exercise.name, in: checks))
            reasons.append(CoachExerciseReason(exercise: ex.name, label: lift.decision.label, text: lift.decision.reason))
            exercises[i] = refreshedNote(ex, lift: lift)
        }

        let engineOnly = reply == nil
        let warning = ctx.coach.recencyWarning(forLifts: finalLifts.map { ($0.exercise.name, $0.exercise.muscleGroup) })
        let summary: String
        if engineOnly {
            summary = "The coach was unavailable, so this plan comes straight from your log."
        } else {
            summary = reply?.summary ?? ""
        }
        let review = CoachPlanReview(
            summary: summary, notes: reply?.notes, decisions: finalLifts.map(\.decision) + dropped, checks: checks,
            recencyMessage: warning?.athleteText, engineOnly: engineOnly)
        for line in safeguards { adjustments.append(line) }
        return AppliedPlan(exercises: exercises, setTargets: targets, evidence: evidence, adjustments: adjustments,
                           review: review, reasons: reasons, recencyWarning: warning)
    }

    // MARK: - A draft lift

    private enum Outcome {
        case applied(ProgressionResult, percent: Double?)
        case held(String)
    }

    private static func draftLift(
        _ draft: DraftExercise, entry: CoachReplyEntry?, ctx: PlanDecisionContext,
        adjustments: inout [String], priorNotes: inout [String: [String]]
    ) -> PlanLift {
        var move = entry?.move ?? .asPlanned
        // "add" or "swap" naming a lift that is already in the draft just means keep it.
        if move == .add || move == .swap || move == .drop { move = .asPlanned }
        var result = draft.result
        var applied = CoachMove.asPlanned
        var held: String?
        var percent: Double?
        switch move {
        case .push, .goalStep, .ease:
            let outcome: Outcome
            switch move {
            case .push: outcome = push(draft, ctx: ctx)
            case .goalStep: outcome = goalStep(draft, ctx: ctx)
            default: outcome = ease(draft, percent: entry?.percent, ctx: ctx)
            }
            switch outcome {
            case .applied(let rebuilt, let p):
                result = rebuilt
                applied = move
                percent = p
            case .held(let why):
                held = why
                let note = "Held the coach's \(move.verb) on \(draft.name): \(why)"
                adjustments.append(note)
                priorNotes[PlanChecks.noProgressID, default: []].append(note)
            }
        default:
            break
        }
        var targets = result.sets.map(\.setTarget)
        if let wanted = entry?.sets {
            targets = setCount(targets, wanted: wanted, isolation: ExerciseTraits.classify(draft.name) == .isolation)
        }
        let top = result.topSet
        let decision = LiftDecision(
            name: draft.name, move: applied, requested: held == nil ? nil : move, percent: percent, replaces: nil, held: held,
            reason: entry?.reason.map { InputSanitizer.sanitizeSentence($0, limit: 200) } ?? "",
            draftTop: topText(draft.result.topSet), finalTop: topText(top))
        let exercise = Exercise.create(
            workoutId: ctx.workoutId, name: draft.name, muscleGroup: draft.muscleGroup, orderIndex: 0, targetSets: targets.count,
            targetReps: top.map { String($0.reps) }, targetRir: top.map { String($0.rir) }, restSeconds: top?.restSeconds,
            coachNote: nil, isPerArm: draft.isPerArm ? true : nil)
        return PlanLift(exercise: exercise, targets: targets, draft: draft, decision: decision,
                        cue: entry?.cue.map { InputSanitizer.sanitizeSentence($0, limit: 160) },
                        superset: nil, evidenceLine: result.evidenceLine, rationale: result.rationale)
    }

    // MARK: - Gate

    /// Why a lift may not progress today, in words for the athlete; nil when it is free to. The same rules back
    /// `PlanChecks`' "no progress" check.
    static func gateReason(for draft: DraftExercise, ctx: PlanDecisionContext) -> String? {
        let muscle = MuscleGroups.canonical(forExercise: draft.name, muscleGroup: draft.muscleGroup)
        if ctx.coach.isVeryRecent(muscle: muscle), let r = ctx.coach.recency[muscle] {
            return "you trained \(RecencyWarning.displayLabel(for: muscle)) \(RecencyWarning.hoursPhrase(r.hoursSince(ctx.coach.now))) ago"
        }
        if let why = draft.result.noProgressReason {
            if why.hasPrefix("trained") { return "you did this lift " + why.dropFirst("trained ".count) }
            if why.hasPrefix("low fuel") { return why }
            return why
        }
        if ctx.coach.fuelHold?.isLow == true { return "fuel is low: " + (ctx.coach.fuelHold?.primaryReason ?? "eating under target") }
        if let group = ctx.history.group(for: draft.name), let last = group.sessions.first {
            let days = max(0, Int(ctx.coach.now.timeIntervalSince(last.date) / 86_400))
            if days > ProgressionEngine.holdAfterDays { return "last done \(days) days ago" }
        }
        if let outcome = ctx.memory.lastOutcome(for: draft.name), outcome.result == .missed { return "the last session missed this lift" }
        return nil
    }

    // MARK: - Moves

    private static func rebuild(_ draft: DraftExercise, top: TopOverride) -> ProgressionResult? {
        guard var input = draft.input else { return nil }
        input.topOverride = top
        return ProgressionEngine.plan(input)
    }

    private static func lastTop(of group: ExerciseHistoryGroup?) -> HistorySet? {
        group?.sessions.first.flatMap { ProgressionEngine.referenceTop(SetStyleDetector.splitWarmups($0.sets).working) }
    }

    private static func g(_ value: Double) -> String { String(format: "%g", value) }

    private static func push(_ draft: DraftExercise, ctx: PlanDecisionContext) -> Outcome {
        guard let input = draft.input, let draftTop = draft.result.topSet, let group = ctx.history.group(for: draft.name) else {
            return .held("there is no log to build on")
        }
        if let why = gateReason(for: draft, ctx: ctx) { return .held(why) }
        let base = HistorySet(draftTop.weight, draftTop.reps, rir: draftTop.rir)
        let ladder = input.increments ?? WeightIncrements.learned(name: draft.name, group: group)
        let next = ProgressionEngine.nextTopTarget(
            name: draft.name, after: base, focus: ctx.coach.focus, best: group.capBest, history: group.sessions, increments: ladder)
        guard next.weight > base.weight + 0.001 || (abs(next.weight - base.weight) <= 0.001 && next.reps > base.reps) else {
            return .held("today's target is already the next step")
        }
        return stepTo(draft, weight: next.weight, reps: next.reps, text: "coach push to \(g(next.weight))×\(next.reps)", ctx: ctx)
    }

    private static func goalStep(_ draft: DraftExercise, ctx: PlanDecisionContext) -> Outcome {
        guard let group = ctx.history.group(for: draft.name), let draftTop = draft.result.topSet else {
            return .held("there is no log to build on")
        }
        guard let item = ctx.goalItems.first(where: { ExerciseNameResolver.isMatch($0.goal.exerciseName, draft.name) && $0.stepIsToday }),
              let step = item.step, let stepWeight = step.weight, let stepReps = step.reps, stepWeight > 0, stepReps > 0 else {
            return .held("no goal step is due for this lift today")
        }
        if let why = gateReason(for: draft, ctx: ctx) { return .held(why) }
        let ladder = draft.input?.increments ?? WeightIncrements.learned(name: draft.name, group: group)
        let weight = ladder.snap(stepWeight, direction: .down)
        // Not above what the draft already asks: nothing to add.
        if weight < draftTop.weight - 0.001 || (abs(weight - draftTop.weight) <= 0.001 && stepReps <= draftTop.reps) {
            return .applied(draft.result, percent: nil)
        }
        return stepTo(draft, weight: weight, reps: stepReps, text: "goal step \(g(weight))×\(stepReps)", ctx: ctx)
    }

    /// Checks a higher top set against the rails and, when it passes, has the engine build the lift around it.
    private static func stepTo(_ draft: DraftExercise, weight: Double, reps: Int, text: String, ctx: PlanDecisionContext) -> Outcome {
        guard let draftTop = draft.result.topSet, let group = ctx.history.group(for: draft.name) else { return .held("there is no log to build on") }
        let last = lastTop(of: group)
        let days = group.sessions.first.map { max(0, Int(ctx.coach.now.timeIntervalSince($0.date) / 86_400)) }
        let allowance = ctx.coach.goalAllowance(for: draft.name)
        let rail = PlanGuardrails.RailContext(
            name: draft.name, cls: ExerciseTraits.classify(draft.name), focus: ctx.coach.focus, lastTop: last, daysSinceLast: days,
            capBestE1RM: group.capBest?.e1RM, prWeight: group.best?.weight, goalAllowance: allowance?.weight,
            goalReps: allowance?.reps ?? 1, ladder: draft.input?.increments, lastWork: [])
        if let limit = PlanGuardrails.coachTopLimit(rail), weight > limit.limit + 0.001 {
            return .held("\(g(weight)) is more than the limit of \(g(limit.limit)) over the last top set")
        }
        if let best = group.capBest?.e1RM, best > 0 {
            var ceiling = best * (1 + PlanGuardrails.coachE1RMTolerance)
            if let allowance { ceiling = max(ceiling, HistorySet(allowance.weight, max(1, allowance.reps)).e1RM) }
            let e1RM = HistorySet(weight, reps).e1RM
            if e1RM > ceiling + 0.001 {
                return .held("\(g(weight))×\(reps) would estimate a \(g(e1RM.rounded())) one-rep max, over your recent best of \(g(best.rounded()))")
            }
        }
        guard let rebuilt = rebuild(draft, top: TopOverride(weight: weight, reps: reps, text: text)), let newTop = rebuilt.topSet else {
            return .held("the app could not rebuild the lift")
        }
        let progressed = newTop.weight > draftTop.weight + 0.001
            || (abs(newTop.weight - draftTop.weight) <= 0.001 && newTop.reps > draftTop.reps)
        guard progressed else {
            let why = rebuilt.repCaps.first.map { "rep-jump rule: \($0)" } ?? "rep-jump rule"
            return .held(why)
        }
        return .applied(rebuilt, percent: nil)
    }

    private static func ease(_ draft: DraftExercise, percent requested: Double?, ctx: PlanDecisionContext) -> Outcome {
        guard let draftTop = draft.result.topSet, draft.input != nil else { return .held("there is no log to build on") }
        let magnitude = min(easeRange.upperBound, max(easeRange.lowerBound, abs(requested ?? defaultEasePercent)))
        let percent = -magnitude
        let group = ctx.history.group(for: draft.name)
        let ladder = draft.input?.increments ?? WeightIncrements.learned(name: draft.name, group: group)
        let target = draftTop.weight * (1 + percent / 100)
        let down = ladder.snap(target, direction: .down)
        let intended = draftTop.weight - target
        // A lighter rung that is a fair step down.
        if down < draftTop.weight - 0.001, draftTop.weight - down <= 2 * intended + 0.001 {
            if let rebuilt = rebuild(draft, top: TopOverride(weight: down, reps: draftTop.reps, text: "coach eased to \(g(down))×\(draftTop.reps)")) {
                return .applied(rebuilt, percent: percent)
            }
            return .held("the app could not rebuild the lift")
        }
        // The weight cannot come down that little on this lift's weights: fewer reps, else one set fewer.
        let drop = magnitude >= 10 ? 2 : 1
        if draftTop.reps - drop >= 3,
           let rebuilt = rebuild(draft, top: TopOverride(weight: draftTop.weight, reps: draftTop.reps - drop,
                                                         text: "coach eased to \(g(draftTop.weight))×\(draftTop.reps - drop)")) {
            return .applied(rebuilt, percent: percent)
        }
        var shorter = draft.result
        let working = shorter.sets.indices.filter { !shorter.sets[$0].isWarmup }
        if working.count > PlanGuardrails.minWorkingSets,
           let victim = working.last(where: { shorter.sets[$0].role != .top }) {
            shorter.sets.remove(at: victim)
            return .applied(shorter, percent: percent)
        }
        return .held("this lift cannot be lightened by that much")
    }

    // MARK: - Set count

    /// Working sets to `wanted`, clamped: isolation 2...3, main lifts 2...their current count (no heavy sets are added).
    static func setCount(_ targets: [SetTarget], wanted: Int, isolation: Bool) -> [SetTarget] {
        var list = targets
        let working = list.indices.filter { list[$0].isWarmup != true }
        guard !working.isEmpty else { return list }
        let upper = isolation ? 3 : min(working.count, ProgressionEngine.mainWorkingSets)
        let target = min(upper, max(PlanGuardrails.minWorkingSets, wanted))
        guard target != working.count else { return list }
        if target < working.count {
            var toRemove = working.count - target
            while toRemove > 0 {
                let now = list.indices.filter { list[$0].isWarmup != true }
                let firstTop = now.first { list[$0].resolvedRole == .top }
                let victim = now.last { list[$0].resolvedRole == .top && $0 != firstTop }
                    ?? now.last { list[$0].resolvedRole == .ramp }
                    ?? now.last { list[$0].resolvedRole == .backoff }
                    ?? now.last { list[$0].resolvedRole == .straight && $0 != firstTop && now.count > target }
                guard let v = victim else { break }
                list.remove(at: v)
                toRemove -= 1
            }
        } else if let last = working.last {
            var copy = list[last]
            copy.rir = "1"
            list[last].rir = "2"
            list.append(copy)
        }
        return list
    }

    // MARK: - A lift that is not in the draft

    private static func newLift(
        entry: CoachReplyEntry, name rawName: String, replacing replaced: DraftExercise?, ctx: PlanDecisionContext,
        firstHeavy: Bool, adjustments: inout [String]
    ) -> PlanLift {
        let canonical = ctx.canonicalName(rawName)
        let name = canonical.name
        let muscleGroup = entry.muscleGroup ?? replaced?.muscleGroup ?? WorkoutSessionService.inferMuscleGroup(name)
        let cls = ExerciseTraits.classify(name)
        let move: CoachMove = replaced == nil ? .add : .swap
        let reason = entry.reason.map { InputSanitizer.sanitizeSentence($0, limit: 200) } ?? ""
        let cue = entry.cue.map { InputSanitizer.sanitizeSentence($0, limit: 160) }

        var decision = LiftDecision(name: name, move: move, replaces: replaced?.name, reason: reason,
                                    draftTop: nil, finalTop: nil)

        // History: the engine builds the numbers, exactly as for a draft lift.
        if let group = ctx.history.group(for: name) {
            let allowWarmups = replaced?.allowedWarmups ?? (cls == .heavyCompound && firstHeavy)
            let input = PlanDraftBuilder.engineInput(name: name, muscleGroup: muscleGroup, group: group, energy: ctx.energy,
                                                     feedback: ctx.feedback, coach: ctx.coach, allowWarmups: allowWarmups)
            if let result = ProgressionEngine.plan(input) {
                let targets = result.sets.map(\.setTarget)
                let top = result.topSet
                decision.finalTop = topText(top)
                let exercise = Exercise.create(
                    workoutId: ctx.workoutId, name: name, muscleGroup: muscleGroup, orderIndex: 0, targetSets: targets.count,
                    targetReps: top.map { String($0.reps) }, targetRir: top.map { String($0.rir) }, restSeconds: top?.restSeconds,
                    coachNote: nil, isPerArm: canonical.isPerArm ? true : nil)
                adjustments.append("\(name): \(move == .swap ? "swapped in" : "added") with the app's numbers (\(result.rationale))")
                let draft = DraftExercise(name: name, muscleGroup: muscleGroup, result: result, input: input,
                                          isPerArm: canonical.isPerArm, allowedWarmups: allowWarmups)
                var lift = PlanLift(exercise: exercise, targets: targets, draft: draft, decision: decision, cue: cue, superset: nil,
                                    evidenceLine: result.evidenceLine, rationale: result.rationale)
                if let wanted = entry.sets {
                    lift.targets = setCount(lift.targets, wanted: wanted, isolation: cls == .isolation)
                }
                return lift
            }
        }

        // No history: the coach's starting sets when they pass, else the app's default.
        let similar = similarTopWeight(name: name, muscleGroup: muscleGroup, cls: cls, ctx: ctx)
        let allowWarmups = cls == .heavyCompound && firstHeavy
        var notes: [String] = []
        var targets: [SetTarget]
        if let checked = validStartingSets(entry.startingSets, similarTop: similar, notes: &notes) {
            targets = checked
        } else {
            targets = defaultStartingSets(name: name, cls: cls, similarTop: similar, ctx: ctx)
            notes.append("starting sets missing or out of range, so the app's default was used")
        }
        let ladder = WeightIncrements.fallback(for: name)
        let guarded = PlanGuardrails.apply(name: name, targets: targets, allowWarmups: allowWarmups, bestWeight: nil,
                                           workingSetCap: cls == .isolation ? ProgressionEngine.isolationWorkingSets + 1 : 3, ladder: ladder)
        notes += guarded.report.reasons
        targets = PlanGuardrails.withRolesAndRest(guarded.targets, cls: cls, focus: ctx.coach.focus, restPreference: ctx.coach.restPreference)
        if let wanted = entry.sets { targets = setCount(targets, wanted: wanted, isolation: cls == .isolation) }
        let top = targets.first { $0.resolvedRole == .top && $0.isWarmup != true } ?? targets.last { $0.isWarmup != true }
        decision.finalTop = top.map { "\($0.prefillWeight)x\($0.prefillReps)@\($0.prefillRir)" }
        let exercise = Exercise.create(
            workoutId: ctx.workoutId, name: name, muscleGroup: muscleGroup, orderIndex: 0, targetSets: targets.count,
            targetReps: top?.prefillReps, targetRir: top?.prefillRir, restSeconds: top?.restSeconds,
            coachNote: nil, isPerArm: canonical.isPerArm ? true : nil)
        for note in notes { adjustments.append("\(name): \(note)") }
        let rationale = "No history yet: " + (notes.isEmpty ? "the coach's starting sets" : notes.joined(separator: "; "))
        var lift = PlanLift(exercise: exercise, targets: targets, draft: nil, decision: decision, cue: cue, superset: nil,
                            evidenceLine: "", rationale: rationale)
        lift.decision.finalTop = decision.finalTop
        return lift
    }

    /// The athlete's top weight on a similar lift (same muscle and class) that has history; nil when none.
    private static func similarTopWeight(name: String, muscleGroup: String, cls: ExerciseClass, ctx: PlanDecisionContext) -> Double? {
        let muscle = MuscleGroups.canonical(forExercise: name, muscleGroup: muscleGroup)
        let weights = ctx.history.groups.compactMap { group -> Double? in
            guard MuscleGroups.canonical(forExercise: group.displayName, muscleGroup: "") == muscle
                    || ctx.draft.contains(where: { ExerciseNameResolver.isMatch($0.name, group.displayName)
                        && MuscleGroups.canonical(forExercise: $0.name, muscleGroup: $0.muscleGroup) == muscle }),
                  ExerciseTraits.classify(group.displayName) == cls else { return nil }
            return group.capBest?.weight
        }
        return weights.max()
    }

    /// The coach's starting sets, clamped (reps 5...15, RIR at least 2, at most 3 work sets), or nil when unusable:
    /// no work set, a missing or negative weight, or a weight far above the athlete's similar lift.
    static func validStartingSets(_ sets: [StartingSet], similarTop: Double?, notes: inout [String]) -> [SetTarget]? {
        guard !sets.isEmpty else { return nil }
        var out: [SetTarget] = []
        var work = 0
        var warm = 0
        var clamped = false
        for s in sets {
            guard let weight = s.weight, weight >= 0, weight < 2_000 else { return nil }
            if s.isWarmup {
                warm += 1
                guard warm <= PlanGuardrails.maxWarmups else { continue }
                out.append(SetTarget(weight: weight > 0 ? g(weight) : "BW", reps: String(min(15, max(5, s.reps ?? 8))), rir: "4",
                                     isWarmup: true, role: .warmup, restSeconds: ProgressionEngine.warmupRest))
                continue
            }
            work += 1
            guard work <= 3 else { clamped = true; continue }
            if let similarTop, weight > similarTop * similarLiftTolerance { return nil }
            let reps = s.reps ?? 10
            let rir = s.rir ?? 2
            if !(5...15).contains(reps) || rir < 2 { clamped = true }
            out.append(SetTarget(weight: weight > 0 ? g(weight) : "BW", reps: String(min(15, max(5, reps))),
                                 rir: String(max(2, min(5, rir))), isWarmup: nil, role: nil, restSeconds: s.rest))
        }
        guard work > 0 else { return nil }
        if clamped { notes.append("starting sets kept to 5-15 reps, RIR 2 or more and 3 work sets at most") }
        return out
    }

    /// The app's own starting sets for a lift with no history: 70% of a similar lift's weight when there is one,
    /// else no weight (the athlete picks it), for 2 sets (isolation) or 3 sets of 10 at RIR 2.
    static func defaultStartingSets(name: String, cls: ExerciseClass, similarTop: Double?, ctx: PlanDecisionContext) -> [SetTarget] {
        let ladder = WeightIncrements.fallback(for: name)
        let weight = similarTop.map { ladder.snap($0 * 0.7, direction: .down) }
        let text = weight.map(g)
        let count = cls == .isolation ? 2 : 3
        return (0..<count).map { _ in SetTarget(weight: text, reps: "10", rir: "2") }
    }

    // MARK: - Evidence

    private static func evidence(for lift: PlanLift, group: ExerciseHistoryGroup?, adjustments: [String]) -> ExerciseEvidence {
        let last = group?.sessions.first
        let bestText = group?.best.map { "\(g($0.weight))×\($0.reps)" }
        let trend = group.map { ProgressionEngine.trend($0.sessions) } ?? .flat
        var reasons = adjustments
        if let held = lift.decision.held { reasons.insert("Held: \(held)", at: 0) }
        return ExerciseEvidence(
            source: lift.hasHistory ? .engine : .newLift,
            lastSets: last.map { $0.sets.map(\.text) } ?? [], lastSessionDate: last?.date, best: bestText, trend: trend,
            rationale: lift.rationale, style: lift.draft?.result.style, warmupCount: lift.targets.filter { $0.isWarmup == true }.count,
            adjustedByGuardrails: !reasons.isEmpty, guardrailReasons: reasons,
            decisionLabel: lift.decision.label, reason: lift.decision.reason)
    }

    private static func adjustmentsFor(_ name: String, in checks: [PlanCheck]) -> [String] {
        checks.flatMap(\.adjustments).filter { $0.hasPrefix(name + ":") }
    }

    /// "Target: 175 lbs" plus the form cue, as the plan screen and the active workout read it.
    private static func refreshedNote(_ exercise: Exercise, lift: PlanLift) -> Exercise {
        var ex = exercise
        if let top = lift.top {
            ex.targetReps = top.prefillReps.isEmpty ? ex.targetReps : top.prefillReps
            ex.targetRir = top.prefillRir.isEmpty ? ex.targetRir : top.prefillRir
            if let rest = top.restSeconds { ex.restSeconds = rest }
        }
        ex.coachNote = combinedNote(weight: lift.top.flatMap { Double($0.prefillWeight) != nil ? "\($0.prefillWeight) lbs" : nil },
                                    cue: lift.cue)
        return ex
    }

    static func combinedNote(weight: String?, cue: String?) -> String? {
        let message = cue.flatMap { $0.isEmpty ? nil : "Cue: \($0)" }
        switch (weight, message) {
        case let (w?, m?): return "Target: \(w) — \(m)"
        case let (w?, nil): return "Target: \(w)"
        case let (nil, m?): return m
        case (nil, nil): return nil
        }
    }

    static func topText(_ set: ProgressionSet?) -> String? {
        set.map { "\(g($0.weight))x\($0.reps)@\($0.rir)" }
    }
}
