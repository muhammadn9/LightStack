import Foundation

/// The AI plan after the app's own numbers replaced or guarded the AI's.
struct AppliedPlan {
    var exercises: [Exercise]
    var setTargets: [UUID: [SetTarget]]
    /// Keyed by exercise id, one entry per exercise in the plan.
    var evidence: [UUID: ExerciseEvidence]
    /// Human-readable list of what was changed (for the debug screen).
    var adjustments: [String]
    /// The coach's proposed edits with what the app did with each.
    var changes: [PlanChange] = []
    /// Deterministic rules that fired (recency, caps, ordering).
    var safeguards: [String] = []
}

/// Swaps the AI's set numbers for `ProgressionEngine` output where history exists, runs
/// `PlanGuardrails` over everything else, applies the coach's review edits inside the guardrails,
/// then enforces the per-muscle and per-lift caps. The AI's coach note is kept.
enum PlanProgressionApplier {

    static func apply(
        plan: WorkoutSessionService.ParsedPlan,
        history: ExerciseHistoryIndex,
        energy: Int,
        /// Fallback when the exercise's last session carries no feedback of its own.
        feedback: SessionFeedback?,
        bestLookup: (String) -> Double? = { _ in nil },
        coach: PlanCoachContext = PlanCoachContext(),
        changes: [PlanChange] = []
    ) -> AppliedPlan {
        var exercises = plan.exercises
        var targets = plan.setTargets
        var evidence: [UUID: ExerciseEvidence] = [:]
        var adjustments: [String] = []
        var safeguards: [String] = []

        // Heavy compounds first (unless supersets pin the order).
        if let moved = heavyFirst(exercises) {
            exercises = moved.exercises
            safeguards.append("Moved \(moved.names.joined(separator: ", ")) ahead of lighter work (heavy compounds go first)")
        }

        // Only the first one or two heavy compounds get warm-ups.
        let warmupIndexes = Set(exercises.indices.filter { ExerciseTraits.classify(exercises[$0].name) == .heavyCompound }.prefix(2))

        for i in exercises.indices {
            var ex = exercises[i]
            let group = history.group(for: ex.name)
            let best = group?.best
            let allowWarmups = warmupIndexes.contains(i)
            let aiNote = ex.coachNoteParts.message
            let muscle = MuscleGroups.canonical(forExercise: ex.name, muscleGroup: ex.muscleGroup)
            let fresh = coach.isFresh(muscle: muscle)

            let engine = group.flatMap {
                ProgressionEngine.plan(ProgressionInput(
                    name: ex.name, sessions: $0.sessions, best: best,
                    feedback: group?.sessions.first?.feedback ?? feedback, energy: energy, allowWarmups: allowWarmups,
                    focus: coach.focus, restPreference: coach.restPreference,
                    nextTarget: coach.nextTarget(for: ex.name, lastSessionDate: $0.sessions.first?.date),
                    recentlyTrained: fresh))
            }

            let lastSession = group?.sessions.first
            let lastSets = lastSession.map { $0.sets.map(\.text) } ?? []
            let trend = group.map { ProgressionEngine.trend($0.sessions) } ?? .flat
            let bestText = best.map { "\(String(format: "%g", $0.weight))×\($0.reps)" }

            if let engine {
                let setTargets = engine.sets.map(\.setTarget)
                targets[ex.id] = setTargets
                ex.targetSets = setTargets.count
                if let top = engine.topSet {
                    ex.targetReps = String(top.reps)
                    ex.targetRir = String(top.rir)
                    ex.restSeconds = top.restSeconds
                    let weight = "\(String(format: "%g", top.weight)) lbs"
                    ex.coachNote = combinedNote(weight: weight, message: aiNote, cue: plan.cues[ex.id])
                }
                evidence[ex.id] = ExerciseEvidence(
                    source: .engine, lastSets: lastSets, lastSessionDate: lastSession?.date, best: bestText,
                    trend: trend, rationale: engine.rationale, style: engine.style,
                    warmupCount: engine.warmupCount, adjustedByGuardrails: false, guardrailReasons: [])
                adjustments.append("\(ex.name): engine set the targets (\(engine.rationale))")
                if engine.recencyApplied {
                    safeguards.append("\(ex.name): \(muscle) trained hard in the last 48 h, so the load is held at RIR 2 and the back-off is dropped")
                }
            } else {
                let isCardio = ex.muscleGroup.lowercased() == "cardio"
                var report = GuardrailReport()
                if !isCardio {
                    let cls = ExerciseTraits.classify(ex.name)
                    let cap = cls == .isolation ? ProgressionEngine.isolationWorkingSets : ProgressionEngine.mainWorkingSets
                    let bestWeight = best?.weight ?? bestLookup(ex.name)
                    if let existing = targets[ex.id], !existing.isEmpty {
                        let guarded = PlanGuardrails.apply(
                            name: ex.name, targets: existing, allowWarmups: allowWarmups, bestWeight: bestWeight,
                            workingSetCap: cap)
                        report = guarded.report
                        let final = PlanGuardrails.withRolesAndRest(
                            guarded.targets, cls: cls, focus: coach.focus, restPreference: coach.restPreference)
                        targets[ex.id] = final
                        ex.targetSets = final.count
                        if let top = final.first(where: { $0.role == .top }) ?? final.last(where: { $0.isWarmup != true }),
                           let rest = top.restSeconds {
                            ex.restSeconds = rest
                        }
                    } else if let sets = ex.targetSets {
                        let clamp = PlanGuardrails.clampedSetCount(sets, cap: cap)
                        report = clamp.report
                        if report.adjustedByGuardrails { ex.targetSets = clamp.count }
                    }
                    if let cue = plan.cues[ex.id] {
                        ex.coachNote = combinedNote(weight: ex.coachNoteParts.weight, message: aiNote, cue: cue)
                    }
                }
                evidence[ex.id] = ExerciseEvidence(
                    source: report.adjustedByGuardrails ? .aiGuarded : .ai, lastSets: lastSets,
                    lastSessionDate: lastSession?.date, best: bestText, trend: trend,
                    rationale: group == nil ? "No history yet: coach estimate" : "Coach estimate",
                    style: nil, warmupCount: (targets[ex.id] ?? []).filter { $0.isWarmup == true }.count,
                    adjustedByGuardrails: report.adjustedByGuardrails, guardrailReasons: report.reasons)
                for reason in report.reasons { adjustments.append("\(ex.name): guardrail: \(reason)") }
            }
            exercises[i] = ex
        }

        // The coach's review edits, inside the guardrails.
        let handled = applyChanges(changes, exercises: &exercises, targets: &targets, adjustments: &adjustments)

        // Per-muscle hard-set cap, then the per-lift heavy-set cap on everything.
        safeguards.append(contentsOf: capMuscleVolume(&exercises, targets: &targets, adjustments: &adjustments))
        for ex in exercises {
            guard let list = targets[ex.id], !list.isEmpty else { continue }
            let working = list.filter { $0.isWarmup != true }
            let capped = PlanGuardrails.capHeavySets(working, step: ExerciseTraits.roundingStep(ex.name))
            guard capped.changed else { continue }
            var queue = capped.targets[...]
            targets[ex.id] = list.map { t in t.isWarmup == true ? t : (queue.popFirst() ?? t) }
            safeguards.append("\(ex.name): heavy sets capped at \(PlanGuardrails.maxHeavySets)")
        }

        // Re-number, and keep evidence and set counts in step with the final targets.
        for i in exercises.indices {
            exercises[i].orderIndex = i
            if let list = targets[exercises[i].id], !list.isEmpty { exercises[i].targetSets = list.count }
            evidence[exercises[i].id]?.warmupCount = (targets[exercises[i].id] ?? []).filter { $0.isWarmup == true }.count
        }
        let kept = Set(exercises.map(\.id))
        return AppliedPlan(exercises: exercises, setTargets: targets.filter { kept.contains($0.key) },
                           evidence: evidence.filter { kept.contains($0.key) }, adjustments: adjustments,
                           changes: handled, safeguards: safeguards)
    }

