import Foundation

/// Deterministic progression engine. Given an exercise's logged history it decides the next
/// session's sets in the owner's standard structure. No AI, no randomness, no I/O.
///
/// Main lifts:  [warm-up] -> Set 1 (~80% of top) -> ONE top set -> Back-off (~92% of top).
/// Isolation:   2 sets, the last one closest to failure.
/// Rest is prescribed per set.
enum ProgressionEngine {

    static let mainWorkingSets = 3
    static let isolationWorkingSets = 2

    /// Rest by role, seconds (`restPreference` is the floor for isolation and back-off).
    static let warmupRest = 60
    static let rampRest = 90
    static let topRest = 120
    static let strengthTopRest = 180
    static let backoffRest = 90
    static let isolationRest = 60

    /// Set 1 / back-off as a share of the top set's weight.
    static let rampShare = 0.80
    static let backoffShare = 0.925

    private static let ladder = [
        RepRange(lower: 5, upper: 8), RepRange(lower: 6, upper: 10),
        RepRange(lower: 8, upper: 12), RepRange(lower: 10, upper: 15)
    ]

    private enum Mode { case reduce, holdRepeat, normal }

    private struct Ctx {
        var name: String
        var cls: ExerciseClass
        var step: Double
        var inc: Double
        var range: RepRange
        var mode: Mode
        var tooEasy: Bool
        var best: HistorySet?
        var focus: CoachFocus
    }

    // MARK: - Public

    /// Next session's sets, or nil when there is no usable history (let the AI's numbers stand).
    static func plan(_ input: ProgressionInput) -> ProgressionResult? {
        let sessions: [(warm: [HistorySet], work: [HistorySet], session: HistorySession)] = input.sessions.prefix(5).compactMap { s in
            let clean = HistorySession(date: s.date, sets: s.sets.filter { $0.reps > 0 && $0.weight >= 0 })
            let split = SetStyleDetector.splitWarmups(clean.sets)
            guard !split.working.isEmpty else { return nil }
            return (split.warmups, split.working, clean)
        }
        guard let last = sessions.first, (last.work.map(\.weight).max() ?? 0) > 0,
              let lastTop = referenceTop(last.work) else { return nil }

        let cls = ExerciseTraits.classify(input.name)
        let step = ExerciseTraits.roundingStep(input.name)
        let working = sessions.map { HistorySession(date: $0.session.date, sets: $0.work) }
        let range = topRange(cls: cls, focus: input.focus, sessions: working)
        let style = SetStyleDetector.detect(sessions: working)
        let full = sessions.map(\.session)
        let trend = self.trend(full)

        let regressed = full.count >= 2 && strength(full[0]) < 0.95 * strength(full[1])
        let mode: Mode
        if input.feedback == .tooHard || input.energy <= 2 { mode = .reduce }
        else if regressed || input.energy == 3 { mode = .holdRepeat }
        else { mode = .normal }
        let ctx = Ctx(name: input.name, cls: cls, step: step, inc: ExerciseTraits.increment(input.name),
                      range: range, mode: mode, tooEasy: input.feedback == .tooEasy, best: input.best,
                      focus: input.focus)

        // 1. The top set.
        var usedTarget = false
        var chosen: (weight: Double, reps: Int, text: String)
        if let target = input.nextTarget, isSane(target, lastTop: lastTop, ctx: ctx),
           input.focus != .maintenance || target.weight <= lastTop.weight {
            chosen = fromTarget(target, lastTop: lastTop, ctx: ctx)
            usedTarget = true
        } else {
            chosen = progressTop(lastTop, ctx: ctx)
        }
        chosen.weight = ExerciseTraits.round(chosen.weight, step: step)

        // Recency rule: muscles trained hard in the last 48 h hold their load at RIR 2.
        var recency = false
        if input.recentlyTrained {
            recency = true
            if chosen.weight > lastTop.weight {
                chosen = (lastTop.weight, lastTop.reps, "hold \(g(lastTop.weight))×\(lastTop.reps)")
            }
            chosen.text += ", RIR 2 (trained recently)"
        }

        // 2. The standard structure around it.
        let built: [ProgressionSet]
        if cls == .isolation {
            built = isolationSets(top: chosen, recency: recency, ctx: ctx, restPreference: input.restPreference)
        } else {
            let warm = input.allowWarmups && userWarmsUp(sessions.prefix(3).map(\.warm))
            built = mainSets(top: chosen, recency: recency, warmup: warm, ctx: ctx, restPreference: input.restPreference)
        }

        var action = chosen.text
        switch mode {
        case .reduce: action += input.feedback == .tooHard ? " (felt too hard)" : " (low energy)"
        case .holdRepeat: action += regressed ? " (down vs previous session)" : " (low energy)"
        case .normal: break
        }
        if usedTarget { action += " (from last review)" }
        let lastText = last.work.map(\.text).joined(separator: ", ")
        let structure = built.filter { !$0.isWarmup }.map { "\($0.role.label) \(g($0.weight))×\($0.reps)" }.joined(separator: ", ")
        let rationale = "Last: \(lastText) → \(action). \(structure)"
        var result = ProgressionResult(sets: built, rationale: rationale, style: style, repRange: range, trend: trend)
        result.usedNextTarget = usedTarget
        result.recencyApplied = recency
        return result
    }

