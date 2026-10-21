import Foundation

/// How the athlete felt about the last session of an exercise (optional input).
enum SessionFeedback: String, Codable, Equatable {
    case tooEasy, aboutRight, tooHard
}

/// One logged set, weight in lb.
struct HistorySet: Equatable {
    var weight: Double
    var reps: Int
    var rir: Int?

    init(_ weight: Double, _ reps: Int, rir: Int? = nil) {
        self.weight = weight
        self.reps = reps
        self.rir = rir
    }

    /// Epley estimated one-rep max.
    var e1RM: Double { weight * (1 + Double(reps) / 30) }

    /// "185×6@1" (RIR omitted when unknown).
    var text: String {
        let w = String(format: "%g", weight)
        return "\(w)×\(reps)" + (rir.map { "@\($0)" } ?? "")
    }
}

/// One session's ordered sets for one exercise group.
struct HistorySession: Equatable {
    var date: Date
    var sets: [HistorySet]
}

enum ExerciseClass: Equatable {
    case heavyCompound, compound, isolation
}

enum SetStyle: String, Equatable {
    case straightSets, topSetBackoff, pyramid, dropSet
}

enum ProgressionTrend: String, Equatable {
    case up, flat, down
}

struct RepRange: Equatable {
    var lower: Int
    var upper: Int
}

/// One prescribed set from the engine.
struct ProgressionSet: Equatable {
    var weight: Double
    var reps: Int
    var rir: Int
    var isWarmup: Bool

    var text: String {
        "\(String(format: "%g", weight))×\(reps)@\(rir)" + (isWarmup ? " (warm-up)" : "")
    }

    /// Per-set target for the existing UI pipeline.
    var setTarget: SetTarget {
        SetTarget(weight: String(format: "%g", weight), reps: String(reps), rir: String(rir),
                  isWarmup: isWarmup ? true : nil)
    }
}

struct ProgressionInput {
    var name: String
    /// Newest first: the last session plus up to 4 earlier same-type sessions.
    var sessions: [HistorySession]
    /// Best set on record (heaviest e1RM), when known.
    var best: HistorySet?
    var feedback: SessionFeedback?
    /// 1...10
    var energy: Int
    /// True only for the first heavy compound of the workout.
    var allowWarmups: Bool

    init(name: String, sessions: [HistorySession], best: HistorySet? = nil,
         feedback: SessionFeedback? = nil, energy: Int = 6, allowWarmups: Bool = false) {
        self.name = name
        self.sessions = sessions
        self.best = best
        self.feedback = feedback
        self.energy = energy
        self.allowWarmups = allowWarmups
    }
}

struct ProgressionResult: Equatable {
    var sets: [ProgressionSet]
    var rationale: String
    var style: SetStyle
    var repRange: RepRange
    var trend: ProgressionTrend

    var workingSets: [ProgressionSet] { sets.filter { !$0.isWarmup } }
    var warmupCount: Int { sets.filter(\.isWarmup).count }
}

/// What the UI can show next to an exercise's targets, keyed by exercise id.
struct ExerciseEvidence: Equatable {
    enum Source: String, Equatable {
        /// Set targets computed by `ProgressionEngine` from logged history.
        case engine
        /// No usable history: the AI's numbers, untouched by the guardrails.
        case ai
        /// No usable history: the AI's numbers after `PlanGuardrails` changed something.
        case aiGuarded
    }

    var source: Source
    /// Last session's sets, e.g. ["160×3@4", "185×6@1"] (empty with no history).
    var lastSets: [String]
    var lastSessionDate: Date?
    /// Best set on record, e.g. "230×1".
    var best: String?
    var trend: ProgressionTrend
    /// Machine-made one-liner, e.g. "Last: 185×6@1, ... → hold 185 ...".
    var rationale: String
    var style: SetStyle?
    var warmupCount: Int
    var adjustedByGuardrails: Bool
    var guardrailReasons: [String]
}