    // MARK: - Notes

    private static func combinedNote(weight: String?, message: String?, cue: String?) -> String? {
        var text = message ?? ""
        if let cue, !cue.isEmpty { text += (text.isEmpty ? "" : " ") + "Cue: \(cue)" }
        switch (weight, text.isEmpty ? nil : text) {
        case let (w?, m?): return "Target: \(w) — \(m)"
        case let (w?, nil): return "Target: \(w)"
        case let (nil, m?): return m
        case (nil, nil): return nil
        }
    }

    private static func refreshNoteWeight(_ ex: inout Exercise, targets: [SetTarget]) {
        let top = targets.filter { $0.isWarmup != true }
            .max { (Double($0.prefillWeight) ?? 0) < (Double($1.prefillWeight) ?? 0) }
        guard let w = top, !w.prefillWeight.isEmpty else { return }
        ex.coachNote = combinedNote(weight: "\(w.prefillWeight) lbs", message: ex.coachNoteParts.message, cue: nil)
        ex.targetReps = w.prefillReps.isEmpty ? ex.targetReps : w.prefillReps
    }

    // MARK: - Order

    /// Stable reorder with heavy compounds first. nil when nothing needs to move or supersets are present.
    static func heavyFirst(_ exercises: [Exercise]) -> (exercises: [Exercise], names: [String])? {
        guard exercises.allSatisfy({ $0.supersetGroupId == nil }) else { return nil }
        let isHeavy: (Exercise) -> Bool = { ExerciseTraits.classify($0.name) == .heavyCompound }
        // Only act when a heavy compound sits behind an isolation exercise.
        guard let firstIso = exercises.firstIndex(where: { ExerciseTraits.classify($0.name) == .isolation }),
              exercises[firstIso...].contains(where: isHeavy) else { return nil }
        let heavy = exercises.filter(isHeavy)
        let rest = exercises.filter { !isHeavy($0) }
        let moved = exercises[firstIso...].filter(isHeavy).map(\.name)
        return (heavy + rest, moved)
    }

