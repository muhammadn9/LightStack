import Foundation

/// One exercise as logged in the finished session.
struct LoggedExercise: Equatable {
    var name: String
    var muscleGroup: String
    /// In the order they were done (warm-ups included).
    var sets: [HistorySet]
}

/// Prescribed against actual for one exercise, worked out in Swift so the model does not have to.
struct ExerciseAnalysis: Equatable {
    var name: String
    var prescription: ExercisePrescription?
    var actual: [HistorySet]
    var prescribedTop: PrescribedSet?
    var actualTop: HistorySet?
    /// Reps short of the prescribed top set (0 = hit or beat it). A lighter load counts as short.
    var shortBy: Int
    var loadDropped: Bool
    /// Actual minus planned RIR on the top set; negative = harder than planned.
    var rirDelta: Int?
    var outcome: ExerciseOutcome
    /// The previous review of this lift also recorded a miss.
    var repeatedMiss: Bool
    var inSessionReason: String?
    var painOrFormSignal: Bool
    /// The rules' verdict on a miss; nil when nothing was missed.
    var miss: MissAnalysis?
    /// The rules' target for next time.
    var target: NextTarget?
    var note: String

    var isMiss: Bool { miss != nil }
    var harderThanPlanned: Bool { (rirDelta ?? 0) <= -1 }

    /// "Cable row machine: planned W 90x10@5 · TOP 180x6@1 ... | did 160x8@1, 180x5@1 | TOP MISSED by 1 rep ..."
    var promptLine: String {
        let planned = prescription.map { p in
            p.sets.map { "\($0.role.label.lowercased()) \($0.text)" }.joined(separator: ", ")
        } ?? "no prescription"
        let did = actual.map(\.text).joined(separator: ", ")
        var verdict: String
        if prescribedTop == nil { verdict = "outcome \(outcome.rawValue)" }
        else if let top = actualTop, shortBy > 0 {
            verdict = loadDropped
                ? "TOP SET MISSED: lifted \(top.text) vs \(prescribedTop?.text ?? "?") planned (lighter load)"
                : "TOP SET MISSED by \(shortBy) rep\(shortBy == 1 ? "" : "s"): \(top.text) vs \(prescribedTop?.text ?? "?")"
        } else { verdict = "top set on target (\(actualTop?.text ?? "?"))" }
        if let d = rirDelta, d < 0 { verdict += ", RIR \(-d) lower than planned" }
        if repeatedMiss { verdict += ", ALSO MISSED LAST TIME" }
        if let r = inSessionReason { verdict += ", athlete says: \(r)" }
        if let m = miss { verdict += ", rules suggest \(m.decision.rawValue) (\(m.cause.rawValue))" }
        return "\(name): planned [\(planned)] | did [\(did)] | \(verdict)"
    }
}

struct SessionAnalysis: Equatable {
    var exercises: [ExerciseAnalysis]
    /// Prescribed exercises with nothing logged.
    var skipped: [String]
    var energy: Int
    var userNote: String?

    var missedCount: Int { exercises.filter(\.isMiss).count }
}

/// Deterministic review rules: prescribed vs actual, miss classification, next targets, and the
/// merge with the model's JSON (the model never overrides a rule-detected miss or a pain flag).
enum SessionAnalyzer {

    // MARK: - Analysis

    static func analyze(
        logged: [LoggedExercise],
        prescription: [ExercisePrescription],
        energy: Int,
        userNote: String?,
        reasons: [String: String],
        previous: [CoachReviewEntry],
        history: ExerciseHistoryIndex,
        focus: CoachFocus
    ) -> SessionAnalysis {
        var analyses: [ExerciseAnalysis] = []
        for ex in logged where !ex.sets.isEmpty {
            let pres = prescription.first { ExerciseNameResolver.isMatch($0.name, ex.name) }
            let reason = reasons[ex.name] ?? reasons.first { ExerciseNameResolver.isMatch($0.key, ex.name) }?.value
            analyses.append(analyzeExercise(ex, prescription: pres, energy: energy, userNote: userNote,
                                            reason: reason, previous: previous, history: history, focus: focus))
        }
        let loggedNames = logged.filter { !$0.sets.isEmpty }.map(\.name)
        let skipped = prescription.filter { p in !loggedNames.contains { ExerciseNameResolver.isMatch($0, p.name) } }.map(\.name)
        return SessionAnalysis(exercises: analyses, skipped: skipped, energy: energy, userNote: userNote)
    }

