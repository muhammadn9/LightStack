import Foundation

/// The athlete's optional "too easy / about right / too hard" answer for one exercise in one
/// workout, keyed by the exercise's id (an exercise row belongs to exactly one workout).
///
/// Kept in UserDefaults: `sets.user_feedback` already holds the free-text set note
/// from the active workout, so it cannot also carry this without mixing the two.
final class ExerciseFeedbackStore {

    static let shared = ExerciseFeedbackStore()
    static let defaultsKey = "coach.exerciseFeedback"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func feedback(forExercise id: UUID) -> SessionFeedback? {
        lock.lock(); defer { lock.unlock() }
        return map()[id.uuidString].flatMap(SessionFeedback.init(rawValue:))
    }

    /// Sets the answer; `nil` clears it.
    func set(_ feedback: SessionFeedback?, forExercise id: UUID) {
        lock.lock(); defer { lock.unlock() }
        var current = map()
        current[id.uuidString] = feedback?.rawValue
        defaults.set(current, forKey: Self.defaultsKey)
    }

    private func map() -> [String: String] {
        defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
    }
}
