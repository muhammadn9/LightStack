import Foundation

/// Deterministic double-progression engine. Given an exercise's logged history it decides
/// the next session's sets. No AI, no randomness, no I/O.
enum ProgressionEngine {

    static let defaultWorkingSets = 3
    /// Upper bound on a pyramid's total sets, warm-ups included.
    static let maxPyramidSets = 6

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
        guard let last = sessions.first, (last.work.map(\.weight).max() ?? 0) > 0 else { return nil }

        let cls = ExerciseTraits.classify(input.name)
        let step = ExerciseTraits.roundingStep(input.name)
        let working = sessions.map { HistorySession(date: $0.session.date, sets: $0.work) }
        let range = inferRange(cls: cls, sessions: working)
        let style = SetStyleDetector.detect(sessions: working)
        let full = sessions.map(\.session)
        let trend = self.trend(full)

        let regressed = full.count >= 2 && strength(full[0]) < 0.95 * strength(full[1])
        let mode: Mode
        if input.feedback == .tooHard || input.energy <= 2 { mode = .reduce }
        else if regressed || input.energy == 3 { mode = .holdRepeat }
        else { mode = .normal }
        let ctx = Ctx(name: input.name, cls: cls, step: step, inc: ExerciseTraits.increment(input.name),
                      range: range, mode: mode, tooEasy: input.feedback == .tooEasy, best: input.best)

        var built: (sets: [ProgressionSet], action: String)
        switch style {
        case .straightSets: built = straight(last.work, count: defaultWorkingSets, ctx: ctx)
        case .dropSet: built = dropSet(last.work, ctx: ctx)
        case .topSetBackoff: built = topSetBackoff(last.work, ctx: ctx)
        case .pyramid: built = pyramid(last.work, ctx: ctx)
        }

        if input.allowWarmups, cls == .heavyCompound, style != .pyramid {
            built.sets = warmups(forTop: built.sets.map(\.weight).max() ?? 0, ctx: ctx) + built.sets
        }

        var action = built.action
        switch mode {
        case .reduce: action += input.feedback == .tooHard ? " (felt too hard)" : " (low energy)"
        case .holdRepeat:
            action += regressed ? " (down vs previous session)" : " (low energy)"
        case .normal: break
        }
        let lastText = last.work.map(\.text).joined(separator: ", ")
        let rationale = "Last: \(lastText) → \(action)"
        return ProgressionResult(sets: built.sets, rationale: rationale, style: style, repRange: range, trend: trend)
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

    // MARK: - Straight sets