    private static func analyzeExercise(
        _ ex: LoggedExercise, prescription: ExercisePrescription?, energy: Int, userNote: String?,
        reason: String?, previous: [CoachReviewEntry], history: ExerciseHistoryIndex, focus: CoachFocus
    ) -> ExerciseAnalysis {
        let working = SetStyleDetector.splitWarmups(ex.sets).working
        let group = history.group(for: ex.name)
        let prev = group?.sessions.first
        let best = group?.best
        let step = ExerciseTraits.roundingStep(ex.name)
        let actualTop = matchTop(working: working, prescribed: prescription)
        let pTop = prescription?.topSet

        // Prescribed vs actual on the top set.
        var shortBy = 0
        var loadDropped = false
        var rirDelta: Int?
        if let pTop, let top = actualTop {
            if top.weight < pTop.weight * 0.97 {
                loadDropped = true
                let equivalent = Int(((top.e1RM / pTop.weight) - 1) * 30)
                shortBy = max(1, pTop.reps - equivalent)
            } else {
                shortBy = max(0, pTop.reps - top.reps)
            }
            if let rir = top.rir { rirDelta = rir - pTop.rir }
        }

        // Repeat misses and signals.
        let lastReview = previous.lazy.compactMap { $0.document.review?.review(for: ex.name) }.first
        let repeated = lastReview?.outcome == .missed
        let missReason = reason.flatMap(MissReason.from)
        let pain = painSignal(reason: missReason, note: userNote, exerciseName: ex.name, muscle: ex.muscleGroup)

        // Outcome.
        let outcome: ExerciseOutcome
        if pTop != nil, actualTop != nil, shortBy > 0 { outcome = .missed }
        else if let top = actualTop {
            if let b = best, top.e1RM > b.e1RM * 1.001 { outcome = .pr }
            else if prev == nil { outcome = .new }
            else if let p = prev, ProgressionEngine.strength(HistorySession(date: Date(), sets: ex.sets)) < 0.95 * ProgressionEngine.strength(p) { outcome = .regression }
            else { outcome = .hold }
        } else { outcome = .new }

        // Miss decision + target.
        var miss: MissAnalysis?
        var target: NextTarget?
        if outcome == .missed, let pTop, let top = actualTop {
            let m = classifyMiss(shortBy: shortBy, energy: energy, reason: missReason, note: userNote,
                                 repeated: repeated, pain: pain)
            miss = m
            target = missTarget(decision: m.decision, prescribed: pTop, actual: top, shortBy: shortBy,
                                repeated: repeated, step: step)
        } else if let top = actualTop, top.weight > 0 {
            if (rirDelta ?? 0) <= -1, outcome != .pr {
                target = NextTarget(weight: top.weight, reps: top.reps, note: "Hit it but harder than planned: repeat before adding")
            } else {
                let next = ProgressionEngine.nextTopTarget(name: ex.name, after: top, focus: focus, best: best,
                                                           history: group?.sessions ?? [])
                let note = next.weight > top.weight ? "Make the jump" : "Add a rep"
                target = NextTarget(weight: next.weight, reps: next.reps, note: note)
            }
        }
        return ExerciseAnalysis(
            name: ex.name, prescription: prescription, actual: ex.sets, prescribedTop: pTop, actualTop: actualTop,
            shortBy: shortBy, loadDropped: loadDropped, rirDelta: rirDelta, outcome: outcome, repeatedMiss: repeated,
            inSessionReason: reason, painOrFormSignal: pain, miss: miss, target: target,
            note: deterministicNote(name: ex.name, top: actualTop, pTop: pTop, shortBy: shortBy, outcome: outcome,
                                    miss: miss, target: target))
    }

    /// The logged working set that answers the prescribed top set.
    static func matchTop(working: [HistorySet], prescribed: ExercisePrescription?) -> HistorySet? {
        guard !working.isEmpty else { return nil }
        guard let pres = prescribed, let pTop = pres.topSet else { return ProgressionEngine.referenceTop(working) }
        let pWork = pres.workingSets
        let index = pWork.firstIndex(of: pTop) ?? max(0, pWork.count - 1)
        let atOrAbove = working.filter { $0.weight >= pTop.weight * 0.97 }
        if !atOrAbove.isEmpty {
            // Most reps at the prescribed load; the earlier set wins a tie.
            var best = atOrAbove[0]
            for s in atOrAbove.dropFirst() where s.reps > best.reps { best = s }
            return best
        }
        return working[min(index, working.count - 1)]
    }