    // MARK: - Review edits

    private static func applyChanges(
        _ changes: [PlanChange], exercises: inout [Exercise], targets: inout [UUID: [SetTarget]],
        adjustments: inout [String]
    ) -> [PlanChange] {
        var out: [PlanChange] = []
        for var change in changes {
            let index = exercises.firstIndex { ExerciseNameResolver.isMatch($0.name, change.exercise) }
            switch change.type {
            case .reorder:
                change.applied = true
                change.note = "Reflected in the exercise order"
            case .drop, .swap:
                if index == nil {
                    change.applied = true
                } else {
                    change.applied = false
                    change.note = "The exercise is still in the coach's list, so it was kept"
                }
            case .add:
                change.applied = index != nil
                if index == nil { change.note = "The exercise did not make it into the plan" }
            case .loadAdjust:
                guard let i = index else { change.note = "Exercise not in the plan"; break }
                applyLoad(&change, exercise: &exercises[i], targets: &targets)
            case .setCount:
                guard let i = index else { change.note = "Exercise not in the plan"; break }
                applySetCount(&change, exercise: &exercises[i], targets: &targets)
            }
            adjustments.append("Review \(change.type.rawValue) \(change.exercise): \(change.applied ? "applied" : "not applied")\(change.note.map { " (\($0))" } ?? "")")
            out.append(change)
        }
        return out
    }

    private static func applyLoad(_ change: inout PlanChange, exercise: inout Exercise, targets: inout [UUID: [SetTarget]]) {
        guard var list = targets[exercise.id], !list.isEmpty else { change.note = "No per-set numbers to adjust"; return }
        guard let requested = change.percent ?? percent(in: change.detail) else { change.note = "No percentage given"; return }
        let clamp = PlanGuardrails.clampLoadAdjustment(requested)
        guard abs(clamp.percent) >= 0.5 else { change.note = "Change too small"; return }
        let step = ExerciseTraits.roundingStep(exercise.name)
        let factor = 1 + clamp.percent / 100
        var moved = false
        for i in list.indices {
            guard let w = Double(list[i].prefillWeight), w > 0 else { continue }
            // Round toward the unchanged weight so the edit never goes beyond what was allowed.
            let new = clamp.percent < 0
                ? (w * factor / step).rounded(.up) * step
                : ExerciseTraits.floorStep(w * factor, step: step)
            if (clamp.percent < 0 ? new >= w : new <= w) { continue }
            list[i].weight = String(format: "%g", new)
            moved = true
        }
        guard moved else { change.note = "Rounded back to the same weights"; return }
        targets[exercise.id] = list
        refreshNoteWeight(&exercise, targets: list)
        change.applied = true
        change.percent = clamp.percent
        change.note = clamp.clamped ? "Clamped from \(String(format: "%g", requested))% to \(String(format: "%g", clamp.percent))%" : nil
    }

