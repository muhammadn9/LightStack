import Foundation

/// A past session's review, with when it happened.
struct CoachReviewEntry: Equatable {
    var workoutId: UUID
    var date: Date
    var workoutType: String
    var document: CoachReviewDocument
}

/// The user-facing reasons offered when a prescribed number is missed in-session.
enum MissReason: String, Codable, CaseIterable, Equatable {
    case lowEnergy, poorSleep, underFueled, tooHeavy, painOrForm, other
    /// Only offered when the athlete lowered the weight: an intentional drop set / back-off, not a problem.
    case plannedDrop

    /// Reasons offered when a set falls short (no planned drop).
    static var missCases: [MissReason] { allCases.filter { $0 != .plannedDrop } }
    /// Reasons offered when the athlete lowered the weight.
    static var dropCases: [MissReason] { [.plannedDrop] + missCases }

    var title: String {
        switch self {
        case .lowEnergy: return "Low energy"
        case .poorSleep: return "Slept badly"
        case .underFueled: return "Didn't eat enough"
        case .tooHeavy: return "Just too heavy"
        case .painOrForm: return "Pain or form"
        case .other: return "Something else"
        case .plannedDrop: return "Planned drop / back-off"
        }
    }

    /// Maps stored free text (or a raw value) back to a reason.
    static func from(_ text: String) -> MissReason? {
        if let exact = MissReason(rawValue: text) { return exact }
        let t = text.lowercased()
        if t.contains("pain") || t.contains("hurt") || t.contains("form") || t.contains("injur") || t.contains("tweak") { return .painOrForm }
        if t.contains("sleep") || t.contains("slept") || t.contains("recover") || t.contains("sore") { return .poorSleep }
        if t.contains("eat") || t.contains("fuel") || t.contains("fasted") || t.contains("hungry") || t.contains("food") { return .underFueled }
        if t.contains("energy") || t.contains("tired") || t.contains("fatigue") { return .lowEnergy }
        if t.contains("heavy") || t.contains("too much") { return .tooHeavy }
        return nil
    }
}

/// Reads and writes `CoachReviewDocument`s kept in `Workout.aiProgressionNote`.
/// Every write goes through `WorkoutRepository.updateWorkout`, so it is saved locally and queued
/// for Supabase like any other workout edit. No schema change.
final class CoachReviewStore {

    private let workoutRepository: WorkoutRepository

    init(workoutRepository: WorkoutRepository) {
        self.workoutRepository = workoutRepository
    }

    // MARK: - Read

    func document(for workout: Workout) -> CoachReviewDocument? {
        CoachReviewDocument.parse(workout.aiProgressionNote)
    }

    func document(forWorkoutId id: UUID) -> CoachReviewDocument? {
        workoutRepository.fetchWorkout(id: id).flatMap { document(for: $0) }
    }

    /// Reviews of the latest sessions of `workoutType` that have a finished review, newest first.
    func latestReviews(userId: UUID, workoutType: String, limit: Int = 4,
                       excluding excluded: UUID? = nil) -> [CoachReviewEntry] {
        let workouts = workoutRepository.fetchRecentWorkouts(userId: userId, limit: 60)
        return Self.latestReviews(from: workouts, workoutType: workoutType, limit: limit, excluding: excluded)
    }

    /// Pure version of `latestReviews` over already-fetched workouts.
    static func latestReviews(from workouts: [Workout], workoutType: String, limit: Int,
                              excluding excluded: UUID? = nil) -> [CoachReviewEntry] {
        var entries: [CoachReviewEntry] = []
        for w in workouts.sorted(by: { $0.date > $1.date })
        where w.workoutType.lowercased() == workoutType.lowercased() && w.id != excluded {
            guard let doc = CoachReviewDocument.parse(w.aiProgressionNote), doc.review != nil else { continue }
            entries.append(CoachReviewEntry(workoutId: w.id, date: w.date, workoutType: w.workoutType, document: doc))
            if entries.count >= limit { break }
        }
        return entries
    }

