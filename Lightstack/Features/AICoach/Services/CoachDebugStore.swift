import Foundation

/// What the coach was shown for the last plan request and what came back.
struct CoachPlanSnapshot: Codable, Equatable {
    var userId: String
    var timestamp: Date
    var workoutType: String
    var model: String
    var systemPromptName: String
    var systemPromptLength: Int
    /// The rendered user message sent to the AI.
    var userMessage: String
    /// The AI's raw reply; nil until it arrives.
    var rawResponse: String?
    /// What the progression engine and guardrails changed.
    var adjustments: [String]
    /// The coach's plan: summary, one decision per lift and the checks that ran.
    var review: CoachPlanReview? = nil
    /// Per exercise: the coach's decision label and the reason shown. nil on snapshots saved by older builds.
    var reasons: [CoachExerciseReason]? = nil
    /// "Coach changes: 6 (4 on target, 2 missed) · As planned: 18 (15 on target, 3 missed)"; nil on older snapshots.
    var scorecard: String? = nil
    /// Whether the athlete shared the nutrition summary / pre-workout meals when this was sent. nil on older snapshots.
    var nutritionShared: Bool? = nil
    var mealsShared: Bool? = nil
    /// The exact FUEL and PRE-WORKOUT MEALS blocks in the message; nil when none was sent.
    var fuelBlock: String? = nil
    var mealsBlock: String? = nil
}

/// One line of "Coach's reasons": an exercise, the decision label ("As planned", "Pushed by coach", ...) and the reason.
struct CoachExerciseReason: Codable, Equatable {
    var exercise: String
    var label: String
    var text: String

    init(exercise: String, label: String, text: String) {
        self.exercise = exercise
        self.label = label
        self.text = text
    }

    enum CodingKeys: String, CodingKey { case exercise, label, text }

    /// Older snapshots stored a flag instead of a label; they decode with an empty one.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exercise = try c.decode(String.self, forKey: .exercise)
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? ""
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
    }
}

/// Keeps the last plan request for a "What the coach saw" screen. In memory plus
/// UserDefaults, capped at about 50 KB, one user only, cleared on sign-out.
final class CoachDebugStore {

    static let shared = CoachDebugStore()
    static let maxBytes = 50_000
    static let defaultsKey = "coach.debug.lastPlan"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var cached: CoachPlanSnapshot?
    private var loaded = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The last plan snapshot, only if it belongs to `userId`.
    func lastPlan(forUser userId: UUID) -> CoachPlanSnapshot? {
        lock.lock(); defer { lock.unlock() }
        guard let snapshot = current(), snapshot.userId == userId.uuidString else { return nil }
        return snapshot
    }

    /// The last plan snapshot regardless of user (tests, diagnostics).
    var lastPlan: CoachPlanSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return current()
    }

    func recordRequest(
        userId: UUID, workoutType: String, model: String,
        systemPromptName: String, systemPromptLength: Int, userMessage: String,
        nutritionShared: Bool? = nil, mealsShared: Bool? = nil, fuelBlock: String? = nil, mealsBlock: String? = nil,
        scorecard: String? = nil, now: Date = Date()
    ) {
        lock.lock(); defer { lock.unlock() }
        store(CoachPlanSnapshot(
            userId: userId.uuidString, timestamp: now, workoutType: workoutType, model: model,
            systemPromptName: systemPromptName, systemPromptLength: systemPromptLength,
            userMessage: userMessage, rawResponse: nil, adjustments: [], review: nil,
            scorecard: scorecard, nutritionShared: nutritionShared, mealsShared: mealsShared, fuelBlock: fuelBlock, mealsBlock: mealsBlock))
    }

    func recordResponse(userId: UUID, raw: String, adjustments: [String], review: CoachPlanReview? = nil,
                        reasons: [CoachExerciseReason]? = nil) {
        lock.lock(); defer { lock.unlock() }
        guard var snapshot = current(), snapshot.userId == userId.uuidString else { return }
        snapshot.rawResponse = raw
        snapshot.adjustments = adjustments
        snapshot.review = review
        snapshot.reasons = reasons
        store(snapshot)
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        cached = nil
        loaded = true
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    // MARK: - Private

    private func current() -> CoachPlanSnapshot? {
        if !loaded {
            loaded = true
            if let data = defaults.data(forKey: Self.defaultsKey) {
                cached = try? JSONDecoder().decode(CoachPlanSnapshot.self, from: data)
            }
        }
        return cached
    }

    private func store(_ snapshot: CoachPlanSnapshot) {
        var capped = snapshot
        capped.adjustments = Array(capped.adjustments.prefix(40))
        // Shrink the two long strings until the encoded snapshot fits.
        var allowance = Self.maxBytes / 2
        for _ in 0..<12 {
            if let data = try? JSONEncoder().encode(capped), data.count <= Self.maxBytes {
                cached = capped
                loaded = true
                defaults.set(data, forKey: Self.defaultsKey)
                return
            }
            capped.userMessage = Self.limited(capped.userMessage, to: allowance)
            capped.rawResponse = capped.rawResponse.map { Self.limited($0, to: allowance) }
            allowance = max(200, allowance * 3 / 4)
        }
        cached = capped
        loaded = true
    }

    private static func limited(_ text: String, to characters: Int) -> String {
        text.count <= characters ? text : String(text.prefix(characters)) + "… [truncated]"
    }
}
