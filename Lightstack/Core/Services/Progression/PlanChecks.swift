import Foundation

/// The checks that run over the FINAL plan, after the coach's decisions were applied. A check that fails is repaired
/// by the engine and reported as adjusted; nothing is only reported.
enum PlanChecks {

    static let ladderID = "ladder"
    static let noProgressID = "noProgress"
    static let repJumpID = "repJump"
    static let volumeID = "volume"
    static let timeID = "time"
    static let evidenceID = "evidence"

    /// Words that count as naming evidence in a reason (besides any digit).
    static let evidenceWords: Set<String> = [
        "rir", "miss", "missed", "misses", "pr", "prs", "note", "notes", "fuel", "days", "day", "goal", "hours", "hour",
        "pain", "e1rm", "deficit", "protein", "calories", "flag", "flags", "injury", "sore", "soreness"
    ]

    /// Working sets one lift may have: isolation 3, main lifts 3 (4 for strength).
    static func workingSetCap(name: String, focus: CoachFocus) -> Int {
        ExerciseTraits.classify(name) == .isolation ? 3 : (focus == .strength ? ProgressionEngine.mainWorkingSets + 1 : ProgressionEngine.mainWorkingSets)
    }

    /// Runs every check, repairing the plan in place. `priorNotes` carries what the decision step already changed
    /// (a push held back), listed under the check it belongs to.
    static func run(_ lifts: inout [PlanLift], context ctx: PlanDecisionContext, priorNotes: [String: [String]] = [:],
                    adjustments: inout [String]) -> [PlanCheck] {
        var checks: [PlanCheck] = []
        checks.append(PlanCheck(id: ladderID, title: "Weights are ones the lift has", adjustments: ladder(&lifts, ctx)))
        checks.append(PlanCheck(id: noProgressID, title: "No progress when rules forbid it",
                                adjustments: (priorNotes[noProgressID] ?? []) + noProgress(&lifts, ctx)))
        checks.append(PlanCheck(id: repJumpID, title: "Rep jumps stay within the rule", adjustments: repJumps(&lifts, ctx)))
        checks.append(PlanCheck(id: volumeID, title: "Set counts and muscle volume within limits", adjustments: volume(&lifts, ctx)))
        checks.append(PlanCheck(id: timeID, title: "Fits the time available", adjustments: time(&lifts, ctx)))
        checks.append(PlanCheck(id: evidenceID, title: "Every lift names its evidence", adjustments: evidence(&lifts)))
        for check in checks where check.adjusted {
            for note in check.adjustments where !adjustments.contains(note) { adjustments.append(note) }
        }
        return checks
    }

    private static func g(_ value: Double) -> String { String(format: "%g", value) }

    private static func group(_ lift: PlanLift, _ ctx: PlanDecisionContext) -> ExerciseHistoryGroup? {
        ctx.history.group(for: lift.exercise.name)
    }

    private static func lastWork(_ group: ExerciseHistoryGroup?) -> [HistorySet] {
        group?.sessions.first.map { SetStyleDetector.splitWarmups($0.sets).working } ?? []
    }

    // MARK: 1. Ladder

    private static func ladder(_ lifts: inout [PlanLift], _ ctx: PlanDecisionContext) -> [String] {
        var notes: [String] = []
        for i in lifts.indices {
            let name = lifts[i].exercise.name
            let rungs = lifts[i].draft?.input?.increments ?? WeightIncrements.learned(name: name, group: group(lifts[i], ctx))
            for j in lifts[i].targets.indices {
                guard let w = Double(lifts[i].targets[j].prefillWeight), w > 0, !rungs.isOnLadder(w) else { continue }
                let fixed = rungs.snap(w, direction: .down)
                lifts[i].targets[j].weight = g(fixed)
                notes.append("\(name): \(g(w)) is not a weight this lift has, so \(g(fixed)) was used")
            }
        }
        return notes
    }

    // MARK: 2. No progress when something forbids it

