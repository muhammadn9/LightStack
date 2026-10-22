import Foundation

/// Recognises how the athlete usually structures an exercise's sets, so the
/// engine can keep that shape. Pure and deterministic.
enum SetStyleDetector {

    /// Splits a session into (warm-ups, working sets). A set is a warm-up when its RIR is 4+,
    /// or it comes before the heaviest set, is under 70% of it and was not close to failure.
    /// If everything would be a warm-up, everything counts as working.
    static func splitWarmups(_ sets: [HistorySet]) -> (warmups: [HistorySet], working: [HistorySet]) {
        let flags = warmupFlags(sets)
        var warm: [HistorySet] = []
        var work: [HistorySet] = []
        for (s, isWarm) in zip(sets, flags) { if isWarm { warm.append(s) } else { work.append(s) } }
        if work.isEmpty { return ([], sets) }
        return (warm, work)
    }

    /// Per-set warm-up flags (same rules as `splitWarmups`, before its all-warm-up fallback).
    static func warmupFlags(_ sets: [HistorySet]) -> [Bool] {
        guard let maxWeight = sets.map(\.weight).max(),
              let topIndex = sets.firstIndex(where: { $0.weight == maxWeight }) else { return sets.map { _ in false } }
        return sets.enumerated().map { i, s in
            let lightEarly = i < topIndex && s.weight < 0.7 * maxWeight && (s.rir == nil || (s.rir ?? 0) >= 3)
            return (s.rir ?? 0) >= 4 || lightEarly
        }
    }

    /// Style of one session's working sets.
    static func classify(_ session: HistorySession) -> SetStyle {
        classify(working: splitWarmups(session.sets).working)
    }

    static func classify(working w: [HistorySet]) -> SetStyle {
        guard w.count >= 2, let maxWeight = w.map(\.weight).max(),
              let topIndex = w.firstIndex(where: { $0.weight == maxWeight }) else { return .straightSets }

        // Pyramid: at least two ascending sets before the heaviest, which is 10%+ above the first.
        if topIndex >= 2, w[0].weight * 1.1 <= maxWeight {
            let ascending = (1...topIndex).allSatisfy { w[$0].weight >= w[$0 - 1].weight }
            if ascending { return .pyramid }
        }
        // Top set first, then two or more clearly lighter sets with more reps.
        if topIndex == 0, w.count >= 3 {
            let backoffs = w.dropFirst()
            if backoffs.allSatisfy({ $0.weight <= 0.93 * maxWeight && $0.reps > w[0].reps }) { return .topSetBackoff }
        }
        // Drop set: equal-weight sets, then a notably lighter last set with more reps.
        if let last = w.last {
            let prior = Array(w.dropLast())
            if let priorMax = prior.map(\.weight).max(), let priorMin = prior.map(\.weight).min(),
               priorMin >= 0.95 * priorMax,
               last.weight <= 0.9 * priorMax,
               last.reps > (prior.last?.reps ?? 0) {
                return .dropSet
            }
        }
        return .straightSets
    }

    /// Style across the last 2-3 sessions (newest first). Needs at least two sessions that agree;
    /// anything less consistent is straight sets.
    static func detect(sessions: [HistorySession]) -> SetStyle {
        let styles = sessions.prefix(3).map { classify($0) }
        guard styles.count >= 2 else { return .straightSets }
        var counts: [SetStyle: Int] = [:]
        styles.forEach { counts[$0, default: 0] += 1 }
        // Order of preference breaks (unlikely) ties deterministically.
        let order: [SetStyle] = [.straightSets, .pyramid, .topSetBackoff, .dropSet]
        var best = SetStyle.straightSets
        for style in order where (counts[style] ?? 0) > (counts[best] ?? 0) { best = style }
        return (counts[best] ?? 0) >= 2 ? best : .straightSets
    }
}
