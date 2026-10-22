import Foundation

/// What the guardrails changed about one exercise's targets.
struct GuardrailReport: Equatable {
    var adjustedByGuardrails: Bool { !reasons.isEmpty }
    var reasons: [String] = []
}

/// Sanity limits for AI-written targets (used for exercises the engine has no history for).
enum PlanGuardrails {

    static let minWorkingSets = 2
    static let maxWorkingSets = 5
    static let maxWarmups = 2
    /// At most this many working sets at 95%+ of a lift's heaviest weight.
    static let maxHeavySets = 2
    /// Hard sets (non-warm-up) per muscle per session.
    static let maxHardSetsPerMuscle = 10
    /// The coach may nudge a lift's load by this much, relative (-15% ... +5%).
    static let loadAdjustRange: ClosedRange<Double> = -15...5
    /// Weights above best × (1 + this) are clamped down.
    static let weightTolerance = 0.05

    static func apply(
        name: String,
        targets: [SetTarget],
        allowWarmups: Bool,
        bestWeight: Double?,
        workingSetCap: Int? = nil
    ) -> (targets: [SetTarget], report: GuardrailReport) {
        var report = GuardrailReport()
        guard !targets.isEmpty else { return (targets, report) }

        struct Row { var target: SetTarget; var warm: Bool }
        let logged = targets.map { t in
            HistorySet(Double(t.prefillWeight) ?? 0, Int(t.prefillReps) ?? 0, rir: Int(t.prefillRir))
        }
        let flags = SetStyleDetector.warmupFlags(logged)
        var rows: [Row] = []
        for (target, flag) in zip(targets, flags) {
            rows.append(Row(target: target, warm: flag || target.isWarmup == true))
        }
        // Everything flagged warm-up means the flags are unreliable: treat all as working.
        if rows.allSatisfy({ $0.warm }) {
            rows = rows.map { Row(target: $0.target, warm: false) }
        }

        // 1. Warm-ups: only the first big compound keeps them, and at most two.
        let warmCount = rows.filter { $0.warm }.count
        if warmCount > 0, !allowWarmups {
            rows.removeAll { $0.warm }
            report.reasons.append("Removed \(warmCount) warm-up set\(warmCount == 1 ? "" : "s") (only the first big lift gets them)")
        } else if warmCount > maxWarmups {
            var toDrop = warmCount - maxWarmups
            rows.removeAll { row in
                guard row.warm, toDrop > 0 else { return false }
                toDrop -= 1
                return true
            }
            report.reasons.append("Capped warm-ups at \(maxWarmups)")
        }

        // 2. Weights well above the best logged set are clamped down.
        if let best = bestWeight, best > 0 {
            let limit = best * (1 + weightTolerance)
            let step = ExerciseTraits.roundingStep(name)
            var clamp = ExerciseTraits.round(best, step: step)
            if clamp > limit { clamp = ExerciseTraits.floorStep(limit, step: step) }
            var changed = false
            for i in rows.indices {
                guard let w = Double(rows[i].target.prefillWeight), w > limit else { continue }
                rows[i].target.weight = String(format: "%g", clamp)
                changed = true
            }
            if changed {
                report.reasons.append("Weights above your best (\(String(format: "%g", best))) clamped to \(String(format: "%g", clamp))")
            }
        }

        // 3. Working set count 2...cap (5 unless the caller knows better).
        let cap = max(minWorkingSets, workingSetCap ?? maxWorkingSets)
        var working = rows.filter { !$0.warm }
        if working.count > cap {
            let extra = working.count - cap
            var toDrop = extra
            // Drop from the end.
            for i in rows.indices.reversed() where !rows[i].warm && toDrop > 0 {
                rows.remove(at: i)
                toDrop -= 1
            }
            report.reasons.append("Capped at \(cap) working sets")
        } else if working.count == 1, let lastWorking = working.last {
            rows.append(Row(target: lastWorking.target, warm: false))
            report.reasons.append("Raised to \(minWorkingSets) working sets")
        }

        // 4. Never RIR 0-1 on every working set.
        working = rows.filter { !$0.warm }
        let rirValues = working.map { Int($0.target.prefillRir) }
        if !working.isEmpty, rirValues.allSatisfy({ ($0 ?? 99) <= 1 }) {
            var seen = 0
            let total = working.count
            for i in rows.indices where !rows[i].warm {
                seen += 1
                rows[i].target.rir = seen == total ? "1" : "2"
            }
            report.reasons.append("RIR 0-1 on every set rewritten to 2…1")
        }

        // 5. Never more than two heavy sets (95%+ of the heaviest) per lift.
        let heavy = capHeavySets(rows.filter { !$0.warm }.map(\.target), step: ExerciseTraits.roundingStep(name))
        if heavy.changed {
            var queue = heavy.targets[...]
            for i in rows.indices where !rows[i].warm {
                if let next = queue.popFirst() { rows[i].target = next }
            }
            report.reasons.append("Heavy sets capped at \(maxHeavySets) per lift")
        }

        let result = rows.map { row -> SetTarget in
            var t = row.target
            t.isWarmup = row.warm ? true : t.isWarmup
            return t
        }
        return (report.reasons.isEmpty ? targets : result, report)
    }