    private static func upperMedian(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// Straight working sets: one load, double progression per set.
    private static func straight(_ working: [HistorySet], count: Int, ctx: Ctx) -> (sets: [ProgressionSet], action: String) {
        let w0 = upperMedian(working.map(\.weight))
        // Reps expressed at the working weight, so a 180×5 next to 185s is just 5 reps, while a
        // set at a very different weight is converted through e1RM.
        let norm: [Int] = working.map { s in
            if abs(s.weight - w0) / w0 <= 0.1 { return s.reps }
            let equivalent = (s.e1RM / w0 - 1) * 30
            return max(1, Int(equivalent.rounded()))
        }
        var reps = Array(norm.prefix(count))
        var weights = Array(working.map(\.weight).prefix(count))
        while reps.count < count { reps.append(reps.last ?? ctx.range.lower); weights.append(weights.last ?? w0) }
        let upper = ctx.range.upper

        var weight = w0
        var action: String
        switch ctx.mode {
        case .reduce:
            var w = ExerciseTraits.floorStep(w0 * 0.95, step: ctx.step)
            if w >= w0 { w = max(ctx.step, w0 - ctx.step) }
            weight = w
            reps = reps.map { min($0, upper) }
            action = "drop about 5% to \(g(w))"
        case .holdRepeat:
            reps = reps.map { min($0, upper) }
            action = "hold \(g(w0)), repeat reps \(reps.map(String.init).joined(separator: "/"))"
        case .normal:
            let allTop = norm.allSatisfy { $0 >= upper } && working.allSatisfy { ($0.rir ?? 0) <= 2 }
            let raised = w0 + ctx.inc
            let allowedByBest = ctx.best.map { raised <= $0.weight + ctx.inc } ?? true
            if (allTop || ctx.tooEasy) && allowedByBest {
                weight = raised
                reps = reps.map { _ in ctx.range.lower }
                action = "all sets at top of range → +\(g(ctx.inc)) to \(g(raised)), reps back to \(ctx.range.lower)"
            } else {
                let r0 = reps[0]
                let lead = min(upper, r0 + 1)
                var next = [lead]
                for r in reps.dropFirst() {
                    next.append(r < r0 ? min(upper, r + 1) : min(r, lead))
                }
                reps = next
                action = "hold \(g(w0)), aim for \(reps.map(String.init).joined(separator: "/")) reps"
                if let lighter = weights.firstIndex(where: { $0 < w0 && abs($0 - w0) / w0 <= 0.1 }) {
                    action += ", bring set \(lighter + 1) to \(g(w0))×\(reps[lighter])"
                }
            }
        }
        let sets = zip(reps, rirs(count: count)).map { ProgressionSet(weight: weight, reps: $0, rir: $1, isWarmup: false) }
        return (sets, action)
    }

    /// Early sets RIR 2, last set RIR 1 (a single set gets 2).
    private static func rirs(count: Int) -> [Int] {
        guard count > 1 else { return [2] }
        return (0..<count).map { $0 == count - 1 ? 1 : 2 }
    }

    // MARK: - Drop set

    private static func dropSet(_ working: [HistorySet], ctx: Ctx) -> (sets: [ProgressionSet], action: String) {
        guard working.count >= 2, let lastSet = working.last else { return straight(working, count: defaultWorkingSets, ctx: ctx) }
        let mains = Array(working.dropLast())
        let mainResult = straight(mains, count: max(2, defaultWorkingSets - 1), ctx: ctx)
        let mainWeight = mainResult.sets.first?.weight ?? lastSet.weight
        let ratio = lastSet.weight / upperMedian(mains.map(\.weight))
        var dropWeight = ExerciseTraits.round(mainWeight * ratio, step: ctx.step)
        if dropWeight >= mainWeight { dropWeight = max(ctx.step, mainWeight - ctx.step) }
        let dropReps = ctx.mode == .normal ? min(lastSet.reps + 1, 20) : lastSet.reps
        var sets = mainResult.sets
        sets.append(ProgressionSet(weight: dropWeight, reps: min(dropReps, 20), rir: 1, isWarmup: false))
        // Mains keep RIR 2; the drop is the hard set.
        for i in 0..<(sets.count - 1) { sets[i].rir = 2 }
        return (sets, "\(mainResult.action); keep the drop set \(g(dropWeight))×\(sets[sets.count - 1].reps)")
    }

    // MARK: - Top set + back-offs

    /// Progression for a single heavy "top" set that does not follow the range logic of the others.
    private static func progressTop(_ top: HistorySet, ctx: Ctx) -> (weight: Double, reps: Int, text: String) {
        switch ctx.mode {
        case .reduce:
            var w = ExerciseTraits.floorStep(top.weight * 0.95, step: ctx.step)
            if w >= top.weight { w = max(ctx.step, top.weight - ctx.step) }
            return (w, top.reps, "top set down about 5% to \(g(w))")
        case .holdRepeat:
            return (top.weight, top.reps, "hold top set \(g(top.weight))×\(top.reps)")
        case .normal:
            let raised = top.weight + ctx.inc
            let allowed = ctx.best.map { raised <= $0.weight + ctx.inc } ?? true
            if top.reps < ctx.range.lower {
                // Heavy single/double: add load only when it was not a grind.
                if ((top.rir ?? 2) >= 2 || ctx.tooEasy) && allowed {
                    return (raised, top.reps, "top set +\(g(ctx.inc)) to \(g(raised))×\(top.reps)")
                }
                return (top.weight, top.reps, "repeat top set \(g(top.weight))×\(top.reps)")
            }
            if (top.reps >= ctx.range.upper && (top.rir ?? 0) <= 2 || ctx.tooEasy) && allowed {
                return (raised, ctx.range.lower, "top set +\(g(ctx.inc)) to \(g(raised))×\(ctx.range.lower)")
            }
            let reps = min(ctx.range.upper, top.reps + 1)
            return (top.weight, reps, "top set \(g(top.weight))×\(reps)")
        }
    }

    private static func topSetBackoff(_ working: [HistorySet], ctx: Ctx) -> (sets: [ProgressionSet], action: String) {
        guard let top = working.first, working.count >= 2 else { return straight(working, count: defaultWorkingSets, ctx: ctx) }
        let newTop = progressTop(top, ctx: ctx)
        var backs = Array(working.dropFirst().prefix(defaultWorkingSets - 1))
        while backs.count < defaultWorkingSets - 1, let l = backs.last { backs.append(l) }
        var sets = [ProgressionSet(weight: newTop.weight, reps: newTop.reps, rir: 1, isWarmup: false)]
        for b in backs {
            let ratio = b.weight / top.weight
            var w = ExerciseTraits.round(newTop.weight * ratio, step: ctx.step)
            if w >= newTop.weight { w = max(ctx.step, newTop.weight - ctx.step) }
            let reps = ctx.mode == .normal ? min(b.reps + 1, 15) : b.reps
            sets.append(ProgressionSet(weight: w, reps: reps, rir: 2, isWarmup: false))
        }
        return (sets, "\(newTop.text), keep \(sets.count - 1) back-off sets")
    }

    // MARK: - Pyramid

    private static func pyramid(_ working: [HistorySet], ctx: Ctx) -> (sets: [ProgressionSet], action: String) {
        guard let maxWeight = working.map(\.weight).max(),
              let topIndex = working.firstIndex(where: { $0.weight == maxWeight }) else {
            return straight(working, count: defaultWorkingSets, ctx: ctx)
        }
        let top = working[topIndex]
        var ramp = Array(working[..<topIndex])
        var backs = Array(working[(topIndex + 1)...])
        // Cap total sets: drop the earliest ramp sets first, then the last back-offs.
        while ramp.count + 1 + backs.count > maxPyramidSets {
            if ramp.count > 2 { ramp.removeFirst() }
            else if !backs.isEmpty { backs.removeLast() }
            else { ramp.removeFirst() }
        }
        let newTop = progressTop(top, ctx: ctx)
        var sets: [ProgressionSet] = []
        for r in ramp {
            var w = r.weight
            if ctx.mode == .reduce { w = ExerciseTraits.floorStep(w * 0.95, step: ctx.step) }
            w = min(ExerciseTraits.round(w, step: ctx.step), max(ctx.step, newTop.weight - ctx.step))
            sets.append(ProgressionSet(weight: w, reps: r.reps, rir: 3, isWarmup: false))
        }
        sets.append(ProgressionSet(weight: newTop.weight, reps: newTop.reps, rir: 1, isWarmup: false))
        for b in backs {
            var w = b.weight
            if ctx.mode == .reduce { w = ExerciseTraits.floorStep(w * 0.95, step: ctx.step) }
            w = min(ExerciseTraits.round(w, step: ctx.step), max(ctx.step, newTop.weight - ctx.step))
            let reps = ctx.mode == .normal ? min(ctx.range.upper, b.reps + 1) : b.reps
            sets.append(ProgressionSet(weight: w, reps: max(reps, b.reps), rir: 2, isWarmup: false))
        }
        return (sets, "keep the pyramid (\(sets.count) sets): \(newTop.text)")
    }

    // MARK: - Warm-ups

    /// One or two ramp sets at roughly 55% and 75% of the working weight (RIR 5 and 4).
    private static func warmups(forTop top: Double, ctx: Ctx) -> [ProgressionSet] {
        guard top > 0 else { return [] }
        var out: [ProgressionSet] = []
        if top < 100 {
            let w = ExerciseTraits.round(top * 0.6, step: ctx.step)
            if w < top { out.append(ProgressionSet(weight: w, reps: 8, rir: 5, isWarmup: true)) }
            return out
        }
        let w1 = ExerciseTraits.round(top * 0.55, step: ctx.step)
        let w2 = ExerciseTraits.round(top * 0.75, step: ctx.step)
        if w1 < w2 { out.append(ProgressionSet(weight: w1, reps: 8, rir: 5, isWarmup: true)) }
        if w2 < top { out.append(ProgressionSet(weight: w2, reps: 5, rir: 4, isWarmup: true)) }
        return out
    }

    private static func g(_ value: Double) -> String { String(format: "%g", value) }
}