    // MARK: - Miss rules

    /// Words that mean the athlete was hurting or the form broke.
    static let painWords = ["pain", "hurt", "injur", "tweak", "pinch", "sharp", "strain", "form broke", "form breakdown", "bad form"]
    static let recoveryWords = ["sleep", "slept", "sore", "recover", "fasted", "didn't eat", "did not eat", "hungry", "no food", "skipped meal", "stress", "sick", "hungover"]
    static let tiredWords = ["tired", "low energy", "exhaust", "drained", "fatigue", "flat", "bad day"]

    static func painSignal(reason: MissReason?, note: String?, exerciseName: String, muscle: String) -> Bool {
        if reason == .painOrForm { return true }
        let text = (note ?? "").lowercased()
        guard painWords.contains(where: { text.contains($0) }) else { return false }
        let tokens = (exerciseName + " " + muscle).lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 4 }
        return tokens.contains { text.contains($0) } || text.contains(MuscleGroups.canonical(muscle))
    }

    /// The rules: one-off miss on a bad day -> retry; good energy or a repeat -> likely lost strength,
    /// reduce; pain/form -> hold or swap.
    static func classifyMiss(shortBy: Int, energy: Int, reason: MissReason?, note: String?,
                             repeated: Bool, pain: Bool) -> MissAnalysis {
        if pain {
            return MissAnalysis(cause: .painOrForm, decision: .holdOrSwap,
                                reason: "Pain or form flagged: hold the load or swap the movement, and cue the form.")
        }
        if repeated {
            return MissAnalysis(cause: .strengthLoss, decision: .reduceAndRebuild,
                                reason: "Missed this lift two sessions in a row: it is too heavy right now, so drop and rebuild.")
        }
        if reason == .tooHeavy {
            return MissAnalysis(cause: .strengthLoss, decision: .reduceAndRebuild,
                                reason: "Athlete said it was too heavy.")
        }
        let text = (note ?? "").lowercased()
        if reason == .poorSleep || reason == .underFueled || recoveryWords.contains(where: { text.contains($0) }) {
            return MissAnalysis(cause: .poorRecovery, decision: .retry,
                                reason: "Sleep or fuel was off: a bad day, not lost strength. Same target again.")
        }
        if reason == .lowEnergy || energy <= 4 || tiredWords.contains(where: { text.contains($0) }) {
            return MissAnalysis(cause: .lowEnergy, decision: .retry,
                                reason: "Low energy: a one-off miss, so retry the same target.")
        }
        if energy >= 7 {
            return MissAnalysis(cause: .strengthLoss, decision: .reduceAndRebuild,
                                reason: "Missed with good energy: likely lost strength, drop and rebuild.")
        }
        if shortBy >= 3 {
            return MissAnalysis(cause: .strengthLoss, decision: .reduceAndRebuild,
                                reason: "Missed by \(shortBy) reps: too heavy right now, drop and rebuild.")
        }
        return MissAnalysis(cause: .unknown, decision: .retry,
                            reason: "Close miss with nothing else to blame: try the same target once more.")
    }

    /// The target that follows from a decision.
    static func missTarget(decision: MissDecision, prescribed: PrescribedSet, actual: HistorySet,
                           shortBy: Int, repeated: Bool, step: Double) -> NextTarget {
        switch decision {
        case .retry:
            return NextTarget(weight: prescribed.weight, reps: prescribed.reps, note: "Retry the same target")
        case .reduceAndRebuild:
            let pct = shortBy >= 3 ? 10.0 : (repeated ? 7.5 : 5.0)
            var w = ExerciseTraits.floorStep(prescribed.weight * (1 - pct / 100), step: step)
            if w >= prescribed.weight { w = max(step, prescribed.weight - step) }
            return NextTarget(weight: w, reps: prescribed.reps, note: "Down \(String(format: "%g", pct))%, rebuild from here")
        case .holdOrSwap:
            let w = ExerciseTraits.round(min(prescribed.weight, actual.weight), step: step)
            return NextTarget(weight: w, reps: max(1, actual.reps), note: "Hold, watch form and pain")
        }
    }

    private static func deterministicNote(name: String, top: HistorySet?, pTop: PrescribedSet?, shortBy: Int,
                                          outcome: ExerciseOutcome, miss: MissAnalysis?, target: NextTarget?) -> String {
        var parts: [String] = []
        if let top, let pTop {
            parts.append(shortBy > 0
                ? "Top set \(top.text) vs \(pTop.text) planned, short by \(shortBy) rep\(shortBy == 1 ? "" : "s")."
                : "Top set \(top.text) on target (\(pTop.text) planned).")
        } else if let top {
            parts.append("Best set \(top.text).")
        }
        switch outcome {
        case .pr: parts.append("New best.")
        case .regression: parts.append("Down on last session.")
        default: break
        }
        if let miss { parts.append(miss.reason) }
        if let target { parts.append("Next: \(target.text).") }
        return parts.joined(separator: " ")
    }

    // MARK: - Deterministic review (no model)

    static func fallbackReview(_ analysis: SessionAnalysis, workoutType: String, now: Date = Date()) -> SessionReview {
        SessionReview(
            exercises: analysis.exercises.map { a in
                ExerciseReview(name: a.name, notes: a.note, outcome: a.outcome, nextTarget: a.target, missAnalysis: a.miss)
            },
            overallRead: deterministicOverallRead(analysis, workoutType: workoutType),
            recurringFlags: mandatoryFlags(analysis),
            createdAt: now, aiAuthored: false)
    }

    static func deterministicOverallRead(_ analysis: SessionAnalysis, workoutType: String) -> String {
        let total = analysis.exercises.count
        let missed = analysis.exercises.filter(\.isMiss).map(\.name)
        let prs = analysis.exercises.filter { $0.outcome == .pr }.map(\.name)
        var read = "\(workoutType): \(total - missed.count) of \(total) lifts on target"
        if !missed.isEmpty { read += ", missed \(missed.joined(separator: ", "))" }
        if !prs.isEmpty { read += ", best ever on \(prs.joined(separator: ", "))" }
        read += ". Energy \(analysis.energy)/10."
        if let first = analysis.exercises.first(where: \.isMiss), let t = first.target {
            read += " Next for \(first.name): \(t.text), no added load."
        } else if missed.isEmpty, total > 0 { read += " Everything hit target." }
        return read
    }

    /// Flags Swift always raises, whatever the model says.
    static func mandatoryFlags(_ analysis: SessionAnalysis) -> [String] {
        var flags: [String] = []
        for a in analysis.exercises {
            if a.painOrFormSignal { flags.append("Pain or form on \(a.name)") }
            if a.repeatedMiss && a.isMiss { flags.append("\(a.name) missed two sessions in a row") }
        }
        if !analysis.skipped.isEmpty { flags.append("Skipped: " + analysis.skipped.joined(separator: ", ")) }
        return flags
    }

    // MARK: - Merging the model's review

    /// Combines the model's JSON with the rules. The model writes the words; the rules keep
    /// misses, pain flags and target sanity honest.
    static func merge(_ analysis: SessionAnalysis, model: ModelReview?, workoutType: String,
                      now: Date = Date()) -> SessionReview {
        guard let model else { return fallbackReview(analysis, workoutType: workoutType, now: now) }
        var exercises: [ExerciseReview] = []
        for a in analysis.exercises {
            let m = model.exercises.first { ExerciseNameResolver.isMatch($0.name, a.name) }
            let notes = m?.notes ?? a.note

            // Outcome: a rule-detected miss stands; the model may not invent one.
            var outcome = a.outcome
            if a.outcome != .missed, let mo = m?.outcome, mo != .missed { outcome = mo }

            // Miss decision: the model's, unless it breaks a hard rule.
            var miss = a.miss
            if var rules = a.miss, let cause = m?.cause, let decision = m?.decision {
                let forced = a.painOrFormSignal || a.repeatedMiss
                let acceptable = !(forced && decision != rules.decision) && !(a.repeatedMiss && decision == .retry)
                if acceptable {
                    rules.cause = cause
                    rules.decision = decision
                    if let r = m?.reason { rules.reason = r }
                    miss = rules
                }
            } else if var rules = a.miss, let r = m?.reason {
                rules.reason = r
                miss = rules
            }

            // Target: from the decision when a miss; otherwise the model's if within a sane window.
            var target = a.target
            if let miss, let pTop = a.prescribedTop, let top = a.actualTop {
                let step = ExerciseTraits.roundingStep(a.name)
                var t = missTarget(decision: miss.decision, prescribed: pTop, actual: top, shortBy: a.shortBy,
                                   repeated: a.repeatedMiss, step: step)
                if let note = m?.nextTarget?.note, !note.isEmpty { t.note = note }
                target = t
            } else if let mt = m?.nextTarget, let top = a.actualTop, top.weight > 0,
                      mt.weight >= top.weight * 0.95, mt.weight <= top.weight * 1.06, (1...30).contains(mt.reps),
                      !(a.harderThanPlanned && mt.weight > top.weight) {
                target = NextTarget(weight: ExerciseTraits.round(mt.weight, step: ExerciseTraits.roundingStep(a.name)),
                                    reps: mt.reps, note: mt.note ?? a.target?.note)
            }
            exercises.append(ExerciseReview(name: a.name, notes: notes, outcome: outcome,
                                            nextTarget: target, missAnalysis: miss))
        }
        var flags = model.recurringFlags
        for mandatory in mandatoryFlags(analysis) where !flags.contains(where: { $0.lowercased() == mandatory.lowercased() }) {
            flags.append(mandatory)
        }
        var read = model.overallRead ?? deterministicOverallRead(analysis, workoutType: workoutType)
        // A rosy read that ignores a rule-detected miss is replaced by the deterministic one.
        let missed = analysis.exercises.filter(\.isMiss).map(\.name)
        if !missed.isEmpty, !missed.contains(where: { read.lowercased().contains($0.lowercased()) }) {
            read = deterministicOverallRead(analysis, workoutType: workoutType)
        }
        return SessionReview(exercises: exercises, overallRead: String(read.prefix(600)),
                             recurringFlags: Array(flags.prefix(6)), createdAt: now, aiAuthored: true)
    }

    // MARK: - Rolling summary

    /// Background-only rolling context built from the review (not from model-written targets).
    static func rollingSummary(review: SessionReview, workoutType: String, previous: String?) -> String {
        var text = "\(workoutType): \(review.overallRead)"
        if !review.recurringFlags.isEmpty { text += " Flags: " + review.recurringFlags.joined(separator: "; ") + "." }
        if let prev = previous?.trimmingCharacters(in: .whitespacesAndNewlines), !prev.isEmpty {
            text += " Earlier: " + String(prev.prefix(300))
        }
        return String(text.prefix(700))
    }
}