    /// The newest next-session target per exercise (keys are lowercased names).
    func nextTargets(userId: UUID, workoutType: String) -> [String: PlanCoachContext.DatedTarget] {
        Self.nextTargets(from: latestReviews(userId: userId, workoutType: workoutType, limit: 5))
    }

    /// Newest first: the first entry that has a target for an exercise wins.
    static func nextTargets(from entries: [CoachReviewEntry]) -> [String: PlanCoachContext.DatedTarget] {
        var result: [String: PlanCoachContext.DatedTarget] = [:]
        for entry in entries {
            for ex in entry.document.review?.exercises ?? [] {
                let key = ex.name.lowercased()
                guard result[key] == nil, let target = ex.nextTarget else { continue }
                result[key] = PlanCoachContext.DatedTarget(target: target, date: entry.date)
            }
        }
        return result
    }

    // MARK: - Write

    /// Writes the prescription (and the plan review, if any) into the workout's document.
    @discardableResult
    func recordPrescription(_ prescription: [ExercisePrescription], planReview: CoachPlanReview? = nil,
                            for workoutId: UUID) -> Bool {
        update(workoutId: workoutId) { doc in
            doc.prescription = prescription
            if let planReview { doc.planReview = planReview }
        }
    }

    /// Records the answer to "why was that short?" for an exercise of the workout in progress.
    @discardableResult
    func recordInSessionReason(exercise: String, reason: String, workoutId: UUID) -> Bool {
        let clean = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return update(workoutId: workoutId) { doc in
            if clean.isEmpty { doc.inSessionReasons.removeValue(forKey: exercise) }
            else { doc.inSessionReasons[exercise] = InputSanitizer.clipAtWord(clean, limit: 200) }
        }
    }

    @discardableResult
    func recordInSessionReason(exercise: String, reason: MissReason, workoutId: UUID) -> Bool {
        recordInSessionReason(exercise: exercise, reason: reason.rawValue, workoutId: workoutId)
    }

    /// Records (or clears, with nil) the "too easy / about right / too hard" answer for an exercise.
    /// Stored in the workout's document, so it syncs and comes back on a new device.
    @discardableResult
    func recordFeedback(_ feedback: SessionFeedback?, exerciseId: UUID, workoutId: UUID) -> Bool {
        update(workoutId: workoutId) { doc in
            if let feedback { doc.feedback[exerciseId.uuidString] = feedback.rawValue }
            else { doc.feedback.removeValue(forKey: exerciseId.uuidString) }
        }
    }

    /// Stores the finished review, keeping the prescription and reasons already there.
    @discardableResult
    func recordReview(_ review: SessionReview, prescription: [ExercisePrescription]? = nil,
                      analysis: SessionAnalysis? = nil, for workoutId: UUID) -> Bool {
        update(workoutId: workoutId) { doc in
            doc.review = review
            if let prescription, !prescription.isEmpty { doc.prescription = prescription }
            // The decisions learn how they went in the same write as the review.
            if let analysis { doc.decisions = Self.applyOutcomes(analysis, to: doc.decisions) }
        }
    }

    /// Reads the workout fresh, edits its document, saves. False when the workout is gone.
    private func update(workoutId: UUID, _ edit: (inout CoachReviewDocument) -> Void) -> Bool {
        guard var workout = workoutRepository.fetchWorkout(id: workoutId) else { return false }
        var doc = CoachReviewDocument.parse(workout.aiProgressionNote) ?? CoachReviewDocument()
        edit(&doc)
        guard let text = doc.encoded() else { return false }
        workout.aiProgressionNote = text
        workoutRepository.updateWorkout(workout)
        return true
    }

    // MARK: - Decisions

    /// The stored reason keeps the whole sentence (cut at a word boundary only past this length).
    static let decisionReasonLimit = 200

