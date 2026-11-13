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

    // MARK: - Final structure pass

    /// What the final structure pass needs to know about the lift.
    struct StructureContext {
        var name: String
        var focus: CoachFocus
        var restPreference: Int
        /// The top-set weight of the lift's most recent session, and the recent best e1RM
        /// (best top set of the last few sessions; the all-time PR only when there is no recent history).
        var lastTop: Double?
        var bestE1RM: Double?
        /// The last review's target, honoured above the +5% limit when it is within the e1RM limit.
        var nextTarget: NextTarget?
        /// The back-off was dropped on purpose (muscle trained in the last 48 h).
        var backoffDropped: Bool = false
        /// The weights the lift can be loaded with (nil = the class default).
        var ladder: WeightIncrements? = nil
        /// Working sets of the lift's last session, for the rep-jump rule.
        var lastWork: [HistorySet] = []
    }

    /// The highest top-set weight a plan may carry: max(+5%, one increment) over the MOST RECENT session's
    /// top set, or the review's target when that stays within the recent-best e1RM limit.
    static func topWeightLimit(_ ctx: StructureContext) -> Double? {
        guard let last = ctx.lastTop, last > 0 else { return nil }
        let step = ctx.ladder?.increment ?? ExerciseTraits.increment(ctx.name)
        var limit = max(last * (1 + weightTolerance), last + step)
        if let t = ctx.nextTarget, t.weight > limit, let e1 = ctx.bestE1RM, e1 > 0,
           t.weight * (1 + Double(t.reps) / 30) <= e1 * 1.03 {
            limit = t.weight
        }
        return limit
    }

    /// Runs after every other edit (engine, AI review changes, caps) on rule-based plans. Enforces, for main
    /// lifts with a top set: at most one back-off (none is added), at most one top set (two for strength),
    /// Set 1 reps at least the top reps, and a top weight within `topWeightLimit`. Isolation work and plans
    /// without a top set pass through. Coach-written plans skip it: `validateCoachSets` is their rail.
    static func enforceMainLiftStructure(_ targets: [SetTarget], ctx: StructureContext) -> (targets: [SetTarget], reasons: [String]) {
        guard ExerciseTraits.classify(ctx.name) != .isolation,
              targets.contains(where: { $0.resolvedRole == .top }) else { return (targets, []) }
        var reasons: [String] = []
        let rungs = ctx.ladder ?? WeightIncrements.fallback(for: ctx.name)
        let warm = targets.filter { $0.isWarmup == true }
        var ramps = targets.filter { $0.isWarmup != true && $0.resolvedRole == .ramp }
        var tops = targets.filter { $0.isWarmup != true && $0.resolvedRole == .top }
        var backs = targets.filter { $0.isWarmup != true && $0.resolvedRole == .backoff }
        // Anything else (straight sets in a mixed list) stays where the model put it, after the back-off.
        let others = targets.filter { $0.isWarmup != true && ![SetRole.ramp, .top, .backoff].contains($0.resolvedRole) }

        let maxTops = ctx.focus == .strength ? 2 : 1
        if tops.count > maxTops {
            tops = Array(tops.prefix(maxTops))
            reasons.append("Kept \(maxTops) top set\(maxTops == 1 ? "" : "s")")
        }

        // Top weight limit.
        func weight(_ t: SetTarget) -> Double { Double(t.prefillWeight) ?? 0 }
        if let limit = topWeightLimit(ctx), let topW = tops.map(weight).max(), topW > limit {
            let clamp = rungs.snap(limit, direction: .down)
            for i in tops.indices where weight(tops[i]) > clamp { tops[i].weight = String(format: "%g", clamp) }
            reasons.append("Top set limited to \(String(format: "%g", clamp)) (more than +5% over your last top set)")
        }
        let topW = tops.map(weight).max() ?? 0
        let topReps = tops.compactMap { Int($0.prefillReps) }.min() ?? 0

        // Set 1: lighter than the top set, never fewer reps.
        for i in ramps.indices {
            if topW > 0, weight(ramps[i]) >= topW * 0.95 || weight(ramps[i]) >= topW {
                ramps[i].weight = String(format: "%g", rungs.snap(topW * 0.8, direction: .down))
            }
            if let r = Int(ramps[i].prefillReps), r < topReps { ramps[i].reps = String(topReps) }
        }

        // At most one back-off; one is never added (the coach or the engine decides whether there is one).
        if backs.count > 1 {
            backs = Array(backs.prefix(1))
            reasons.append("Kept one back-off")
        }
        for i in backs.indices {
            if topW > 0, weight(backs[i]) >= topW * 0.95 {
                var w = rungs.snap(topW * ProgressionEngine.backoffShare)
                if w >= topW * 0.95 { w = max(rungs.step, rungs.snap(topW * 0.95 - 0.001, direction: .down)) }
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

    // MARK: - Coach-written sets (v3)

    /// Longest rest the coach may set, seconds (strength focus gets more).
    static let maxCoachRest = 300
    static let maxCoachRestStrength = 360
    static let minCoachRest = 30
    static let maxCoachWorkingSets = 5
    static let maxCoachWarmups = 3
    /// The coach's top weight may rise at most this much over the lift's last top set.
    static let coachTopIncrease = 0.10
    /// No work set may estimate above the recent best e1RM by more than this.
    static let coachE1RMTolerance = 0.05
    /// After a long layoff the top weight must be at most this share of the last top.
    static let layoffTopShare = 0.95
    /// A work weight under this share of the last top at RIR 2 or less looks like a unit mix-up.
    static let unitConfusionShare = 0.5

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
        /// e1RM limit, never the gap rules or the unit-confusion rule. nil when today has no attempt.
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

    enum RailVerdict: Equatable {
        /// The sets stand (possibly after clamping); the strings say what was clamped.
        case accepted(softFixes: [String])
        /// The exercise's sets are outside the safety rails; the string says which rail.
        case rejected(reason: String)
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

    /// The fuel backstop: when fuel is low, no work set may be heavier than the lift's last top set. Sets above it
    /// are lowered to it; sets at or below it are left alone. Returns the weight the lift was held at when anything
    /// changed. Does nothing without a last top set or without a low-fuel assessment.
    static func applyFuelHold(
        _ targets: [SetTarget], lastTopWeight: Double?, hold: FuelAssessment?
    ) -> (targets: [SetTarget], heldAt: Double?) {
        guard let hold, hold.isLow, let cap = lastTopWeight, cap > 0 else { return (targets, nil) }
        var out = targets
        var changed = false
        for i in out.indices where out[i].isWarmup != true {
            guard let weight = Double(out[i].prefillWeight), weight > cap + 0.001 else { continue }
            out[i].weight = String(format: "%g", cap)
            changed = true
        }
        return (out, changed ? cap : nil)
    }

    /// Checks AI-written sets against the wide safety rails and clamps the small stuff.
    /// Rejected: top weight too far above the last top set (tighter after a gap), any work set above the
    /// recent best e1RM + 5%, or a work weight under half the last top at RIR 2 or less.
    /// Everything else is clamped (reps 1-30, RIR 0-5 with one RIR 0, at most 5 work sets and 3 warm-ups,
    /// no warm-up at or above the first work weight, rest 30-300 s) and reported in `softFixes`.
    static func validateCoachSets(
        name: String, targets: [SetTarget], ctx: RailContext
    ) -> (targets: [SetTarget], verdict: RailVerdict) {
        func g(_ v: Double) -> String { String(format: "%g", v) }
        let fixed = softFixCoachSets(targets, focus: ctx.focus)
        let work = fixed.targets.filter { $0.isWarmup != true }
        guard !work.isEmpty else { return (targets, .rejected(reason: "the plan has no working sets")) }
        let weights = work.map { Double($0.prefillWeight) ?? 0 }
        let topW = weights.max() ?? 0

        // 1. Top weight against the last top set and the gap rules.
        if let rail = coachTopLimit(ctx), topW > rail.limit + 0.001 {
            return (targets, .rejected(reason: "top weight \(g(topW)) is above the limit of \(g(rail.limit)) (\(rail.rule))"))
        }
        // 2. Estimated one-rep max against the recent best (or the record's weight when nothing recent exists).
        if let best = ctx.capBestE1RM, best > 0 {
            var e1RMLimit = best * (1 + coachE1RMTolerance)
            if let allowance = ctx.goalAllowance {
                e1RMLimit = max(e1RMLimit, HistorySet(allowance, max(1, ctx.goalReps)).e1RM)
            }
            for t in work {
                let set = HistorySet(Double(t.prefillWeight) ?? 0, Int(t.prefillReps) ?? 1)
                if set.e1RM > e1RMLimit + 0.001 {
                    return (targets, .rejected(reason: "\(g(set.weight))×\(set.reps) estimates a \(g(set.e1RM.rounded())) one-rep max, more than 5% over your recent best \(g(best.rounded()))"))
                }
            }
        } else if let pr = ctx.prWeight, pr > 0,
                  topW > max(pr * (1 + coachE1RMTolerance), ctx.goalAllowance ?? 0) + 0.001 {
            return (targets, .rejected(reason: "top weight \(g(topW)) is more than 5% above your record \(g(pr))"))
        }
        // 3. Unit / per-arm confusion.
        if let last = ctx.lastTop, last.weight > 0 {
            for (t, w) in zip(work, weights) where w < last.weight * unitConfusionShare && (Int(t.prefillRir) ?? 3) <= 2 {
                return (targets, .rejected(reason: "work weight \(g(w)) is under half the last top set \(g(last.weight)) at hard effort (a unit or per-arm mix-up?)"))
            }
        }
        let roled = assignCoachRoles(fixed.targets, isolation: ctx.cls == .isolation)
        let jumps = capRepJumps(roled, last: ctx.lastWork, ladder: ctx.ladder ?? WeightIncrements.fallback(for: name))
        return (jumps.targets, .accepted(softFixes: fixed.fixes + jumps.reasons))
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

    /// Clamps the small stuff in AI-written sets. Returns the sets (warm-ups first) and what changed.
    static func softFixCoachSets(_ targets: [SetTarget], focus: CoachFocus) -> (targets: [SetTarget], fixes: [String]) {
        var fixes: [String] = []
        var rows = targets
        func isWarm(_ t: SetTarget) -> Bool { t.isWarmup == true || t.role == .warmup }

        // Warm-ups first, in order.
        let warmFirst = rows.filter { isWarm($0) } + rows.filter { !isWarm($0) }
        if warmFirst != rows {
            rows = warmFirst
            fixes.append("Moved warm-ups ahead of the working sets")
        }

        // Reps 1...30.
        var repsFixed = false
        for i in rows.indices {
            let reps = Int(rows[i].prefillReps)
            let clamped = min(30, max(1, reps ?? 8))
            if reps != clamped { rows[i].reps = String(clamped); repsFixed = true }
        }
        if repsFixed { fixes.append("Reps kept between 1 and 30") }

        // RIR 0...5, and at most one RIR 0 among the working sets (the last one keeps it).
        var rirFixed = false
        for i in rows.indices where !isWarm(rows[i]) {
            let rir = Int(rows[i].prefillRir)
            let clamped = min(5, max(0, rir ?? 2))
            if rir != clamped { rows[i].rir = String(clamped); rirFixed = true }
        }
        let zeroIdx = rows.indices.filter { !isWarm(rows[$0]) && rows[$0].prefillRir == "0" }
        for i in zeroIdx.dropLast() { rows[i].rir = "1"; rirFixed = true }
        if rirFixed { fixes.append("RIR kept between 0 and 5, with RIR 0 on one set at most") }

        // At most 5 working sets: drop from the end, never the heaviest.
        var workIdx = rows.indices.filter { !isWarm(rows[$0]) }
        if workIdx.count > maxCoachWorkingSets {
            let weights = workIdx.map { Double(rows[$0].prefillWeight) ?? 0 }
            let heaviest = workIdx[weights.firstIndex(of: weights.max() ?? 0) ?? 0]
            var drop = workIdx.count - maxCoachWorkingSets
            var remove: [Int] = []
            for i in workIdx.reversed() where drop > 0 && i != heaviest {
                remove.append(i)
                drop -= 1
            }
            for i in remove.sorted(by: >) { rows.remove(at: i) }
            fixes.append("Capped at \(maxCoachWorkingSets) working sets")
            workIdx = rows.indices.filter { !isWarm(rows[$0]) }
        }

        // Warm-ups: none at or above the first work weight, at most 3 (the heaviest ones stay).
        if let firstWork = workIdx.first {
            let firstWeight = Double(rows[firstWork].prefillWeight) ?? 0
            let before = rows.filter { isWarm($0) }.count
            rows.removeAll { isWarm($0) && (Double($0.prefillWeight) ?? 0) >= firstWeight }
            let removed = before - rows.filter { isWarm($0) }.count
            if removed > 0 {
                fixes.append("Removed \(removed) warm-up\(removed == 1 ? "" : "s") at or above the first working weight")
            }
        }
        let warmCount = rows.filter { isWarm($0) }.count
        if warmCount > maxCoachWarmups {
            var drop = warmCount - maxCoachWarmups
            rows.removeAll { row in
                guard isWarm(row), drop > 0 else { return false }
                drop -= 1
                return true
            }
            fixes.append("Capped warm-ups at \(maxCoachWarmups)")
        }

        // Rest 30...300 s (360 for strength).
        let maxRest = focus == .strength ? maxCoachRestStrength : maxCoachRest
        var restFixed = false
        for i in rows.indices {
            guard let rest = rows[i].restSeconds else { continue }
            let clamped = min(maxRest, max(minCoachRest, rest))
            if clamped != rest { rows[i].restSeconds = clamped; restFixed = true }
        }
        if restFixed { fixes.append("Rest kept between \(minCoachRest) and \(maxRest) s") }
        return (rows, fixes)
    }

    /// Roles for coach-written sets: warm-ups stay warm-ups, the heaviest work set is the top set,
    /// the rest are straight sets, and the first work set is Set 1 (`ramp`) only when it is more than
    /// 10% lighter than the top. Isolation work is all straight sets.
    static func assignCoachRoles(_ targets: [SetTarget], isolation: Bool = false) -> [SetTarget] {
        var out = targets
        let workIdx = out.indices.filter { out[$0].isWarmup != true && out[$0].role != .warmup }
        let weights = workIdx.map { Double(out[$0].prefillWeight) ?? 0 }
        let topWeight = weights.max() ?? 0
        let topPos = weights.firstIndex(of: topWeight) ?? 0
        for i in out.indices {
            if out[i].isWarmup == true || out[i].role == .warmup {
                out[i].role = .warmup
                continue
            }
            let pos = workIdx.firstIndex(of: i) ?? 0
            if isolation || topWeight <= 0 {
                out[i].role = .straight
            } else if pos == topPos {
                out[i].role = .top
            } else if pos == 0, topPos > 0, weights[0] < topWeight * 0.9 {
                out[i].role = .ramp
            } else {
                out[i].role = .straight
            }
        }
        return out
    }

    /// Fills the rest the coach left out of a set with the role's default; set rest the coach wrote stands.
    static func withDefaultRest(
        _ targets: [SetTarget], cls: ExerciseClass, focus: CoachFocus, restPreference: Int
    ) -> [SetTarget] {
        var out = targets
        for i in out.indices where out[i].restSeconds == nil {
            switch out[i].resolvedRole {
            case .warmup: out[i].restSeconds = ProgressionEngine.warmupRest
            case .ramp: out[i].restSeconds = ProgressionEngine.rampRest
            case .top: out[i].restSeconds = focus == .strength ? ProgressionEngine.strengthTopRest : ProgressionEngine.topRest
            case .backoff, .straight:
                out[i].restSeconds = max(cls == .isolation ? ProgressionEngine.isolationRest : ProgressionEngine.backoffRest,
                                         restPreference)
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