    /// Where the next top set would go after this one (double progression), for review defaults.
    static func nextTopTarget(name: String, after top: HistorySet, focus: CoachFocus = .hypertrophy,
                              best: HistorySet? = nil, history: [HistorySession] = []) -> (weight: Double, reps: Int) {
        let cls = ExerciseTraits.classify(name)
        let sessions = history.isEmpty ? [HistorySession(date: Date(), sets: [top])] : history
        let ctx = Ctx(name: name, cls: cls, step: ExerciseTraits.roundingStep(name),
                      inc: ExerciseTraits.increment(name),
                      range: topRange(cls: cls, focus: focus, sessions: sessions),
                      mode: .normal, tooEasy: false, best: best, focus: focus)
        let next = progressTop(top, ctx: ctx)
        return (ExerciseTraits.round(next.weight, step: ctx.step), next.reps)
    }

    /// The set the last session was built around: the best estimated one-rep max (heavier on ties).
    static func referenceTop(_ working: [HistorySet]) -> HistorySet? {
        var best: HistorySet?
        for s in working where s.reps > 0 {
            guard let b = best else { best = s; continue }
            if s.e1RM > b.e1RM * 1.0001 || (abs(s.e1RM - b.e1RM) <= b.e1RM * 0.0001 && s.weight > b.weight) { best = s }
        }
        return best
    }

    /// Trend arrow input: strength of the last session against the one before.
    static func trend(_ sessions: [HistorySession]) -> ProgressionTrend {
        guard sessions.count >= 2 else { return .flat }
        let now = strength(sessions[0]), before = strength(sessions[1])
        guard before > 0 else { return .flat }
        if now > before * 1.02 { return .up }
        if now < before * 0.98 { return .down }
        return .flat
    }

    /// Session strength: best e1RM among working sets of 3+ reps (all sets if there are none).
    static func strength(_ session: HistorySession) -> Double {
        let work = SetStyleDetector.splitWarmups(session.sets).working
        let heavy = work.filter { $0.reps >= 3 }
        return (heavy.isEmpty ? work : heavy).map(\.e1RM).max() ?? 0
    }

    /// Rep range for a lift's top (or only) working set.
    static func topRange(cls: ExerciseClass, focus: CoachFocus, sessions: [HistorySession]) -> RepRange {
        if cls == .isolation { return inferRange(cls: cls, sessions: sessions) }
        return focus == .strength ? RepRange(lower: 3, upper: 6) : RepRange(lower: 6, upper: 10)
    }

