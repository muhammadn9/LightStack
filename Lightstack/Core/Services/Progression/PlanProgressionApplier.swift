import Foundation

/// The AI plan after the app's own numbers replaced or guarded the AI's.
struct AppliedPlan {
    var exercises: [Exercise]
    var setTargets: [UUID: [SetTarget]]
    /// Keyed by exercise id, one entry per exercise in the plan.
    var evidence: [UUID: ExerciseEvidence]
    /// Human-readable list of what was changed (for the debug screen).
    var adjustments: [String]
}

/// Swaps the AI's set numbers for `ProgressionEngine` output where history exists and
/// runs `PlanGuardrails` over everything else. The AI's coach note is kept.
enum PlanProgressionApplier {

    static func apply(
        plan: WorkoutSessionService.ParsedPlan,
        history: ExerciseHistoryIndex,
        energy: Int,
        /// Fallback when the exercise's last session carries no feedback of its own.
        feedback: SessionFeedback?,
        bestLookup: (String) -> Double? = { _ in nil }
    ) -> AppliedPlan {
        var exercises = plan.exercises
        var targets = plan.setTargets
        var evidence: [UUID: ExerciseEvidence] = [:]
        var adjustments: [String] = []

        // Only the first heavy compound of the workout gets warm-ups.
        let warmupIndex = exercises.firstIndex { ExerciseTraits.classify($0.name) == .heavyCompound }

        for i in exercises.indices {
            var ex = exercises[i]
            let group = history.group(for: ex.name)
            let best = group?.best
            let allowWarmups = (i == warmupIndex)
            let aiNote = ex.coachNoteParts.message

            let engine = group.flatMap {
                ProgressionEngine.plan(ProgressionInput(
                    name: ex.name, sessions: $0.sessions, best: best,
                    feedback: group?.sessions.first?.feedback ?? feedback, energy: energy, allowWarmups: allowWarmups))
            }

            let lastSession = group?.sessions.first
            let lastSets = lastSession.map { $0.sets.map(\.text) } ?? []
            let trend = group.map { ProgressionEngine.trend($0.sessions) } ?? .flat
            let bestText = best.map { "\(String(format: "%g", $0.weight))×\($0.reps)" }

            if let engine {
                let setTargets = engine.sets.map(\.setTarget)
                targets[ex.id] = setTargets
                ex.targetSets = setTargets.count
                if let top = engine.workingSets.max(by: { $0.weight < $1.weight }) {
                    ex.targetReps = String(top.reps)
                    ex.targetRir = String(top.rir)
                    let weight = "\(String(format: "%g", top.weight)) lbs"
                    ex.coachNote = aiNote.map { "Target: \(weight) — \($0)" } ?? "Target: \(weight)"
                }
                evidence[ex.id] = ExerciseEvidence(
                    source: .engine, lastSets: lastSets, lastSessionDate: lastSession?.date, best: bestText,
                    trend: trend, rationale: engine.rationale, style: engine.style,
                    warmupCount: engine.warmupCount, adjustedByGuardrails: false, guardrailReasons: [])
                adjustments.append("\(ex.name): engine set the targets (\(engine.rationale))")
            } else {
                let isCardio = ex.muscleGroup.lowercased() == "cardio"
                var report = GuardrailReport()
                if !isCardio {
                    let bestWeight = best?.weight ?? bestLookup(ex.name)
                    if let existing = targets[ex.id], !existing.isEmpty {
                        let guarded = PlanGuardrails.apply(
                            name: ex.name, targets: existing, allowWarmups: allowWarmups, bestWeight: bestWeight)
                        report = guarded.report
                        if report.adjustedByGuardrails {
                            targets[ex.id] = guarded.targets
                            ex.targetSets = guarded.targets.count
                        }
                    } else if let sets = ex.targetSets {
                        let clamp = PlanGuardrails.clampedSetCount(sets)
                        report = clamp.report
                        if report.adjustedByGuardrails { ex.targetSets = clamp.count }
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
        let kept = Set(exercises.map(\.id))
        return AppliedPlan(exercises: exercises, setTargets: targets.filter { kept.contains($0.key) },
                           evidence: evidence, adjustments: adjustments)
    }
}
