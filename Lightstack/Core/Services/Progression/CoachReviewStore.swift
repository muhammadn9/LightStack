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

    var title: String {
        switch self {
        case .lowEnergy: return "Low energy"
        case .poorSleep: return "Slept badly"
        case .underFueled: return "Didn't eat enough"
        case .tooHeavy: return "Just too heavy"
        case .painOrForm: return "Pain or form"
        case .other: return "Something else"
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
            else { doc.inSessionReasons[exercise] = String(clean.prefix(200)) }
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
    func recordReview(_ review: SessionReview, prescription: [ExercisePrescription]? = nil, for workoutId: UUID) -> Bool {
        update(workoutId: workoutId) { doc in
            doc.review = review
            if let prescription, !prescription.isEmpty { doc.prescription = prescription }
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
