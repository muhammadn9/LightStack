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
    /// Weights above best × (1 + this) are clamped down.
    static let weightTolerance = 0.05

    static func apply(
        name: String,
        targets: [SetTarget],
        allowWarmups: Bool,
        bestWeight: Double?
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

        // 3. Working set count 2...5.
        var working = rows.filter { !$0.warm }
        if working.count > maxWorkingSets {
            let extra = working.count - maxWorkingSets
            var toDrop = extra
            // Drop from the end.
            for i in rows.indices.reversed() where !rows[i].warm && toDrop > 0 {
                rows.remove(at: i)
                toDrop -= 1
            }
            report.reasons.append("Capped at \(maxWorkingSets) working sets")
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

        let result = rows.map { row -> SetTarget in
            var t = row.target
            t.isWarmup = row.warm ? true : t.isWarmup
            return t
        }
        return (report.reasons.isEmpty ? targets : result, report)
    }

    /// Set-count clamp for an exercise that came without per-set targets.
    static func clampedSetCount(_ sets: Int) -> (count: Int, report: GuardrailReport) {
        let clamped = min(maxWorkingSets, max(minWorkingSets, sets))
        var report = GuardrailReport()
        if clamped != sets { report.reasons.append("Set count \(sets) changed to \(clamped)") }
        return (clamped, report)
    }
}