    /// Sets beyond the second one at 95%+ of the heaviest weight are lowered to about 90% of it.
    static func capHeavySets(_ working: [SetTarget], step: Double) -> (targets: [SetTarget], changed: Bool) {
        let weights = working.map { Double($0.prefillWeight) ?? 0 }
        guard let top = weights.max(), top > 0 else { return (working, false) }
        var out = working
        var heavySeen = 0
        var changed = false
        for i in out.indices where weights[i] >= top * 0.95 {
            heavySeen += 1
            guard heavySeen > maxHeavySets else { continue }
            var lowered = ExerciseTraits.round(top * 0.9, step: step)
            if lowered >= top { lowered = max(step, top - step) }
            out[i].weight = String(format: "%g", lowered)
            changed = true
        }
        return (out, changed)
    }

    // MARK: - Final structure pass

    /// What the final structure pass needs to know about the lift.
    struct StructureContext {
        var name: String
        var focus: CoachFocus
        var restPreference: Int
        /// Heaviest recent top-set weight and the best e1RM, from logged history.
        var bestRecentTop: Double?
        var bestE1RM: Double?
        /// The last review's target, honoured above the +5% limit when it is within the e1RM limit.
        var nextTarget: NextTarget?
        /// The back-off was dropped on purpose (muscle trained in the last 48 h).
        var backoffDropped: Bool = false
    }

    /// The highest top-set weight a plan may carry: +5% (at least one plate step) over the best recent top set,
    /// or the review's target when that stays within the e1RM-based limit.
    static func topWeightLimit(_ ctx: StructureContext) -> Double? {
        guard let best = ctx.bestRecentTop, best > 0 else { return nil }
        let step = ExerciseTraits.roundingStep(ctx.name)
        var limit = max(best * (1 + weightTolerance), best + step)
        if let t = ctx.nextTarget, t.weight > limit, let e1 = ctx.bestE1RM, e1 > 0,
           t.weight * (1 + Double(t.reps) / 30) <= e1 * 1.03 {
            limit = t.weight
        }
        return limit
    }