    private static func applySetCount(_ change: inout PlanChange, exercise: inout Exercise, targets: inout [UUID: [SetTarget]]) {
        guard let wanted = change.sets ?? firstInt(in: change.detail) else { change.note = "No set count given"; return }
        let cls = ExerciseTraits.classify(exercise.name)
        let isIso = cls == .isolation
        guard var list = targets[exercise.id], !list.isEmpty else {
            let clamp = PlanGuardrails.clampedSetCount(wanted, cap: isIso ? 3 : ProgressionEngine.mainWorkingSets)
            exercise.targetSets = clamp.count
            change.applied = true
            change.note = clamp.report.reasons.first
            return
        }
        let working = list.indices.filter { list[$0].isWarmup != true }
        let upper = isIso ? 3 : min(working.count, ProgressionEngine.mainWorkingSets)
        let target = min(upper, max(PlanGuardrails.minWorkingSets, wanted))
        guard target != working.count else {
            change.note = wanted > working.count && !isIso ? "Main lifts keep their \(working.count) working sets" : "Already \(working.count) working sets"
            return
        }
        if target < working.count {
            var toRemove = working.count - target
            while toRemove > 0 {
                let now = list.indices.filter { list[$0].isWarmup != true }
                let victim = now.last { list[$0].resolvedRole == .backoff }
                    ?? now.last { list[$0].resolvedRole == .ramp }
                    ?? now.last { list[$0].resolvedRole != .top }
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
        targets[exercise.id] = list
        exercise.targetSets = list.count
        change.applied = true
        change.sets = target
        if target != wanted { change.note = "Limited to \(target) working sets" }
    }

    private static func percent(in text: String) -> Double? {
        guard let r = text.range(of: #"[-+−]?\d+(\.\d+)?\s*%"#, options: .regularExpression) else { return nil }
        let raw = text[r].replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "+", with: "").trimmingCharacters(in: .whitespaces)
        guard let v = Double(raw) else { return nil }
        // "cut 10%" / "reduce by 10%" with no sign means lighter.
        let lower = text.lowercased()
        if v > 0, !text.contains("+"), ["cut", "reduce", "lower", "drop", "lighter", "decrease", "back off"].contains(where: { lower.contains($0) }) {
            return -v
        }
        return v
    }

    private static func firstInt(in text: String) -> Int? {
        guard let r = text.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(text[r])
    }

    // MARK: - Volume

    /// No muscle gets more than `PlanGuardrails.maxHardSetsPerMuscle` working sets in one session:
    /// isolation work is trimmed first (last exercise first), then extra compound sets.
    private static func capMuscleVolume(
        _ exercises: inout [Exercise], targets: inout [UUID: [SetTarget]], adjustments: inout [String]
    ) -> [String] {
        var notes: [String] = []
        func workingCount(_ ex: Exercise) -> Int {
            if let list = targets[ex.id], !list.isEmpty { return list.filter { $0.isWarmup != true }.count }
            return ex.targetSets ?? 0
        }
        let muscles = Set(exercises.filter { $0.trackingType != .cardio }.map {
            MuscleGroups.canonical(forExercise: $0.name, muscleGroup: $0.muscleGroup)
        })
        for muscle in muscles.sorted() {
            func members() -> [Int] {
                exercises.indices.filter {
                    exercises[$0].trackingType != .cardio
                        && MuscleGroups.canonical(forExercise: exercises[$0].name, muscleGroup: exercises[$0].muscleGroup) == muscle
                }
            }
            var total = members().reduce(0) { $0 + workingCount(exercises[$1]) }
            guard total > PlanGuardrails.maxHardSetsPerMuscle else { continue }
            let before = total
            var removed: [String] = []
            var guardCount = 0
            while total > PlanGuardrails.maxHardSetsPerMuscle, guardCount < 20 {
                guardCount += 1
                let ordered = members().sorted { a, b in
                    let ia = ExerciseTraits.classify(exercises[a].name) == .isolation
                    let ib = ExerciseTraits.classify(exercises[b].name) == .isolation
                    if ia != ib { return ia }          // isolation first
                    return a > b                        // later exercises first
                }
                var trimmed = false
                for i in ordered {
                    let ex = exercises[i]
                    let isIso = ExerciseTraits.classify(ex.name) == .isolation
                    let count = workingCount(ex)
                    if isIso, count <= PlanGuardrails.minWorkingSets, members().count > 1 {
                        // Drop the whole isolation exercise.
                        total -= count
                        removed.append("dropped \(ex.name)")
                        targets[ex.id] = nil
                        exercises.remove(at: i)
                        trimmed = true
                        break
                    }
                    if count > PlanGuardrails.minWorkingSets {
                        if var list = targets[ex.id], !list.isEmpty {
                            let now = list.indices.filter { list[$0].isWarmup != true }
                            if let v = now.last(where: { list[$0].resolvedRole == .backoff })
                                ?? now.last(where: { list[$0].resolvedRole != .top }) {
                                list.remove(at: v)
                                targets[ex.id] = list
                                exercises[i].targetSets = list.count
                            }
                        } else {
                            exercises[i].targetSets = count - 1
                        }
                        total -= 1
                        removed.append("-1 set on \(ex.name)")
                        trimmed = true
                        break
                    }
                }
                if !trimmed { break }
            }
            notes.append("\(muscle.capitalized): \(before) hard sets is over the \(PlanGuardrails.maxHardSetsPerMuscle) cap (\(removed.joined(separator: ", ")))")
            adjustments.append("Volume cap: \(notes.last ?? "")")
        }
        return notes
    }
}

// MARK: - Draft

/// One exercise of the engine's draft plan.
struct DraftExercise: Equatable {
    var name: String
    var muscleGroup: String
    var result: ProgressionResult
}

/// The engine's full draft for the next session of a workout type, built from the last
/// same-type session's exercise list. The model reviews this; the app applies the result.
enum PlanDraftBuilder {

    static func build(
        lastSessionExercises: [Exercise],
        history: ExerciseHistoryIndex,
        energy: Int,
        feedback: SessionFeedback?,
        coach: PlanCoachContext,
        timeMinutes: Int?
    ) -> [DraftExercise] {
        var ordered: [Exercise] = []
        for ex in lastSessionExercises.sorted(by: { $0.orderIndex < $1.orderIndex }) where ex.trackingType != .cardio {
            if !ordered.contains(where: { ExerciseNameResolver.isMatch($0.name, ex.name) }) { ordered.append(ex) }
        }
        if let moved = PlanProgressionApplier.heavyFirst(ordered) { ordered = moved.exercises }
        let warmupIndexes = Set(ordered.indices.filter { ExerciseTraits.classify(ordered[$0].name) == .heavyCompound }.prefix(2))

        var draft: [DraftExercise] = []
        for (i, ex) in ordered.enumerated() {
            guard let group = history.group(for: ex.name) else { continue }
            let muscle = MuscleGroups.canonical(forExercise: ex.name, muscleGroup: ex.muscleGroup)
            let input = ProgressionInput(
                name: ex.name, sessions: group.sessions, best: group.best,
                feedback: group.sessions.first?.feedback ?? feedback, energy: energy,
                allowWarmups: warmupIndexes.contains(i), focus: coach.focus, restPreference: coach.restPreference,
                nextTarget: coach.nextTarget(for: ex.name, lastSessionDate: group.sessions.first?.date),
                recentlyTrained: coach.isFresh(muscle: muscle))
            if let result = ProgressionEngine.plan(input) {
                draft.append(DraftExercise(name: ex.name, muscleGroup: ex.muscleGroup, result: result))
            }
        }
        // Fit the available time: drop trailing exercises, but keep the first two.
        if let limit = timeMinutes {
            while draft.count > 2, estimatedMinutes(draft) > Double(limit) * 1.1 { draft.removeLast() }
        }
        return draft
    }

    /// Rough session length: 40 s of work per set plus the prescribed rest, and a few minutes of setup.
    static func estimatedMinutes(_ draft: [DraftExercise]) -> Double {
        let seconds = draft.flatMap(\.result.sets).reduce(0) { $0 + 40 + $1.restSeconds }
        return Double(seconds) / 60 + 3
    }

    /// A plan made only of the draft, used when the model's reply cannot be read.
    static func parsedPlan(from draft: [DraftExercise], workoutId: UUID) -> WorkoutSessionService.ParsedPlan {
        let exercises = draft.enumerated().map { index, d in
            Exercise.create(workoutId: workoutId, name: d.name, muscleGroup: d.muscleGroup, orderIndex: index,
                            targetSets: d.result.sets.count, targetReps: nil, targetRir: nil,
                            restSeconds: RestPreference.seconds(forMuscleGroup: d.muscleGroup), coachNote: nil)
        }
        return WorkoutSessionService.ParsedPlan(exercises: exercises, setTargets: [:])
    }
}
