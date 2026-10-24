import ActivityKit
import Foundation

/// Live Activity data for the active workout. Compiled into both the app and the
/// widget extension, so it must stay free of app-only types.
struct LightstackWorkoutAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        /// Current exercise ("" when every planned set is logged).
        var exerciseName: String
        /// Identifies the set shown, so a stale tap on an old Live Activity render is ignored.
        var setKey: String
        var setNumber: Int
        var totalSets: Int
        /// "Top set", "Warm-up"... nil for a plain set.
        var setLabel: String?
        /// "135", or "BW" for bodyweight. Empty for cardio.
        var weightText: String
        var unit: String
        var reps: Int
        var rir: Int?
        var isCardio: Bool
        /// "20:00 · 1.5 mi" for cardio rows.
        var cardioText: String?
        /// False when the pending set has too little filled in to log.
        var canLog: Bool
        /// Name of the next different exercise still to do.
        var nextExercise: String?
        /// Set while resting; drives `Text(timerInterval:)` so it ticks without updates.
        var restEndDate: Date?
        /// `now - elapsed` at the time of the update; `Text(_, style: .timer)` counts up from here.
        var elapsedAnchor: Date
        var isPaused: Bool
        var pausedElapsedSeconds: Int
        /// Every planned set is logged: show a "finish in the app" state.
        var allDone: Bool
    }

    var workoutName: String
}

extension LightstackWorkoutAttributes.ContentState {
    /// True while the rest countdown should show. The system marks the content stale at `restEndDate`
    /// (see `staleDate`) and re-renders, so rest flips to the next-set controls with no app wake-up;
    /// comparing against `now` keeps any render after the end correct as well.
    func isResting(now: Date, isStale: Bool = false) -> Bool {
        guard !isStale, let end = restEndDate else { return false }
        return now < end
    }

    /// When the system should treat this content as stale: the moment rest ends.
    var staleDate: Date? { restEndDate }
}

/// Buttons on the Live Activity.
enum LiveActivityAction: String, Codable, Sendable {
    case weightDown, weightUp, repsDown, repsUp, logSet, skipRest
}
