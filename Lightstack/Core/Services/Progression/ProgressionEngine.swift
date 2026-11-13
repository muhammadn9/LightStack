import Foundation

/// Deterministic progression engine. Given an exercise's logged history it decides the next
/// session's sets in the owner's standard structure. No AI, no randomness, no I/O.
///
/// Main lifts:  [warm-up, first heavy compound only] -> Set 1 (~80% of top) -> ONE top set -> a back-off
///              (~92% of top) for hypertrophy at energy 5+, otherwise a straight set.
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
    /// Hypertrophy gets a back-off only at this energy or above.
    static let backoffMinEnergy = 5

    private static let ladder = [
        RepRange(lower: 5, upper: 8), RepRange(lower: 6, upper: 10),
        RepRange(lower: 8, upper: 12), RepRange(lower: 10, upper: 15)
    ]

    /// Days since the lift was last done after which the load is held (no increase).
    static let holdAfterDays = 14
    /// Days after which the load is reduced by `layoffReductionPercent`.
    static let layoffAfterDays = 28
    static let layoffReductionPercent = 7.5
    /// A top set may rise at most this much over the most recent session's top (or one increment).
    static let topWeightTolerance = 0.05

    /// The same lift trained less than this many hours ago: no progress, and a main lift comes down a notch.
    static let sameLiftRecentHours = 24.0
    /// A muscle with 2+ hard sets this recently counts as just trained (the session-level warning and the engine's hold).
    static let muscleRecentHours = 20.0
    static let muscleRecentMinHardSets = 2
    /// How much a main lift comes down when it (or its muscle) was trained hours ago.
    static let recentReductionPercent = 5.0

    private enum Mode { case reduce, holdRepeat, layoffReduce, normal }

    private struct Ctx {
        var name: String
        var cls: ExerciseClass
        /// The weights this lift can actually be loaded with (learned from history, else the class default).
        var ladder: WeightIncrements
        var step: Double { ladder.step }
        var inc: Double { ladder.increment }
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
        let ladder = input.increments ?? WeightIncrements(name: input.name, sessions: input.sessions)
        let working = sessions.map { HistorySession(date: $0.session.date, sets: $0.work) }
        let range = topRange(cls: cls, focus: input.focus, sessions: working)
        let style = SetStyleDetector.detect(sessions: working)
        let full = sessions.map(\.session)
        let trend = self.trend(full)

        let regressed = full.count >= 2 && strength(full[0]) < 0.95 * strength(full[1])
        var mode: Mode
        if input.feedback == .tooHard || input.energy <= 2 { mode = .reduce }
        else if regressed || input.energy == 3 { mode = .holdRepeat }
        else { mode = .normal }

        // Skipped last time or a long gap: hold, or after a long layoff come back lighter.
        let daysSince = input.now.map { max(0, Int($0.timeIntervalSince(last.session.date) / 86_400)) }
        let skippedLast = input.lastSameTypeSessionDate.map { $0 > last.session.date.addingTimeInterval(3600) } ?? false
        var pauseNote: String?
        if let days = daysSince, days > layoffAfterDays {
            mode = .layoffReduce
            pauseNote = "last done \(days) days ago, down about \(g(layoffReductionPercent))% to rebuild"
        } else if mode != .reduce, let days = daysSince, days > holdAfterDays {
            mode = .holdRepeat
            pauseNote = "last done \(days) days ago, no load increase"
        } else if mode != .reduce, skippedLast {
            mode = .holdRepeat
            pauseNote = "skipped in the last session, no load increase"
        }
        // Trained this lift (or its muscle) hours ago, or running on empty: never progress, and a main lift also
        // comes down a notch when it was trained very recently.
        let hoursSinceLast = input.now.map { max(0, $0.timeIntervalSince(last.session.date)) / 3600 }
        let liftVeryRecent = (hoursSinceLast ?? .infinity) < sameLiftRecentHours
        let noProgress = liftVeryRecent || input.muscleVeryRecent || input.fuelLow
        var noProgressNote: String?
        if noProgress {
            if mode == .normal { mode = .holdRepeat }
            if liftVeryRecent, let h = hoursSinceLast {
                noProgressNote = "trained \(hoursText(h)) ago"
            } else if input.muscleVeryRecent {
                noProgressNote = "muscle trained in the last \(Int(muscleRecentHours)) h"
            } else if let why = input.fuelReason {
                noProgressNote = "low fuel: \(why)"
            } else {
                noProgressNote = "low fuel"
            }
            if pauseNote == nil { pauseNote = "\(noProgressNote ?? ""), no load or rep increase" }
        }
        let ctx = Ctx(name: input.name, cls: cls, ladder: ladder,
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
        chosen.weight = ladder.snap(chosen.weight)

        // Never progress when the lift or its muscle was trained hours ago, or fuel is low: weight and reps stay
        // at or under the last top set. A main lift trained very recently also comes down about 5%.
        let veryRecent = liftVeryRecent || input.muscleVeryRecent
        if noProgress, mode != .reduce, mode != .layoffReduce {
            if chosen.weight > lastTop.weight + 0.001 {
                chosen = (lastTop.weight, lastTop.reps, "hold \(g(lastTop.weight))×\(lastTop.reps)")
            } else if abs(chosen.weight - lastTop.weight) <= 0.001, chosen.reps > lastTop.reps {
                chosen = (lastTop.weight, lastTop.reps, "hold \(g(lastTop.weight))×\(lastTop.reps)")
            }
            if veryRecent, cls != .isolation {
                let lighter = ladder.snap(lastTop.weight * (1 - recentReductionPercent / 100), direction: .down)
                if lighter < chosen.weight - 0.001 {
                    chosen = (lighter, min(chosen.reps, lastTop.reps),
                              "top set down about \(g(recentReductionPercent))% to \(g(lighter))")
                }
            }
        }

        // Recency rule: muscles trained hard in the last 48 h hold their load at RIR 2.
        var recency = false
        if input.recentlyTrained || veryRecent {
            recency = true
            if chosen.weight > lastTop.weight {
                chosen = (lastTop.weight, lastTop.reps, "hold \(g(lastTop.weight))×\(lastTop.reps)")
            }
            chosen.text += ", RIR 2 (trained recently)"
        }

        // 2. The standard structure around it.
        var built: [ProgressionSet]
        if cls == .isolation {
            built = isolationSets(top: chosen, recency: recency, ctx: ctx, restPreference: input.restPreference)
        } else {
            let warm = input.allowWarmups && userWarmsUp(sessions.prefix(3).map(\.warm))
            built = mainSets(top: chosen, recency: recency, warmup: warm, energy: input.energy, ctx: ctx,
                             restPreference: input.restPreference)
        }
        // No rep jumps at a weight the athlete just did: at most +2 reps (+1 after a hard set or at a higher RIR).
        let capped = RepJumpRule.apply(built, last: last.work, ladder: ladder)
        built = capped.sets

        var action = chosen.text
        switch mode {
        case .reduce: action += input.feedback == .tooHard ? " (felt too hard)" : " (low energy)"
        case .holdRepeat: action += pauseNote.map { " (\($0))" } ?? (regressed ? " (down vs previous session)" : " (low energy)")
        case .layoffReduce: action += " (\(pauseNote ?? "long layoff"))"
        case .normal: break
        }
        if usedTarget { action += " (from last review)" }
        let lastText = last.work.map(\.text).joined(separator: ", ")
        let structure = built.filter { !$0.isWarmup }.map { "\($0.role.label) \(g($0.weight))×\($0.reps)" }.joined(separator: ", ")
        var rationale = "Last: \(lastText) → \(action). \(structure)"
        if !capped.notes.isEmpty { rationale += " (" + capped.notes.joined(separator: "; ") + ")" }
        var result = ProgressionResult(sets: built, rationale: rationale, style: style, repRange: range, trend: trend)
        result.usedNextTarget = usedTarget
        result.recencyApplied = recency
        result.noProgressReason = noProgress ? noProgressNote : nil
        result.repCaps = capped.notes
        return result
    }

    /// Where the next top set would go after this one (double progression), for review defaults.
    static func nextTopTarget(name: String, after top: HistorySet, focus: CoachFocus = .hypertrophy,
                              best: HistorySet? = nil, history: [HistorySession] = [],
                              increments: WeightIncrements? = nil) -> (weight: Double, reps: Int) {
        let cls = ExerciseTraits.classify(name)
        let sessions = history.isEmpty ? [HistorySession(date: Date(), sets: [top])] : history
        let ladder = increments ?? (history.isEmpty ? WeightIncrements.fallback(for: name)
                                                    : WeightIncrements(name: name, sessions: history))
        let ctx = Ctx(name: name, cls: cls, ladder: ladder,
                      range: topRange(cls: cls, focus: focus, sessions: sessions),
                      mode: .normal, tooEasy: false, best: best, focus: focus)
        let next = progressTop(top, ctx: ctx)
        return (ladder.snap(next.weight), next.reps)
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
        let ceiling = max(lastTop.weight * (1 + topWeightTolerance), lastTop.weight + ctx.inc)
        guard t.weight >= lastTop.weight * 0.80, t.weight <= ceiling else { return false }
        if let b = ctx.best, t.weight > b.weight + 2 * ctx.inc { return false }
        if t.weight >= lastTop.weight * 0.99, t.reps > lastTop.reps + 3 { return false }
        return true
    }

    /// The review's target, still bent by energy and feedback for today.
    private static func fromTarget(_ t: NextTarget, lastTop: HistorySet, ctx: Ctx) -> (weight: Double, reps: Int, text: String) {
        switch ctx.mode {
        case .reduce:
            let w = reduced(t.weight, percent: 5, ctx: ctx)
            return (w, t.reps, "review target \(g(t.weight))×\(t.reps), down about 5% to \(g(w))")
        case .layoffReduce:
            let w = layoffWeight(min(t.weight, lastTop.weight), ctx: ctx)
            return (w, t.reps, "review target \(g(t.weight))×\(t.reps), down about \(g(layoffReductionPercent))% to \(g(w))")
        case .holdRepeat:
            if t.weight > lastTop.weight {
                return (lastTop.weight, lastTop.reps, "hold top set \(g(lastTop.weight))×\(lastTop.reps)")
            }
            return (t.weight, t.reps, "top set \(g(t.weight))×\(t.reps)")
        case .normal:
            return (t.weight, t.reps, "top set \(g(t.weight))×\(t.reps)")
        }
    }

    /// The weight after a long layoff: about 7.5% lighter, rounded down to the plate step.
    private static func layoffWeight(_ weight: Double, ctx: Ctx) -> Double {
        reduced(weight, percent: layoffReductionPercent, ctx: ctx)
    }

    /// `weight` lowered by about `percent`, on the lift's ladder. Rounds down; when the ladder is so coarse that the
    /// next rung down is more than twice the intended cut, the nearer rung is used instead, and if that is the same
    /// weight the weight is held (never a weight the lift cannot be loaded to).
    private static func reduced(_ weight: Double, percent: Double, ctx: Ctx) -> Double {
        let target = weight * (1 - percent / 100)
        var down = ctx.ladder.snap(target, direction: .down)
        if down >= weight - 0.001 { down = ctx.ladder.stepDown(from: weight) }
        let intended = weight - target
        if weight - down > 2 * intended {
            let up = ctx.ladder.snap(target, direction: .up)
            if up < weight - 0.001 { return up }
            return weight
        }
        return down
    }

    /// Double progression for the top set.
    private static func progressTop(_ top: HistorySet, ctx: Ctx) -> (weight: Double, reps: Int, text: String) {
        switch ctx.mode {
        case .reduce:
            let w = reduced(top.weight, percent: 5, ctx: ctx)
            return (w, top.reps, "top set down about 5% to \(g(w))")
        case .layoffReduce:
            let w = layoffWeight(top.weight, ctx: ctx)
            return (w, top.reps, "top set down about \(g(layoffReductionPercent))% to \(g(w))")
        case .holdRepeat:
            return (top.weight, top.reps, "hold top set \(g(top.weight))×\(top.reps)")
        case .normal:
            if ctx.focus == .maintenance {
                return (top.weight, top.reps, "maintenance: hold top set \(g(top.weight))×\(top.reps)")
            }
            let raised = ctx.ladder.stepUp(from: top.weight)
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
                                 energy: Int, ctx: Ctx, restPreference: Int) -> [ProgressionSet] {
        let strength = ctx.focus == .strength
        let steady = recency || ctx.mode != .normal
        let topRir = steady ? 2 : 1
        var sets: [ProgressionSet] = []

        let rampWeight = rampWeight(forTop: top.weight, ladder: ctx.ladder)
        // Set 1 is lighter, so it gets more reps than the top set (hypertrophy ~10-12, strength up to 8).
        let rampReps = strength ? max(top.reps, min(8, top.reps + 2)) : max(top.reps, min(12, max(10, top.reps + 3)))

        if warmup {
            var w = ctx.ladder.snap(top.weight * 0.5)
            if w >= rampWeight { w = ctx.ladder.snap(rampWeight * 0.6) }
            if w < rampWeight {
                sets.append(ProgressionSet(weight: w, reps: 10, rir: 5, role: .warmup, restSeconds: warmupRest))
            }
        }
        sets.append(ProgressionSet(weight: rampWeight, reps: rampReps, rir: 2, role: .ramp, restSeconds: rampRest))
        sets.append(ProgressionSet(weight: top.weight, reps: top.reps, rir: topRir, role: .top,
                                   restSeconds: strength ? strengthTopRest : topRest))
        guard !recency else { return sets }

        if strength {
            // Strength focus repeats the top weight once as a straight set (no back-off).
            sets.append(ProgressionSet(weight: top.weight, reps: max(ctx.range.lower, top.reps - 1), rir: 1,
                                       role: .straight, restSeconds: strengthTopRest))
            return sets
        }
        var weight = ctx.ladder.snap(top.weight * backoffShare)
        if weight >= top.weight { weight = ctx.ladder.stepDown(from: top.weight) }
        let reps = max(top.reps, min(ctx.range.upper, top.reps + 1))
        // A back-off only for hypertrophy with energy to spare; otherwise a plain straight set.
        let role: SetRole = energy >= backoffMinEnergy ? .backoff : .straight
        sets.append(ProgressionSet(weight: weight, reps: reps, rir: 2, role: role,
                                   restSeconds: max(backoffRest, restPreference)))
        return sets
    }

    /// Set 1: about 80% of the top set, kept inside 75-85% when the plate step allows.
    private static func rampWeight(forTop top: Double, ladder: WeightIncrements) -> Double {
        let target = top * rampShare
        let down = ladder.snap(target, direction: .down)
        let up = ladder.stepUp(from: down)
        let candidates = [down, up].filter { $0 >= top * 0.75 && $0 <= top * 0.85 && $0 < top }
        if let best = candidates.min(by: { abs($0 - target) < abs($1 - target) }) { return best }
        let rounded = ladder.snap(target)
        return rounded < top ? rounded : ladder.stepDown(from: top)
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

    private static func hoursText(_ hours: Double) -> String { RecencyWarning.hoursPhrase(hours) }
}

// MARK: - Goal assessment

/// Is a lift goal ("225x1 bench") realistic, and what is the path? Deterministic, from the lift's own
/// recent top sets. The chat hands these facts to the AI as a hidden "APP CHECK" line.
enum GoalAssessor {

    /// A session's best working set for the lift.
    struct Point: Equatable {
        var date: Date
        var weight: Double
        var reps: Int

        /// The app's one e1RM formula (`OneRepMax`).
        var e1RM: Double { OneRepMax.estimate(weight: weight, reps: reps) }
        var text: String { "\(String(format: "%g", weight))x\(reps)" }
    }

    enum Verdict: Equatable {
        /// Within `realisticGapPercent` of the current e1RM: attempt it with a warm-up ladder.
        case realisticNow
        /// Up to `blockGapPercent` away: a multi-session block of about this many weeks.
        case block(weeks: Int)
        /// Further away: aim for this weight (at the goal's reps) first.
        case longTerm(intermediateWeight: Double)
    }

    struct LadderStep: Equatable {
        var weight: Double
        var reps: Int
        var isAttempt: Bool
        var text: String { "\(String(format: "%g", weight))x\(reps)" }
    }

    struct Assessment: Equatable {
        var exercise: String
        var targetWeight: Double
        var targetReps: Int
        var best: Point
        var currentE1RM: Double
        /// e1RM change per week over the recent window (0 when there is not enough data).
        var weeklySlope: Double
        var spanWeeks: Int
        /// True when nothing was logged inside the recent window.
        var stale: Bool
        var targetE1RM: Double
        /// How far the target e1RM is above the current one, in percent (negative when already past it).
        var gapPercent: Double
        var verdict: Verdict
        var ladder: [LadderStep]
    }

    static let realisticGapPercent = 3.0
    static let blockGapPercent = 10.0
    static let slopeWindowDays = 42
    /// Weekly gain assumed (share of the current e1RM) when the recent slope is flat or negative.
    static let assumedWeeklyGainShare = 0.005
    static let maxBlockWeeks = 16
    /// An intermediate goal sits this far above the current e1RM.
    static let intermediateShare = 1.05
    /// Sets above this many reps say too little about a max.
    static let maxUsefulReps = 10

    // MARK: History

    /// The best working set of each session, oldest first.
    static func topPoints(from sessions: [HistorySession]) -> [Point] {
        sessions.compactMap { session -> Point? in
            let working = SetStyleDetector.splitWarmups(session.sets).working
                .filter { $0.weight > 0 && $0.reps > 0 && $0.reps <= maxUsefulReps }
            guard let top = ProgressionEngine.referenceTop(working) else { return nil }
            return Point(date: session.date, weight: top.weight, reps: top.reps)
        }.sorted { $0.date < $1.date }
    }

    // MARK: Assessment

    /// nil when the lift has no usable history.
    static func assess(exercise: String, targetWeight: Double, targetReps: Int,
                       history: [Point], now: Date = Date(), increments: WeightIncrements? = nil) -> Assessment? {
        guard targetWeight > 0, targetReps > 0 else { return nil }
        let all = history.filter { $0.weight > 0 && $0.reps > 0 && $0.date <= now.addingTimeInterval(86_400) }
            .sorted { $0.date < $1.date }
        guard let newest = all.last else { return nil }

        let cutoff = now.addingTimeInterval(-Double(slopeWindowDays) * 86_400)
        var window = all.filter { $0.date >= cutoff }
        let stale = window.isEmpty
        if stale { window = [newest] }

        // "Now" is the athlete's recent best: the best of the lift's last few sessions, the same value the brief
        // ends its e1RM trend on. (The 42-day window is only for the slope: an old single would inflate "now".)
        guard let best = all.suffix(OneRepMax.recentSessions).max(by: { $0.e1RM < $1.e1RM }) else { return nil }
        let current = best.e1RM

        // One value per day (the day's best), then a least-squares slope in e1RM per week.
        let calendar = Calendar.current
        var perDay: [Date: Double] = [:]
        for point in window {
            let day = calendar.startOfDay(for: point.date)
            perDay[day] = max(perDay[day] ?? 0, point.e1RM)
        }
        let days = perDay.keys.sorted()
        var slope = 0.0
        var spanWeeks = 1
        if let first = days.first, let last = days.last, days.count >= 2 {
            let spanDays = last.timeIntervalSince(first) / 86_400
            spanWeeks = max(1, Int((spanDays / 7).rounded()))
            if spanDays >= 7 {
                let xs = days.map { $0.timeIntervalSince(first) / (7 * 86_400) }
                let ys = days.map { perDay[$0] ?? 0 }
                slope = leastSquaresSlope(xs, ys)
            }
        }

        let targetE1RM = Point(date: now, weight: targetWeight, reps: targetReps).e1RM
        let gap = (targetE1RM - current) / current * 100

        let verdict: Verdict
        if gap <= realisticGapPercent {
            verdict = .realisticNow
        } else if gap <= blockGapPercent {
            let weekly = slope > 0.1 ? slope : current * assumedWeeklyGainShare
            let weeks = Int(((targetE1RM - current) / weekly).rounded(.up))
            verdict = .block(weeks: min(maxBlockWeeks, max(1, weeks)))
        } else {
            verdict = .longTerm(intermediateWeight: intermediateWeight(
                exercise: exercise, current: current, reps: targetReps, targetWeight: targetWeight,
                increments: increments))
        }

        return Assessment(
            exercise: exercise, targetWeight: targetWeight, targetReps: targetReps, best: best,
            currentE1RM: current, weeklySlope: slope, spanWeeks: spanWeeks, stale: stale,
            targetE1RM: targetE1RM, gapPercent: gap, verdict: verdict,
            ladder: ladder(exercise: exercise, weight: targetWeight, reps: targetReps, increments: increments))
    }

    private static func leastSquaresSlope(_ xs: [Double], _ ys: [Double]) -> Double {
        let n = Double(xs.count)
        guard n >= 2 else { return 0 }
        let mx = xs.reduce(0, +) / n
        let my = ys.reduce(0, +) / n
        var num = 0.0
        var den = 0.0
        for (x, y) in zip(xs, ys) {
            num += (x - mx) * (y - my)
            den += (x - mx) * (x - mx)
        }
        return den > 0.0001 ? num / den : 0
    }

    /// The weight at the goal's reps that is about `intermediateShare` above the current e1RM,
    /// rounded to the lift's plate step and always below the final target.
    private static func intermediateWeight(exercise: String, current: Double, reps: Int, targetWeight: Double,
                                           increments: WeightIncrements? = nil) -> Double {
        let ladder = increments ?? WeightIncrements.fallback(for: exercise)
        let raw = OneRepMax.weight(forE1RM: current * intermediateShare, reps: reps)
        var weight = ladder.snap(raw)
        if weight >= targetWeight { weight = ladder.stepDown(from: targetWeight) }
        return weight
    }

    // MARK: Warm-up ladder

    /// The bar (or about 40% of the attempt) for 5, then 60% x3, 75% x2, 85% x1, 92% x1, then the attempt.
    static func ladder(exercise: String, weight: Double, reps: Int, increments: WeightIncrements? = nil) -> [LadderStep] {
        guard weight > 0, reps > 0 else { return [] }
        let rungs = increments ?? WeightIncrements.fallback(for: exercise)
        let name = exercise.lowercased()
        let barbellLift = !name.contains("dumbbell")
            && ["barbell", "bench", "squat", "deadlift", "overhead press"].contains { name.contains($0) }

        var first = rungs.snap(weight * 0.40)
        if barbellLift && first < 45 { first = 45 }
        let plan: [(weight: Double, reps: Int)] = [
            (first, 5),
            (rungs.snap(weight * 0.60), 3),
            (rungs.snap(weight * 0.75), 2),
            (rungs.snap(weight * 0.85), 1),
            (rungs.snap(weight * 0.92), 1)
        ]
        var steps: [LadderStep] = []
        var previous = 0.0
        for entry in plan where entry.weight > previous && entry.weight < weight {
            steps.append(LadderStep(weight: entry.weight, reps: entry.reps, isAttempt: false))
            previous = entry.weight
        }
        steps.append(LadderStep(weight: weight, reps: reps, isAttempt: true))
        return steps
    }

    // MARK: APP CHECK line

    /// The hidden line appended to the athlete's goal message. The AI writes the conversation around it.
    static func appCheckLine(_ a: Assessment) -> String {
        var line = "APP CHECK: \(a.exercise) e1RM \(whole(a.currentE1RM)) (\(a.best.text) \(shortDate(a.best.date)))"
        if a.stale {
            line += ", nothing logged in the last \(slopeWindowDays / 7) wks"
        } else {
            line += ", \(String(format: "%+.1f", a.weeklySlope)) lb/wk over \(a.spanWeeks) wks"
        }
        let target = "\(String(format: "%g", a.targetWeight))x\(a.targetReps)"
        line += "; \(target) = e1RM \(whole(a.targetE1RM)), gap \(max(0, Int(a.gapPercent.rounded())))% → "
        switch a.verdict {
        case .realisticNow:
            line += "within reach now. Warm-up ladder: " + a.ladder.map(\.text).joined(separator: ", ")
                + " (last one is the attempt)"
        case .block(let weeks):
            line += "not this week, ~\(max(1, weeks - 1))-\(weeks + 1) wks"
        case .longTerm(let intermediate):
            line += "far off. Suggest an intermediate goal first: \(String(format: "%g", intermediate))x\(a.targetReps)"
        }
        return line
    }

    /// Used when the lift has no logged history.
    static func noHistoryLine(exercise: String, targetWeight: Double, targetReps: Int) -> String {
        let e1RM = Point(date: Date(), weight: targetWeight, reps: targetReps).e1RM
        return "APP CHECK: no logged \(exercise) sets, so the app cannot judge "
            + "\(String(format: "%g", targetWeight))x\(targetReps) (e1RM \(whole(e1RM))). "
            + "Ask for a recent top set before promising dates."
    }

    private static func whole(_ value: Double) -> String { String(format: "%.0f", value) }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
}
