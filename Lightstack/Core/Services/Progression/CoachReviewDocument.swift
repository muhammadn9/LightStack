import Foundation

/// A concrete number to aim for next session.
struct NextTarget: Codable, Equatable {
    var weight: Double
    var reps: Int
    var note: String?

    init(weight: Double, reps: Int, note: String? = nil) {
        self.weight = weight
        self.reps = reps
        self.note = note
    }

    /// "140 x 9"
    var text: String { "\(String(format: "%g", weight)) x \(reps)" }
}

enum ExerciseOutcome: String, Codable, Equatable, CaseIterable {
    case pr, hold, regression, missed, new
}

enum MissCause: String, Codable, Equatable, CaseIterable {
    case lowEnergy, poorRecovery, painOrForm, strengthLoss, unknown
}

enum MissDecision: String, Codable, Equatable, CaseIterable {
    /// One-off bad day: try the same target again.
    case retry
    /// Likely lost strength: drop 5-10% and rebuild step by step.
    case reduceAndRebuild
    /// Pain or form: hold the load (or swap the exercise) and watch it.
    case holdOrSwap
}

struct MissAnalysis: Codable, Equatable {
    var cause: MissCause
    var decision: MissDecision
    var reason: String
}

/// One set of the plan, as prescribed.
struct PrescribedSet: Codable, Equatable {
    var role: SetRole
    var weight: Double
    var reps: Int
    var rir: Int
    var restSeconds: Int

    var text: String { "\(String(format: "%g", weight))x\(reps)@\(rir)" }
}

/// The ordered set targets of one exercise, written when the plan is finalized.
struct ExercisePrescription: Codable, Equatable {
    var name: String
    var muscleGroup: String?
    var sets: [PrescribedSet]

    var workingSets: [PrescribedSet] { sets.filter { $0.role != .warmup } }
    /// The set the session is built around: the `top` set, else the heaviest working set.
    var topSet: PrescribedSet? {
        workingSets.first { $0.role == .top } ?? workingSets.max { $0.weight < $1.weight }
    }
}

struct ExerciseReview: Codable, Equatable {
    var name: String
    var notes: String
    var outcome: ExerciseOutcome
    var nextTarget: NextTarget?
    var missAnalysis: MissAnalysis?
}

/// Written after the workout is finished.
struct SessionReview: Codable, Equatable {
    var exercises: [ExerciseReview]
    var overallRead: String
    var recurringFlags: [String]
    var createdAt: Date?
    /// False when the AI reply was missing or unusable and Swift's rules wrote the review.
    var aiAuthored: Bool

    init(exercises: [ExerciseReview], overallRead: String, recurringFlags: [String],
         createdAt: Date? = nil, aiAuthored: Bool = true) {
        self.exercises = exercises
        self.overallRead = overallRead
        self.recurringFlags = recurringFlags
        self.createdAt = createdAt
        self.aiAuthored = aiAuthored
    }

    func review(for name: String) -> ExerciseReview? {
        exercises.first { ExerciseNameResolver.isMatch($0.name, name) }
    }
}

/// Everything the coach remembers about one workout, stored as JSON in
/// `Workout.aiProgressionNote` (a TEXT column locally and in Supabase, so no schema change).
/// Old plain-text notes load as `legacyNote`.
struct CoachReviewDocument: Codable, Equatable {
    static let currentVersion = 1
    /// Marker key that tells a document apart from a plain-text note.
    private static let marker = "coachReview"

    var version: Int = CoachReviewDocument.currentVersion
    /// Written when the plan is finalized (and refreshed at finish from what was on screen).
    var prescription: [ExercisePrescription] = []
    /// The structure review from the plan call (verdict, changes), for the UI.
    var planReview: CoachPlanReview?
    /// Written after finish.
    var review: SessionReview?
    /// Exercise name -> the athlete's answer to "why was that short?" (`MissReason` raw value or free text).
    var inSessionReasons: [String: String] = [:]
    /// A pre-v2 plain-text progression note.
    var legacyNote: String?

    init() {}

    init(legacyNote: String) { self.legacyNote = legacyNote }

    enum CodingKeys: String, CodingKey {
        case marker = "coachReview"
        case prescription, planReview, review, inSessionReasons, legacyNote
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .marker) ?? Self.currentVersion
        // Each part decodes on its own so one damaged section never loses the rest.
        prescription = (try? c.decodeIfPresent([ExercisePrescription].self, forKey: .prescription)) ?? []
        planReview = try? c.decodeIfPresent(CoachPlanReview.self, forKey: .planReview)
        review = try? c.decodeIfPresent(SessionReview.self, forKey: .review)
        inSessionReasons = try c.decodeIfPresent([String: String].self, forKey: .inSessionReasons) ?? [:]
        legacyNote = try c.decodeIfPresent(String.self, forKey: .legacyNote)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .marker)
        if !prescription.isEmpty { try c.encode(prescription, forKey: .prescription) }
        try c.encodeIfPresent(planReview, forKey: .planReview)
        try c.encodeIfPresent(review, forKey: .review)
        if !inSessionReasons.isEmpty { try c.encode(inSessionReasons, forKey: .inSessionReasons) }
        try c.encodeIfPresent(legacyNote, forKey: .legacyNote)
    }

    // MARK: - Storage string

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// The JSON string stored in `aiProgressionNote`.
    func encoded() -> String? {
        guard let data = try? Self.encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Reads a stored note. nil for empty text; plain text becomes a legacy document.
    static func parse(_ stored: String?) -> CoachReviewDocument? {
        guard let text = stored?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.hasPrefix("{"), text.contains("\"\(marker)\""),
           let data = text.data(using: .utf8),
           let doc = try? decoder.decode(CoachReviewDocument.self, from: data) {
            return doc
        }
        return CoachReviewDocument(legacyNote: text)
    }

    // MARK: - Display

    /// Readable text for the post-workout card and History: the overall read, per-exercise
    /// lines, next targets and flags. Legacy notes pass through; a plan-only document has none.
    static func displayText(from stored: String?) -> String? {
        guard let doc = parse(stored) else { return nil }
        return doc.displayText
    }

    var displayText: String? {
        if let review {
            var parts: [String] = []
            let read = review.overallRead.trimmingCharacters(in: .whitespacesAndNewlines)
            if !read.isEmpty { parts.append(read) }
            let lines = review.exercises.compactMap { ex -> String? in
                let notes = ex.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                return notes.isEmpty ? nil : "\(ex.name): \(notes)"
            }
            if !lines.isEmpty { parts.append(lines.joined(separator: "\n")) }
            let targets = review.exercises.compactMap { ex -> String? in
                guard let t = ex.nextTarget else { return nil }
                return "\(ex.name) \(t.text)" + ((t.note?.isEmpty ?? true) ? "" : " (\(t.note ?? ""))")
            }
            if !targets.isEmpty { parts.append("Next session:\n" + targets.joined(separator: "\n")) }
            if !review.recurringFlags.isEmpty { parts.append("Watch: " + review.recurringFlags.joined(separator: "; ")) }
            return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
        }
        return legacyNote
    }

    // MARK: - Prescription helpers

    func prescription(for name: String) -> ExercisePrescription? {
        prescription.first { ExerciseNameResolver.isMatch($0.name, name) }
    }

    func reason(for name: String) -> String? {
        if let exact = inSessionReasons[name] { return exact }
        return inSessionReasons.first { ExerciseNameResolver.isMatch($0.key, name) }?.value
    }
}