    /// Rep range for the exercise: the class default, moved up the ladder when the athlete's
    /// own recent reps are consistently above it.
    static func inferRange(cls: ExerciseClass, sessions: [HistorySession]) -> RepRange {
        var index: Int
        switch cls {
        case .heavyCompound: index = 0
        case .compound: index = 1
        case .isolation: index = 2
        }
        let reps = sessions.prefix(3).flatMap { SetStyleDetector.splitWarmups($0.sets).working }.map(\.reps)
        guard reps.count >= 4 else { return ladder[index] }
        while index < ladder.count - 1 {
            let above = reps.filter { $0 > ladder[index].upper }.count
            if Double(above) / Double(reps.count) >= 0.7 { index += 1 } else { break }
        }
        return ladder[index]
    }

    // MARK: - Top set

    private static func userWarmsUp(_ warmups: [[HistorySet]]) -> Bool {
        warmups.contains { !$0.isEmpty }
    }

    private static func isSane(_ t: NextTarget, lastTop: HistorySet, ctx: Ctx) -> Bool {
        guard t.weight > 0, (1...30).contains(t.reps), lastTop.weight > 0 else { return false }
        let ceiling = max(lastTop.weight * 1.10, lastTop.weight + ctx.inc)
        guard t.weight >= lastTop.weight * 0.80, t.weight <= ceiling else { return false }
        if let b = ctx.best, t.weight > b.weight + 2 * ctx.inc { return false }
        if t.weight >= lastTop.weight * 0.99, t.reps > lastTop.reps + 3 { return false }
        return true
    }

    /// The review's target, still bent by energy and feedback for today.
    private static func fromTarget(_ t: NextTarget, lastTop: HistorySet, ctx: Ctx) -> (weight: Double, reps: Int, text: String) {
        switch ctx.mode {
        case .reduce:
            let w = ExerciseTraits.floorStep(t.weight * 0.95, step: ctx.step)
            return (w, t.reps, "review target \(g(t.weight))×\(t.reps), down about 5% to \(g(w))")
        case .holdRepeat:
            if t.weight > lastTop.weight {
                return (lastTop.weight, lastTop.reps, "hold top set \(g(lastTop.weight))×\(lastTop.reps)")
            }
            return (t.weight, t.reps, "top set \(g(t.weight))×\(t.reps)")
        case .normal:
            return (t.weight, t.reps, "top set \(g(t.weight))×\(t.reps)")
        }
    }

    /// Double progression for the top set.
    private static func progressTop(_ top: HistorySet, ctx: Ctx) -> (weight: Double, reps: Int, text: String) {
        switch ctx.mode {
        case .reduce:
            var w = ExerciseTraits.floorStep(top.weight * 0.95, step: ctx.step)
            if w >= top.weight { w = max(ctx.step, top.weight - ctx.step) }
            return (w, top.reps, "top set down about 5% to \(g(w))")
        case .holdRepeat:
            return (top.weight, top.reps, "hold top set \(g(top.weight))×\(top.reps)")
        case .normal:
            if ctx.focus == .maintenance {
                return (top.weight, top.reps, "maintenance: hold top set \(g(top.weight))×\(top.reps)")
            }
            let raised = top.weight + ctx.inc
            let allowed = ctx.best.map { raised <= $0.weight + ctx.inc } ?? true
            if top.reps < ctx.range.lower {
                // Under the range: add load only with plenty in reserve, else build reps.
                if ((top.rir ?? 1) >= 2 || ctx.tooEasy) && allowed {
                    return (raised, top.reps, "top set +\(g(ctx.inc)) to \(g(raised))×\(top.reps)")
                }
                let reps = min(ctx.range.upper, top.reps + 1)
                return (top.weight, reps, "top set \(g(top.weight))×\(reps)")
            }
            if (top.reps >= ctx.range.upper && (top.rir ?? 0) <= 2 || ctx.tooEasy) && allowed {
                var reps = ctx.range.lower
                if top.reps > ctx.range.upper {
                    // Far above the range: land near the top of it at the heavier load.
                    let estimate = Int(((top.e1RM / raised) - 1) * 30)
                    reps = min(ctx.range.upper, max(ctx.range.lower, estimate))
                }
                return (raised, reps, "top set +\(g(ctx.inc)) to \(g(raised))×\(reps)")
            }
            let reps = min(ctx.range.upper, top.reps + 1)
            return (top.weight, reps, "top set \(g(top.weight))×\(reps)")
        }
    }