    /// The coach's calls for a finished plan: one per exercise with a top set, with the reason the plan
    /// carried (or the safety rail that replaced it), who set the numbers and what the coach saw.
    static func decisions(prescription: [ExercisePrescription], exercises: [Exercise],
                          evidence: [UUID: ExerciseEvidence], reasons: [CoachExerciseReason],
                          energy: Int?) -> [CoachDecision] {
        var result: [CoachDecision] = []
        for ex in exercises.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            guard let pres = prescription.first(where: { $0.name == ex.name }), let top = pres.topSet else { continue }
            let ev = evidence[ex.id]
            var source = "coach"
            if let kind = ev?.source {
                if kind == .engine { source = "engine" }
                if kind == .engineFallback { source = "fallback" }
            }
            let reasonText = reasons.first { $0.exercise == ex.name }?.text ?? ev?.rationale ?? ""
            var parts: [String] = []
            if let last = ev?.lastSets.last {
                parts.append("last " + last.replacingOccurrences(of: "\u{00D7}", with: "x"))
            }
            if let trend = ev?.trend {
                if trend == .up { parts.append("trend up") }
                if trend == .down { parts.append("trend down") }
            }
            if let energy { parts.append("energy \(energy)") }
            result.append(CoachDecision(
                name: ex.name, muscle: ex.muscleGroup, target: top, sets: pres.workingSets,
                reason: SessionAnalyzer.cleanLine(reasonText, limit: CoachReviewStore.decisionReasonLimit) ?? "",
                context: SessionAnalyzer.cleanLine(parts.joined(separator: ", "), limit: 120) ?? "",
                source: source, outcome: nil))
        }
        return result
    }

    /// Fills each decision's outcome from the session analysis (matched by exercise name).
    static func applyOutcomes(_ analysis: SessionAnalysis, to decisions: [CoachDecision]) -> [CoachDecision] {
        decisions.map { decision -> CoachDecision in
            guard let a = analysis.exercises.first(where: { ExerciseNameResolver.isMatch($0.name, decision.name) }),
                  let top = a.actualTop else { return decision }
            var updated = decision
            let rirText = top.rir.map { "@\($0)" } ?? ""
            updated.outcome = DecisionOutcome(
                hit: a.outcome == .close || (a.shortBy == 0 && a.outcome != .missed),
                actualTop: "\(String(format: "%g", top.weight))x\(top.reps)\(rirText)",
                rir: top.rir, shortBy: a.shortBy, result: a.outcome)
            return updated
        }
    }

    // MARK: - Memory

    /// What the coach remembers about a lift: its past calls and how they went, newest first.
    static func memory(for name: String, muscle: String, from workouts: [Workout], limit: Int = 3) -> CoachExerciseMemory {
        CoachMemoryIndex(workouts: workouts).memory(for: name, muscle: muscle, limit: limit)
    }

    // MARK: - Prescription from the plan

    /// The prescription for a finished plan: every exercise whose targets carry weights.
    static func prescription(exercises: [Exercise], targets: [UUID: [SetTarget]]) -> [ExercisePrescription] {
        exercises.sorted { $0.orderIndex < $1.orderIndex }.compactMap { ex in
            guard let list = targets[ex.id], !list.isEmpty else { return nil }
            let sets: [PrescribedSet] = list.compactMap { t in
                guard let weight = Double(t.prefillWeight), let reps = Int(t.prefillReps) else { return nil }
                return PrescribedSet(role: t.resolvedRole, weight: weight, reps: reps,
                                     rir: Int(t.prefillRir) ?? 2, restSeconds: t.restSeconds ?? ex.restSeconds ?? RestPreference.fallbackSeconds)
            }
            return sets.isEmpty ? nil : ExercisePrescription(name: ex.name, muscleGroup: ex.muscleGroup, sets: sets)
        }
    }
}

// MARK: - Coach memory

