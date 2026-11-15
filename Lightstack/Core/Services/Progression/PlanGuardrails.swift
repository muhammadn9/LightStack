import Foundation

/// What the guardrails changed about one exercise's targets.
struct GuardrailReport: Equatable {
    var adjustedByGuardrails: Bool { !reasons.isEmpty }
    var reasons: [String] = []
}

/// Sanity limits for the coach's starting sets (exercises the engine has no history for) and the rails a push or a goal step must pass.
enum PlanGuardrails {

    static let minWorkingSets = 2
    static let maxWorkingSets = 5
    static let maxWarmups = 2
    /// At most this many working sets at 95%+ of a lift's heaviest weight.
    static let maxHeavySets = 2
    /// Hard sets (non-warm-up) per muscle per session.
    static let maxHardSetsPerMuscle = 10
    /// Weights above best × (1 + this) are clamped down.
    static let weightTolerance = 0.05

    static func apply(
        name: String,
        targets: [SetTarget],
        allowWarmups: Bool,
        bestWeight: Double?,
        workingSetCap: Int? = nil,
        ladder: WeightIncrements? = nil
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
            let rungs = ladder ?? WeightIncrements.fallback(for: name)
            var clamp = rungs.snap(best)
            if clamp > limit { clamp = rungs.snap(limit, direction: .down) }
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
        let heavy = capHeavySets(rows.filter { !$0.warm }.map(\.target), step: ExerciseTraits.roundingStep(name),
                                 ladder: ladder)
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
    static func capHeavySets(_ working: [SetTarget], step: Double,
                             ladder: WeightIncrements? = nil) -> (targets: [SetTarget], changed: Bool) {
        let weights = working.map { Double($0.prefillWeight) ?? 0 }
        guard let top = weights.max(), top > 0 else { return (working, false) }
        var out = working
        var heavySeen = 0
        var changed = false
        for i in out.indices where weights[i] >= top * 0.95 {
            heavySeen += 1
            guard heavySeen > maxHeavySets else { continue }
            var lowered = ladder?.snap(top * 0.9) ?? ExerciseTraits.round(top * 0.9, step: step)
            if lowered >= top { lowered = ladder?.stepDown(from: top) ?? max(step, top - step) }
            out[i].weight = String(format: "%g", lowered)
            changed = true
        }
        return (out, changed)
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

    // MARK: - Rails for a push or a goal step

    /// The coach's top weight may rise at most this much over the lift's last top set.
    static let coachTopIncrease = 0.10
    /// No work set may estimate above the recent best e1RM by more than this.
    static let coachE1RMTolerance = 0.05
    /// After a long layoff the top weight must be at most this share of the last top.
    static let layoffTopShare = 0.95

    /// What the rails need to know about one lift.
    struct RailContext {
        var name: String
        var cls: ExerciseClass
        var focus: CoachFocus
        /// The top work set of the lift's most recent session (nil with no usable history).
        var lastTop: HistorySet?
        /// Whole days since that session (nil when unknown).
        var daysSinceLast: Int?
        /// Recent best e1RM (`ExerciseHistoryGroup.capBest`), nil when unknown.
        var capBestE1RM: Double?
        /// Heaviest weight on record (PR), used when there is no recent history.
        var prWeight: Double?
        /// A per-lift absolute top weight (an agreed goal attempt) that may exceed the +10% limit and the
        /// e1RM limit, never the gap rules. nil when today has no attempt.
        var goalAllowance: Double?
        /// Reps of that attempt; its estimated one-rep max is the e1RM ceiling the allowance lifts.
        var goalReps: Int
        /// The weights the lift can be loaded with (nil = the class default).
        var ladder: WeightIncrements?
        /// Working sets of the lift's last session, for the rep-jump rule.
        var lastWork: [HistorySet]

        init(name: String, cls: ExerciseClass, focus: CoachFocus, lastTop: HistorySet? = nil,
             daysSinceLast: Int? = nil, capBestE1RM: Double? = nil, prWeight: Double? = nil,
             goalAllowance: Double? = nil, goalReps: Int = 1,
             ladder: WeightIncrements? = nil, lastWork: [HistorySet] = []) {
            self.name = name
            self.cls = cls
            self.focus = focus
            self.lastTop = lastTop
            self.daysSinceLast = daysSinceLast
            self.capBestE1RM = capBestE1RM
            self.prWeight = prWeight
            self.goalAllowance = goalAllowance
            self.goalReps = goalReps
            self.ladder = ladder
            self.lastWork = lastWork
        }
    }

    /// The highest top-set weight the rails allow, with the rule that set it.
    static func coachTopLimit(_ ctx: RailContext) -> (limit: Double, rule: String)? {
        guard let last = ctx.lastTop, last.weight >= 0 else { return nil }
        let inc = ctx.ladder?.increment ?? ExerciseTraits.increment(ctx.name)
        let w = last.weight
        let wText = String(format: "%g", w)
        if let days = ctx.daysSinceLast, days > ProgressionEngine.layoffAfterDays {
            return (w * layoffTopShare, "\(days) days since the last session, so at most 95% of \(wText)")
        }
        if let days = ctx.daysSinceLast, days > ProgressionEngine.holdAfterDays {
            return (w, "\(days) days since the last session, so no increase over \(wText)")
        }
        var limit = max(w * (1 + coachTopIncrease), w + inc)
        if let allowance = ctx.goalAllowance { limit = max(limit, allowance) }
        return (limit, "more than 10% (or one increment) over the last top set \(wText)")
    }

    /// The rep-jump rule on per-set targets (see `RepJumpRule`): every working set, top, back-off or isolation.
    static func capRepJumps(_ targets: [SetTarget], last: [HistorySet],
                            ladder: WeightIncrements) -> (targets: [SetTarget], reasons: [String]) {
        guard !last.isEmpty else { return (targets, []) }
        var out = targets
        var reasons: [String] = []
        for i in out.indices where out[i].isWarmup != true && out[i].role != .warmup {
            guard let weight = Double(out[i].prefillWeight), let reps = Int(out[i].prefillReps),
                  let cap = RepJumpRule.maxReps(weight: weight, rir: Int(out[i].prefillRir) ?? 2, last: last, ladder: ladder),
                  reps > cap.reps else { continue }
            out[i].reps = String(max(1, cap.reps))
            reasons.append("\(String(format: "%g", weight)) reps held at \(cap.reps) (last time \(cap.basis.text))")
        }
        return (out, reasons)
    }

    /// Set-count clamp for an exercise that came without per-set targets.
    static func clampedSetCount(_ sets: Int, cap: Int? = nil) -> (count: Int, report: GuardrailReport) {
        let clamped = min(max(minWorkingSets, cap ?? maxWorkingSets), max(minWorkingSets, sets))
        var report = GuardrailReport()
        if clamped != sets { report.reasons.append("Set count \(sets) changed to \(clamped)") }
        return (clamped, report)
    }
}
