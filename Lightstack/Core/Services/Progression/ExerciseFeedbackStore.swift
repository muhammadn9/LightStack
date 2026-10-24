import Foundation

/// The athlete's optional "too easy / about right / too hard" answer for one exercise in one
/// workout, keyed by the exercise's id (an exercise row belongs to exactly one workout).
///
/// The answer is written into the workout's `CoachReviewDocument` (`Workout.aiProgressionNote`), which
/// syncs, so it survives a reinstall or a new device. UserDefaults still gets a copy: it is the only
/// place answers given before this change exist, so reads fall back to it.
final class ExerciseFeedbackStore {

    static let shared = ExerciseFeedbackStore()
    static let defaultsKey = "coach.exerciseFeedback"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var reviewStore: CoachReviewStore?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Connects the store to the repository-backed document writer (done once at app start).
    func attach(reviewStore: CoachReviewStore) {
        lock.lock(); defer { lock.unlock() }
        self.reviewStore = reviewStore
    }

    /// Document first (when the workout is known), then the device-only copy.
    func feedback(forExercise id: UUID, workoutId: UUID? = nil) -> SessionFeedback? {
        lock.lock()
        let store = reviewStore
        lock.unlock()
        if let workoutId, let doc = store?.document(forWorkoutId: workoutId),
           let synced = doc.feedback(forExercise: id) {
            return synced
        }
        return deviceFeedback(forExercise: id)
    }

    /// Sets the answer; `nil` clears it. Also written to the workout's document so it syncs.
    func set(_ feedback: SessionFeedback?, forExercise id: UUID, workoutId: UUID? = nil) {
        lock.lock()
        var current = map()
        current[id.uuidString] = feedback?.rawValue
        defaults.set(current, forKey: Self.defaultsKey)
        let store = reviewStore
        lock.unlock()
        if let workoutId { store?.recordFeedback(feedback, exerciseId: id, workoutId: workoutId) }
    }

    func deviceFeedback(forExercise id: UUID) -> SessionFeedback? {
        lock.lock(); defer { lock.unlock() }
        return map()[id.uuidString].flatMap(SessionFeedback.init(rawValue:))
    }

    /// Feedback reader for the history index: answers stored in the given workouts' documents win,
    /// anything else falls back to `fallback` (the device-only copy for older data).
    static func reader(workouts: [Workout],
                       fallback: @escaping (UUID) -> SessionFeedback?) -> (UUID) -> SessionFeedback? {
        var synced: [UUID: SessionFeedback] = [:]
        for workout in workouts {
            guard let doc = CoachReviewDocument.parse(workout.aiProgressionNote) else { continue }
            for (key, raw) in doc.feedback {
                if let id = UUID(uuidString: key), let value = SessionFeedback(rawValue: raw) { synced[id] = value }
            }
        }
        return { synced[$0] ?? fallback($0) }
    }

    private func map() -> [String: String] {
        defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
    }
}