/// One remembered call and how it went.
struct CoachMemoryLine: Equatable {
    var date: Date
    var decision: CoachDecision
}

/// What the coach remembers about one lift.
struct CoachExerciseMemory: Equatable {
    /// Past calls on this very lift that have an outcome, newest first.
    var lines: [CoachMemoryLine] = []
    /// Only when this lift has fewer than 2 calls: the newest call per other lift on the same muscle.
    var related: [CoachMemoryLine] = []
    /// The newest memory note for this lift.
    var note: String?

    var isEmpty: Bool { lines.isEmpty && related.isEmpty && note == nil }
}

/// A lift by name and muscle group (for memory lookups of lifts outside the baseline).
struct CoachLiftRef: Equatable {
    var name: String
    var muscle: String
}

/// The coach documents of recent workouts, parsed once (only `aiProgressionNote`, no set fetches).
struct CoachMemoryIndex: Equatable {
    struct Record: Equatable {
        var date: Date
        var document: CoachReviewDocument
        var workoutType: String = ""
    }

    /// Newest first. Only documents that carry decisions or a review.
    var records: [Record] = []

    /// How many workouts are scanned.
    static let scanLimit = 60
    /// At most this many other lifts are added from the same muscle.
    static let relatedLimit = 3

    init() {}

    init(workouts: [Workout]) {
        var found: [Record] = []
        for w in workouts.sorted(by: { $0.date > $1.date }).prefix(Self.scanLimit) {
            guard let doc = CoachReviewDocument.parse(w.aiProgressionNote),
                  !doc.decisions.isEmpty || doc.review != nil else { continue }
            found.append(Record(date: w.date, document: doc, workoutType: w.workoutType))
        }
        records = found
    }

    var isEmpty: Bool { records.isEmpty }

    /// Lifts the coach made a call on (with an outcome) in sessions of this workout type, newest first, once each.
    func lifts(forWorkoutType type: String, limit: Int = 12) -> [CoachLiftRef] {
        var found: [CoachLiftRef] = []
        for record in records where record.workoutType.lowercased() == type.lowercased() {
            for d in record.document.decisions where d.outcome != nil {
                if found.contains(where: { ExerciseNameResolver.isMatch($0.name, d.name) }) { continue }
                found.append(CoachLiftRef(name: d.name, muscle: d.muscle))
                if found.count >= limit { return found }
            }
        }
        return found
    }

    /// The newest memory note for a lift.
    func note(for name: String) -> String? {
        for record in records {
            guard let text = record.document.review?.review(for: name)?.memoryNote else { continue }
            let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { return note }
        }
        return nil
    }

    func memory(for name: String, muscle: String, limit: Int = 3) -> CoachExerciseMemory {
        var result = CoachExerciseMemory()
        result.note = note(for: name)
        guard limit > 0 else { return result }
        for record in records {
            guard let d = record.document.decisions.first(where: {
                $0.outcome != nil && ExerciseNameResolver.isMatch($0.name, name)
            }) else { continue }
            result.lines.append(CoachMemoryLine(date: record.date, decision: d))
            if result.lines.count >= limit { break }
        }
        guard result.lines.count < 2 else { return result }
        let canon = MuscleGroups.canonical(forExercise: name, muscleGroup: muscle)
        var seen: [String] = []
        for record in records {
            for d in record.document.decisions where d.outcome != nil {
                if ExerciseNameResolver.isMatch(d.name, name) { continue }
                if MuscleGroups.canonical(forExercise: d.name, muscleGroup: d.muscle) != canon { continue }
                if seen.contains(where: { ExerciseNameResolver.isMatch($0, d.name) }) { continue }
                if result.related.count >= Self.relatedLimit { break }
                seen.append(d.name)
                result.related.append(CoachMemoryLine(date: record.date, decision: d))
            }
            if result.related.count >= Self.relatedLimit { break }
        }
        return result
    }
}
