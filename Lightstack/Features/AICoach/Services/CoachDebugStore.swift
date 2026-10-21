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
        now: Date = Date()
    ) {
        lock.lock(); defer { lock.unlock() }
        store(CoachPlanSnapshot(
            userId: userId.uuidString, timestamp: now, workoutType: workoutType, model: model,
            systemPromptName: systemPromptName, systemPromptLength: systemPromptLength,
            userMessage: userMessage, rawResponse: nil, adjustments: []))
    }

    func recordResponse(userId: UUID, raw: String, adjustments: [String]) {
        lock.lock(); defer { lock.unlock() }
        guard var snapshot = current(), snapshot.userId == userId.uuidString else { return }
        snapshot.rawResponse = raw
        snapshot.adjustments = adjustments
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