    /// Runs after every other edit (engine, AI review changes, caps). Enforces, for main lifts with a top set:
    /// exactly one back-off, at most one top set (two for strength), Set 1 reps at least the top reps,
    /// and a top weight within `topWeightLimit`. Isolation work and plans without a top set pass through.
    static func enforceMainLiftStructure(_ targets: [SetTarget], ctx: StructureContext) -> (targets: [SetTarget], reasons: [String]) {
        guard ExerciseTraits.classify(ctx.name) != .isolation,
              targets.contains(where: { $0.resolvedRole == .top }) else { return (targets, []) }
        var reasons: [String] = []
        let step = ExerciseTraits.roundingStep(ctx.name)
        let warm = targets.filter { $0.isWarmup == true }
        var ramps = targets.filter { $0.isWarmup != true && $0.resolvedRole == .ramp }
        var tops = targets.filter { $0.isWarmup != true && $0.resolvedRole == .top }
        var backs = targets.filter { $0.isWarmup != true && $0.resolvedRole == .backoff }
        // Anything else (straight sets in a mixed list) stays where the model put it, after the back-off.
        let others = targets.filter { $0.isWarmup != true && ![SetRole.ramp, .top, .backoff].contains($0.resolvedRole) }

        let maxTops = ctx.focus == .strength ? 2 : 1
        if tops.count > maxTops {
            tops = Array(tops.prefix(maxTops))
            reasons.append("Kept \(maxTops) top set\(maxTops == 1 ? "" : "s") (a back-off follows instead)")
        }

        // Top weight limit.
        func weight(_ t: SetTarget) -> Double { Double(t.prefillWeight) ?? 0 }
        if let limit = topWeightLimit(ctx), let topW = tops.map(weight).max(), topW > limit {
            let clamp = ExerciseTraits.floorStep(limit, step: step)
            for i in tops.indices where weight(tops[i]) > clamp { tops[i].weight = String(format: "%g", clamp) }
            reasons.append("Top set limited to \(String(format: "%g", clamp)) (more than +5% over your best recent top set)")
        }
        let topW = tops.map(weight).max() ?? 0
        let topReps = tops.compactMap { Int($0.prefillReps) }.min() ?? 0

        // Set 1: lighter than the top set, never fewer reps.
        for i in ramps.indices {
            if topW > 0, weight(ramps[i]) >= topW * 0.95 || weight(ramps[i]) >= topW {
                ramps[i].weight = String(format: "%g", ExerciseTraits.floorStep(topW * 0.8, step: step))
            }
            if let r = Int(ramps[i].prefillReps), r < topReps { ramps[i].reps = String(topReps) }
        }

        // Exactly one back-off (unless dropped on purpose for recovery).
        if backs.count > 1 {
            backs = Array(backs.prefix(1))
            reasons.append("Kept one back-off")
        }
        if backs.isEmpty, !ctx.backoffDropped, topW > 0 {
            var w = ExerciseTraits.round(topW * ProgressionEngine.backoffShare, step: step)
            if w >= topW * 0.95 { w = max(step, ExerciseTraits.floorStep(topW * 0.95 - 0.001, step: step)) }
            backs = [SetTarget(weight: String(format: "%g", w), reps: String(max(topReps, 1)), rir: "2", role: .backoff,
                               restSeconds: max(ProgressionEngine.backoffRest, ctx.restPreference))]
            reasons.append("Added the missing back-off")
        }
        for i in backs.indices {
            if topW > 0, weight(backs[i]) >= topW * 0.95 {
                var w = ExerciseTraits.round(topW * ProgressionEngine.backoffShare, step: step)
                if w >= topW * 0.95 { w = max(step, ExerciseTraits.floorStep(topW * 0.95 - 0.001, step: step)) }
                backs[i].weight = String(format: "%g", w)
            }
            if let r = Int(backs[i].prefillReps), r < topReps { backs[i].reps = String(topReps) }
        }

        // Top-set rest: 180 s is for strength only.
        if ctx.focus != .strength {
            for i in tops.indices where (tops[i].restSeconds ?? 0) > ProgressionEngine.topRest {
                tops[i].restSeconds = ProgressionEngine.topRest
            }
        }

        let result = warm + ramps + tops + backs + others
        return (result == targets ? targets : result, reasons)
    }

    /// Roles and per-set rest for AI-written targets (new exercises), so every plan row carries them.
    /// Working sets: the heaviest becomes the top set, earlier ones Set 1 / ramp, later ones back-offs;
    /// isolation work stays straight sets.
    static func withRolesAndRest(
        _ targets: [SetTarget], cls: ExerciseClass, focus: CoachFocus, restPreference: Int
    ) -> [SetTarget] {
        var out = targets
        let workingIdx = out.indices.filter { out[$0].isWarmup != true }
        let weights = workingIdx.map { Double(out[$0].prefillWeight) ?? 0 }
        let topPos = weights.isEmpty ? 0 : (weights.firstIndex(of: weights.max() ?? 0) ?? 0)
        for i in out.indices {
            if out[i].isWarmup == true {
                out[i].role = .warmup
                out[i].restSeconds = ProgressionEngine.warmupRest
                continue
            }
            let pos = workingIdx.firstIndex(of: i) ?? 0
            if cls == .isolation || workingIdx.count < 2 {
                out[i].role = .straight
                out[i].restSeconds = max(ProgressionEngine.isolationRest, restPreference)
            } else if pos < topPos {
                out[i].role = .ramp
                out[i].restSeconds = ProgressionEngine.rampRest
            } else if pos == topPos {
                out[i].role = .top
                out[i].restSeconds = focus == .strength ? ProgressionEngine.strengthTopRest : ProgressionEngine.topRest
            } else {
                out[i].role = .backoff
                out[i].restSeconds = max(ProgressionEngine.backoffRest, restPreference)
            }
        }
        return out
    }

    /// Clamps a relative load change to the allowed range.
    static func clampLoadAdjustment(_ percent: Double) -> (percent: Double, clamped: Bool) {
        let c = min(loadAdjustRange.upperBound, max(loadAdjustRange.lowerBound, percent))
        return (c, c != percent)
    }

    /// Set-count clamp for an exercise that came without per-set targets.
    static func clampedSetCount(_ sets: Int, cap: Int? = nil) -> (count: Int, report: GuardrailReport) {
        let clamped = min(max(minWorkingSets, cap ?? maxWorkingSets), max(minWorkingSets, sets))
        var report = GuardrailReport()
        if clamped != sets { report.reasons.append("Set count \(sets) changed to \(clamped)") }
        return (clamped, report)
    }
}