    // MARK: - Structures

    private static func mainSets(top: (weight: Double, reps: Int, text: String), recency: Bool, warmup: Bool,
                                 ctx: Ctx, restPreference: Int) -> [ProgressionSet] {
        let strength = ctx.focus == .strength
        let steady = recency || ctx.mode != .normal
        let topRir = steady ? 2 : 1
        var sets: [ProgressionSet] = []

        let rampWeight = rampWeight(forTop: top.weight, step: ctx.step)
        // Set 1 is lighter, so it gets more reps than the top set (hypertrophy ~10-12, strength up to 8).
        let rampReps = strength ? max(top.reps, min(8, top.reps + 2)) : max(top.reps, min(12, max(10, top.reps + 3)))

        if warmup {
            var w = ExerciseTraits.round(top.weight * 0.5, step: ctx.step)
            if w >= rampWeight { w = ExerciseTraits.round(rampWeight * 0.6, step: ctx.step) }
            if w < rampWeight {
                sets.append(ProgressionSet(weight: w, reps: 10, rir: 5, role: .warmup, restSeconds: warmupRest))
            }
        }
        sets.append(ProgressionSet(weight: rampWeight, reps: rampReps, rir: 2, role: .ramp, restSeconds: rampRest))
        sets.append(ProgressionSet(weight: top.weight, reps: top.reps, rir: topRir, role: .top,
                                   restSeconds: strength ? strengthTopRest : topRest))
        guard !recency else { return sets }

        if strength {
            // Strength focus may repeat the top weight once, but a back-off still follows.
            sets.append(ProgressionSet(weight: top.weight, reps: max(ctx.range.lower, top.reps - 1), rir: 1,
                                       role: .top, restSeconds: strengthTopRest))
        }
        var weight = ExerciseTraits.round(top.weight * backoffShare, step: ctx.step)
        if weight >= top.weight { weight = max(ctx.step, top.weight - ctx.step) }
        let reps = max(top.reps, min(ctx.range.upper, top.reps + 1))
        sets.append(ProgressionSet(weight: weight, reps: reps, rir: 2, role: .backoff,
                                   restSeconds: max(backoffRest, restPreference)))
        return sets
    }

    /// Set 1: about 80% of the top set, kept inside 75-85% when the plate step allows.
    private static func rampWeight(forTop top: Double, step: Double) -> Double {
        let target = top * rampShare
        let down = ExerciseTraits.floorStep(target, step: step)
        let up = down + step
        let candidates = [down, up].filter { $0 >= top * 0.75 && $0 <= top * 0.85 && $0 < top }
        if let best = candidates.min(by: { abs($0 - target) < abs($1 - target) }) { return best }
        let rounded = ExerciseTraits.round(target, step: step)
        return rounded < top ? rounded : max(step, top - step)
    }

    private static func isolationSets(top: (weight: Double, reps: Int, text: String), recency: Bool,
                                      ctx: Ctx, restPreference: Int) -> [ProgressionSet] {
        let rest = max(isolationRest, restPreference)
        let steady = recency || ctx.mode != .normal
        return [
            ProgressionSet(weight: top.weight, reps: top.reps, rir: 2, role: .straight, restSeconds: rest),
            ProgressionSet(weight: top.weight, reps: top.reps, rir: steady ? 2 : 1, role: .straight, restSeconds: rest)
        ]
    }

    private static func g(_ value: Double) -> String { String(format: "%g", value) }
}
