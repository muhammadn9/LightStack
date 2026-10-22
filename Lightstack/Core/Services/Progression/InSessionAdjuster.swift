import Foundation

extension HistorySet {
    init(_ set: WorkoutSet) {
        self.init(set.weightLbs, set.reps, rir: set.rir)
    }
}

/// Mid-workout check, pure and UI-free. When the first working set or the top set falls short,
/// it proposes lighter weights for the sets still to come and a question to ask why.
enum InSessionAdjuster {

    /// A set as logged (weight, reps, RIR).
    typealias LoggedSet = HistorySet

    /// Reps under the target that trigger a suggestion.
    static let repShortfall = 2

    struct SetChange: Equatable {
        /// Index into the `prescribed` array.
        var index: Int
        var role: SetRole
        var previousWeight: Double
        var weight: Double
        var reps: Int
    }

    struct Suggestion: Equatable {
        /// Index into `prescribed` of the set that fell short.
        var triggerIndex: Int
        /// Index into `logged` of that set. Show the suggestion only while it is the latest logged set.
        var triggerLoggedIndex: Int
        var role: SetRole
        var shortBy: Int
        var rirZero: Bool
        /// Asked in the UI; the answer goes to `recordInSessionReason`.
        var question: String
        var reasons: [MissReason]
        /// New weights for the sets not yet logged (may be empty when the short set was the last).
        var changes: [SetChange]
        var message: String
    }

    /// - Parameters:
    ///   - prescribed: the exercise's set targets in order.
    ///   - logged: sets logged so far, in order (warm-ups included when the athlete logs them).
    ///   - roundingStep: plate step for new weights (`ExerciseTraits.roundingStep(name)`).
    static func evaluate(prescribed: [SetTarget], logged: [LoggedSet], roundingStep: Double = 5) -> Suggestion? {
        guard !prescribed.isEmpty, !logged.isEmpty else { return nil }
        let offset = warmupOffset(prescribed: prescribed, logged: logged)

        // Candidates: the first working set and the first top set.
        let working = prescribed.indices.filter { prescribed[$0].resolvedRole != .warmup }
        guard let firstWorking = working.first else { return nil }
        var candidates = [firstWorking]
        if let top = prescribed.indices.first(where: { prescribed[$0].resolvedRole == .top }), top != firstWorking {
            candidates.append(top)
        }

        for index in candidates.sorted() {
            let loggedIndex = index - offset
            guard loggedIndex >= 0, loggedIndex < logged.count else { continue }
            let target = prescribed[index]
            let set = logged[loggedIndex]
            guard let targetWeight = Double(target.prefillWeight), let targetReps = Int(target.prefillReps),
                  targetWeight > 0 else { continue }
            // The athlete already changed the load: nothing to correct.
            guard set.weight >= targetWeight * 0.97 else { continue }
            let short = targetReps - set.reps
            let plannedRir = Int(target.prefillRir)
            let rirZero = set.rir == 0 && (plannedRir ?? 0) >= 1
            guard short >= repShortfall || rirZero else { continue }
            return suggestion(prescribed: prescribed, index: index, loggedIndex: loggedIndex,
                              loggedCount: logged.count, offset: offset, shortBy: max(0, short),
                              rirZero: rirZero, step: roundingStep)
        }
        return nil
    }

    /// Convenience for UI call sites that hold `WorkoutSet`s.
    static func evaluate(exerciseName: String, prescribed: [SetTarget], logged: [WorkoutSet]) -> Suggestion? {
        evaluate(prescribed: prescribed, logged: logged.sorted { $0.setNumber < $1.setNumber }.map { LoggedSet($0) },
                 roundingStep: ExerciseTraits.roundingStep(exerciseName))
    }

    // MARK: - Private

    /// 1 when the athlete skipped logging the prescribed warm-up (their first logged set is
    /// clearly closer to the first working set than to the warm-up).
    private static func warmupOffset(prescribed: [SetTarget], logged: [LoggedSet]) -> Int {
        guard prescribed.first?.resolvedRole == .warmup, prescribed.count > 1,
              let warm = Double(prescribed[0].prefillWeight), let work = Double(prescribed[1].prefillWeight),
              let first = logged.first, work > warm else { return 0 }
        return abs(first.weight - work) < abs(first.weight - warm) ? 1 : 0
    }

    private static func suggestion(prescribed: [SetTarget], index: Int, loggedIndex: Int, loggedCount: Int,
                                   offset: Int, shortBy: Int, rirZero: Bool, step: Double) -> Suggestion {
        let role = prescribed[index].resolvedRole
        var changes: [SetChange] = []
        for k in prescribed.indices where k > index && (k - offset) >= loggedCount {
            let target = prescribed[k]
            let r = target.resolvedRole
            guard r != .warmup, let w = Double(target.prefillWeight), let reps = Int(target.prefillReps), w > 0 else { continue }
            let factor: Double
            switch r {
            case .backoff: factor = 0.90
            case .top: factor = role == .top ? 0.90 : 0.95
            default: factor = 0.95
            }
            var lowered = ExerciseTraits.floorStep(w * factor, step: step)
            if lowered >= w { lowered = max(step, w - step) }
            guard lowered < w else { continue }
            changes.append(SetChange(index: k, role: r, previousWeight: w, weight: lowered, reps: reps))
        }
        let what = rirZero && shortBy < repShortfall ? "went to failure" : "came up \(shortBy) rep\(shortBy == 1 ? "" : "s") short"
        var message = "That set \(what)."
        if !changes.isEmpty {
            message += " Drop the rest: " + changes.map { "\(String(format: "%g", $0.weight)) for set \($0.index + 1)" }.joined(separator: ", ") + "."
        }
        return Suggestion(
            triggerIndex: index, triggerLoggedIndex: loggedIndex, role: role, shortBy: shortBy, rirZero: rirZero,
            question: "What got in the way?", reasons: MissReason.allCases, changes: changes, message: message)
    }
}
