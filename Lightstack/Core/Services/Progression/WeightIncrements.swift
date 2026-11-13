import Foundation

/// The weights an exercise can actually be loaded with, learned from what the athlete has logged.
/// A cable stack that only ever shows 50 and 57.5 has no 52.5; a Smith bench that shows 175, 180, 185
/// moves in fives. Pure and deterministic.
///
/// Inference needs evidence: at least 3 distinct logged weights whose gaps agree on one step. With less,
/// the exercise falls back to the class default (`ExerciseTraits.roundingStep`), exactly as before.
struct WeightIncrements: Equatable {

    enum Direction: Equatable { case nearest, down, up }

    /// Distinct logged weights, ascending, near-duplicates (within `noise`) merged.
    let anchors: [Double]
    /// The step inferred from the anchors; nil when the history does not support one.
    let inferredStep: Double?
    /// The class default step (2.5 or 5), used when nothing is inferred.
    let fallbackStep: Double

    /// Weights closer than this are one weight (a 57 logged next to 57.5 is noise).
    static let noise = 0.5
    /// Fewest distinct weights before an inferred step is trusted.
    static let minDistinctWeights = 3
    /// An inferred step may be at most this many class steps wide (2.5 -> 7.5, 5 -> 15).
    static let maxStepMultiple = 3.0
    /// Smallest step ever inferred (microplates stop here).
    static let minStep = 1.25

    // MARK: - Building

    init(weights: [Double], fallbackStep: Double, plateLoaded: Bool = false) {
        self.fallbackStep = fallbackStep
        let clean = Self.cluster(weights.filter { $0 > 0 })
        anchors = clean
        var step = Self.infer(clean)
        // Wider than a few class steps is more likely a coincidence of the loads chosen (140, 160, 180 on a stack that
        // moves in fives) than a real ladder: do not trust it.
        if let s = step, s > Self.maxStepMultiple * fallbackStep + 0.001 { step = nil }
        // Plate-loaded bars take any plate combination: only a FINER step than the class default is believable.
        if plateLoaded, let s = step, s > fallbackStep + 0.001 { step = nil }
        inferredStep = step
    }

    /// From every set ever logged for the lift (warm-ups included: they sit on the same stack).
    init(name: String, sessions: [HistorySession]) {
        self.init(weights: sessions.flatMap { $0.sets.map(\.weight) },
                  fallbackStep: ExerciseTraits.roundingStep(name),
                  plateLoaded: ExerciseTraits.isPlateLoaded(name))
    }

    /// No history: the class default only.
    static func fallback(for name: String) -> WeightIncrements {
        WeightIncrements(weights: [], fallbackStep: ExerciseTraits.roundingStep(name))
    }

    /// The lift's history merged across name variants, all-time (as far as the history index reaches).
    static func learned(name: String, group: ExerciseHistoryGroup?) -> WeightIncrements {
        guard let group else { return fallback(for: name) }
        return WeightIncrements(name: name, sessions: group.sessions)
    }

    // MARK: - Reading

    var isConfident: Bool { inferredStep != nil }

    /// The step in use: the inferred one, else the class default.
    var step: Double { inferredStep ?? fallbackStep }

    /// The smallest sensible load increase (one rung).
    var increment: Double { step }

    /// Where the ladder is anchored: a logged weight when confident, else zero.
    private var origin: Double {
        guard inferredStep != nil, let first = anchors.first else { return 0 }
        return first
    }

    /// True when `weight` is a rung of the ladder (always true for the class default's multiples when unconfident).
    func isOnLadder(_ weight: Double) -> Bool {
        let units = (weight - origin) / step
        return abs(units - units.rounded()) * step <= Self.noise
    }

    /// A weight on the ladder. Never below one step.
    func snap(_ weight: Double, direction: Direction = .nearest) -> Double {
        guard weight > 0 else { return step }
        let units = (weight - origin) / step
        let k: Double
        switch direction {
        // Halves round up on both sides of the anchor (92.5 on a 5 ladder is 95, as plain rounding always gave).
        case .nearest: k = (units + 0.5 + 1e-9).rounded(.down)
        // 1e-6 keeps an already-on-ladder weight where it is despite floating point noise.
        case .down: k = (units + 1e-6).rounded(.down)
        case .up: k = (units - 1e-6).rounded(.up)
        }
        var result = origin + k * step
        if result < step {
            // Below the first usable rung: the lowest rung that is at least one step.
            let kMin = ((step - origin) / step - 1e-6).rounded(.up)
            result = origin + kMin * step
        }
        return Self.tidy(result)
    }

    /// The next rung above `weight` (strictly higher).
    func stepUp(from weight: Double) -> Double {
        let up = snap(weight, direction: .up)
        return up > weight + 0.001 ? up : Self.tidy(up + step)
    }

    /// The next rung below `weight` (strictly lower, never under one step).
    func stepDown(from weight: Double) -> Double {
        let down = snap(weight, direction: .down)
        let lower = down < weight - 0.001 ? down : Self.tidy(down - step)
        return max(lower, step)
    }

    /// The rung at or below `weight` that is not above the lift's own weight: "the nearest lower weight available".
    func nearestBelow(_ weight: Double) -> Double { snap(weight, direction: .down) }

    // MARK: - Inference