    /// A lift whose gate is closed (trained hours ago, low fuel, layoff, last session missed) may not end up above the
    /// engine's own top set. When it does, the engine's draft is restored.
    private static func noProgress(_ lifts: inout [PlanLift], _ ctx: PlanDecisionContext) -> [String] {
        var notes: [String] = []
        for i in lifts.indices {
            guard let draft = lifts[i].draft, let draftTop = draft.result.topSet, let top = lifts[i].top,
                  let w = Double(top.prefillWeight), let r = Int(top.prefillReps),
                  let why = CoachDecisionApplier.gateReason(for: draft, ctx: ctx) else { continue }
            let above = w > draftTop.weight + 0.001 || (abs(w - draftTop.weight) <= 0.001 && r > draftTop.reps)
            guard above else { continue }
            let requested = lifts[i].decision.move
            lifts[i].targets = draft.result.sets.map(\.setTarget)
            lifts[i].decision.requested = requested
            lifts[i].decision.move = .asPlanned
            lifts[i].decision.held = why
            lifts[i].decision.finalTop = CoachDecisionApplier.topText(draftTop)
            notes.append("\(lifts[i].exercise.name): held at \(g(draftTop.weight))x\(draftTop.reps) because \(why)")
        }
        return notes
    }

    // MARK: 3. Rep jumps

    private static func repJumps(_ lifts: inout [PlanLift], _ ctx: PlanDecisionContext) -> [String] {
        var notes: [String] = []
        for i in lifts.indices {
            let g0 = group(lifts[i], ctx)
            let last = lastWork(g0)
            guard !last.isEmpty else { continue }
            let rungs = lifts[i].draft?.input?.increments ?? WeightIncrements.learned(name: lifts[i].exercise.name, group: g0)
            let capped = PlanGuardrails.capRepJumps(lifts[i].targets, last: last, ladder: rungs)
            guard !capped.reasons.isEmpty else { continue }
            lifts[i].targets = capped.targets
            for reason in capped.reasons { notes.append("\(lifts[i].exercise.name): \(reason)") }
        }
        return notes
    }

    // MARK: 4. Set counts and muscle volume

    private static func volume(_ lifts: inout [PlanLift], _ ctx: PlanDecisionContext) -> [String] {
        var notes: [String] = []
        // Per lift.
        for i in lifts.indices {
            let name = lifts[i].exercise.name
            let cap = workingSetCap(name: name, focus: ctx.coach.focus)
            let working = lifts[i].workingCount
            guard working > cap else { continue }
            lifts[i].targets = CoachDecisionApplier.setCount(lifts[i].targets, wanted: cap, isolation: ExerciseTraits.classify(name) == .isolation)
            if lifts[i].workingCount > cap {
                // A mixed list the structure cannot trim: drop from the end.
                while lifts[i].workingCount > cap, let last = lifts[i].targets.lastIndex(where: { $0.isWarmup != true }) {
                    lifts[i].targets.remove(at: last)
                }
            }
            notes.append("\(name): \(working) working sets is over the limit of \(cap), so \(lifts[i].workingCount) were kept")
        }
        // Per muscle.
        let muscles = Set(lifts.map { MuscleGroups.canonical(forExercise: $0.exercise.name, muscleGroup: $0.exercise.muscleGroup) })
        for muscle in muscles.sorted() {
            func members() -> [Int] {
                lifts.indices.filter { MuscleGroups.canonical(forExercise: lifts[$0].exercise.name, muscleGroup: lifts[$0].exercise.muscleGroup) == muscle }
            }
            var total = members().reduce(0) { $0 + lifts[$1].workingCount }
            guard total > PlanGuardrails.maxHardSetsPerMuscle else { continue }
            let before = total
            var removed: [String] = []
            var guardCount = 0
            while total > PlanGuardrails.maxHardSetsPerMuscle, guardCount < 20 {
                guardCount += 1
                let ordered = members().sorted { a, b in
                    let ia = ExerciseTraits.classify(lifts[a].exercise.name) == .isolation
                    let ib = ExerciseTraits.classify(lifts[b].exercise.name) == .isolation
                    return ia != ib ? ia : a > b
                }
                var trimmed = false
                for i in ordered {
                    let isIso = ExerciseTraits.classify(lifts[i].exercise.name) == .isolation
                    let count = lifts[i].workingCount
                    if isIso, count <= PlanGuardrails.minWorkingSets, members().count > 1 {
                        total -= count
                        removed.append("dropped \(lifts[i].exercise.name)")
                        lifts.remove(at: i)
                        trimmed = true
                        break
                    }
                    if count > PlanGuardrails.minWorkingSets {
                        let list = lifts[i].targets
                        let now = list.indices.filter { list[$0].isWarmup != true }
                        let firstTop = now.first { list[$0].resolvedRole == .top }
                        if let v = now.last(where: { list[$0].resolvedRole == .top && $0 != firstTop })
                            ?? now.last(where: { list[$0].resolvedRole == .ramp })
                            ?? now.last(where: { list[$0].resolvedRole != .top }) {
                            lifts[i].targets.remove(at: v)
                            total -= 1
                            removed.append("-1 set on \(lifts[i].exercise.name)")
                            trimmed = true
                            break
                        }
                    }
                }
                if !trimmed { break }
            }
            notes.append("\(muscle.capitalized): \(before) hard sets is over the \(PlanGuardrails.maxHardSetsPerMuscle) cap (\(removed.joined(separator: ", ")))")
        }
        return notes
    }