// MARK: - Model reply

/// The post-workout JSON the model returns.
struct ModelReview: Equatable {
    struct Exercise: Equatable {
        var name: String
        var notes: String?
        var outcome: ExerciseOutcome?
        var nextTarget: NextTarget?
        var cause: MissCause?
        var decision: MissDecision?
        var reason: String?
    }
    var exercises: [Exercise]
    var overallRead: String?
    var recurringFlags: [String]

    /// nil when the reply is not a review at all.
    static func parse(_ text: String) -> ModelReview? {
        guard let object = JSONReply.object(from: text) else { return nil }
        let read = JSONReply.string(object["overall_read"]) ?? JSONReply.string(object["note"])
        let rawExercises = object["exercises"] as? [[String: Any]]
        guard rawExercises != nil || read != nil else { return nil }
        let exercises: [Exercise] = (rawExercises ?? []).compactMap { raw in
            guard let name = JSONReply.string(raw["name"]) else { return nil }
            var target: NextTarget?
            if let t = raw["next_target"] as? [String: Any], let w = JSONReply.double(t["weight"]),
               let r = JSONReply.int(t["reps"]), w > 0, r > 0 {
                target = NextTarget(weight: w, reps: r, note: JSONReply.string(t["note"]))
            }
            let miss = raw["miss"] as? [String: Any]
            return Exercise(
                name: name,
                notes: JSONReply.string(raw["notes"]).map { String($0.prefix(400)) },
                outcome: JSONReply.string(raw["outcome"]).flatMap { ExerciseOutcome(rawValue: $0.lowercased()) },
                nextTarget: target,
                cause: JSONReply.string(miss?["cause"]).flatMap(MissCause.init(rawValue:)),
                decision: JSONReply.string(miss?["decision"]).flatMap(MissDecision.init(rawValue:)),
                reason: JSONReply.string(miss?["reason"]).map { String($0.prefix(300)) })
        }
        let flags = ((object["recurring_flags"] as? [Any]) ?? []).compactMap { JSONReply.string($0) }.map { String($0.prefix(120)) }
        return ModelReview(exercises: exercises, overallRead: read.map { String($0.prefix(600)) }, recurringFlags: Array(flags.prefix(6)))
    }
}