    /// Distinct weights, ascending. Weights within `noise` of each other are one weight: the one logged most often,
    /// then the one nearest a multiple of 2.5 (57.5 beats a stray 57).
    static func cluster(_ weights: [Double]) -> [Double] {
        var groups: [[Double]] = []
        for w in weights.sorted() {
            if let last = groups.last?.last, w - last <= noise { groups[groups.count - 1].append(w) } else { groups.append([w]) }
        }
        return groups.compactMap { group in
            let counts = Dictionary(grouping: group, by: { $0 }).mapValues(\.count)
            func roundness(_ v: Double) -> Double { abs(v / 2.5 - (v / 2.5).rounded()) }
            return counts.keys.min { a, b in
                let ca = counts[a] ?? 0, cb = counts[b] ?? 0
                if ca != cb { return ca > cb }
                return roundness(a) != roundness(b) ? roundness(a) < roundness(b) : a < b
            }
        }
    }

    /// The largest step that explains every gap (within `noise`); a single stray weight may be ignored when
    /// there are enough weights to spare. nil with fewer than `minDistinctWeights`.
    static func infer(_ weights: [Double]) -> Double? {
        guard weights.count >= minDistinctWeights else { return nil }
        let full = step(for: weights)
        if let full, full >= 2.5 - 0.001 { return full }
        // A one-off outlier (a mis-typed weight) can force a tiny step: try without each weight in turn.
        guard weights.count >= minDistinctWeights + 2 else { return full }
        var best = full
        for i in weights.indices {
            var trimmed = weights
            trimmed.remove(at: i)
            if let s = step(for: trimmed), s > (best ?? 0) { best = s }
        }
        return best
    }

    private static func step(for weights: [Double]) -> Double? {
        let gaps = zip(weights.dropFirst(), weights).map { $0 - $1 }.filter { $0 > noise }
        guard let smallest = gaps.min() else { return nil }
        // Try the smallest gap, then fractions of it (a 7.5 and a 5 gap share a 2.5 step).
        for divisor in 1...4 {
            let candidate = smallest / Double(divisor)
            guard candidate >= minStep - 0.001 else { break }
            let fits = gaps.allSatisfy { gap in
                let units = gap / candidate
                return abs(units - units.rounded()) * candidate <= noise
            }
            if fits { return tidy(candidate) }
        }
        return nil
    }

    /// 57.50000001 -> 57.5.
    private static func tidy(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}

extension ExerciseTraits {

    /// Barbell and Smith / plate-loaded machines take any plate combination, so their weights are not a fixed ladder.
    /// A cable, dumbbell or selectorized machine is.
    static func isPlateLoaded(_ name: String) -> Bool {
        let n = name.lowercased()
        if n.contains("cable") || n.contains("dumbbell") || n.contains("dumbell") || n.contains("pec deck") { return false }
        if n.split(whereSeparator: { !$0.isLetter }).contains(where: { $0 == "db" || $0 == "dbs" }) { return false }
        if n.contains("smith") || n.contains("barbell") || n.contains("leg press") || n.contains("hack")
            || n.contains("plate") || n.contains("ez bar") || n.contains("ez-bar") || n.contains("trap bar") { return true }
        // A bare "Bench Press" / "Squat" / "Deadlift" is a bar; a "... Machine" is not unless named above.
        if n.contains("machine") { return false }
        return ["bench", "squat", "deadlift", "overhead press", "military", "row"].contains { n.contains($0) }
    }
}

/// No big rep jumps at a weight the athlete just did. At a weight within one ladder step of a set from the lift's
/// LAST session, target reps are at most that set's reps + 2, and + 1 when that set was hard (RIR 1 or less) or the
/// target asks for more reserve than the athlete had.
enum RepJumpRule {

    /// The most reps a set at `weight` / `rir` may carry, or nil when the last session had nothing near that weight.
    static func maxReps(weight: Double, rir: Int, last: [HistorySet], ladder: WeightIncrements) -> (reps: Int, basis: HistorySet)? {
        let near = last.filter { $0.reps > 0 && abs($0.weight - weight) <= ladder.step + 0.01 }
        // The set closest in weight; the one with more reps on a tie.
        guard let basis = near.min(by: { a, b in
            let da = abs(a.weight - weight), db = abs(b.weight - weight)
            return abs(da - db) > 0.001 ? da < db : a.reps > b.reps
        }) else { return nil }
        var allowed = 2
        if let lastRir = basis.rir {
            if lastRir <= 1 || rir > lastRir { allowed = 1 }
        }
        return (basis.reps + allowed, basis)
    }

    /// Applies the rule to every working set (warm-ups are exempt).
    static func apply(_ sets: [ProgressionSet], last: [HistorySet], ladder: WeightIncrements) -> (sets: [ProgressionSet], notes: [String]) {
        var out = sets
        var notes: [String] = []
        for i in out.indices where !out[i].isWarmup {
            guard let cap = maxReps(weight: out[i].weight, rir: out[i].rir, last: last, ladder: ladder),
                  out[i].reps > cap.reps else { continue }
            notes.append("\(out[i].role.label.lowercased()) reps held at \(cap.reps): last time \(cap.basis.text)")
            out[i].reps = max(1, cap.reps)
        }
        return (out, notes)
    }

    /// For sets that are not `ProgressionSet`s (the coach's own): the cap for one weight / RIR / reps.
    static func capped(reps: Int, weight: Double, rir: Int, last: [HistorySet], ladder: WeightIncrements) -> Int {
        guard let cap = maxReps(weight: weight, rir: rir, last: last, ladder: ladder) else { return reps }
        return min(reps, max(1, cap.reps))
    }
}