    // MARK: 5. Time

    /// 40 s of work per set plus its rest, and a few minutes of setup.
    static func estimatedMinutes(_ lifts: [PlanLift]) -> Double {
        let seconds = lifts.reduce(0) { total, lift in
            total + lift.targets.reduce(0) { $0 + 40 + ($1.restSeconds ?? lift.exercise.restSeconds ?? RestPreference.fallbackSeconds) }
        }
        return Double(seconds) / 60 + 3
    }

    /// Over the time available (plus 10%): isolation sets and lifts go, last first. The first two lifts always stay.
    private static func time(_ lifts: inout [PlanLift], _ ctx: PlanDecisionContext) -> [String] {
        let limit = Double(ctx.timeMinutes) * 1.1
        var notes: [String] = []
        var guardCount = 0
        while estimatedMinutes(lifts) > limit, lifts.count > 2, guardCount < 40 {
            guardCount += 1
            let iso = lifts.indices.filter { ExerciseTraits.classify(lifts[$0].exercise.name) == .isolation && $0 >= 2 }
            if let i = iso.last(where: { lifts[$0].workingCount > PlanGuardrails.minWorkingSets }),
               let set = lifts[i].targets.lastIndex(where: { $0.isWarmup != true }) {
                lifts[i].targets.remove(at: set)
                notes.append("\(lifts[i].exercise.name): one set removed to fit \(ctx.timeMinutes) minutes")
            } else if let i = iso.last {
                notes.append("\(lifts[i].exercise.name): removed to fit \(ctx.timeMinutes) minutes")
                lifts.remove(at: i)
            } else {
                break
            }
        }
        return notes
    }

    // MARK: 6. Evidence

    /// True when the reason has a digit or one of the evidence words.
    static func namesEvidence(_ reason: String) -> Bool {
        if reason.contains(where: \.isNumber) { return true }
        let words = reason.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        return words.contains { evidenceWords.contains($0) }
    }

    /// A reason with no evidence keeps the coach's words and gets the engine's evidence line after them.
    private static func evidence(_ lifts: inout [PlanLift]) -> [String] {
        var notes: [String] = []
        for i in lifts.indices {
            let reason = lifts[i].decision.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            var line = lifts[i].evidenceLine
            if line.isEmpty, let top = lifts[i].top {
                line = "New lift, no log yet: starts at " + [top.prefillWeight, top.prefillReps].filter { !$0.isEmpty }.joined(separator: "×") + " @\(top.prefillRir)"
            }
            if reason.isEmpty {
                lifts[i].decision.reason = line
            } else if !namesEvidence(reason), !line.isEmpty {
                let joiner = reason.hasSuffix(".") || reason.hasSuffix("!") ? " " : ". "
                lifts[i].decision.reason = reason + joiner + line
                notes.append("\(lifts[i].exercise.name): the reason named no evidence, so \"\(line)\" was added")
            }
        }
        return notes
    }
}
