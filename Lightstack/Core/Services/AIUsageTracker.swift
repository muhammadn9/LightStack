import Foundation

/// Token counts from Gemini's `usageMetadata`.
struct AIUsage: Equatable {
    var prompt = 0
    var candidates = 0
    var thoughts = 0
    var total = 0

    /// Reads `usageMetadata` from a decoded Gemini response; nil when absent.
    static func from(response json: [String: Any]) -> AIUsage? {
        guard let meta = json["usageMetadata"] as? [String: Any] else { return nil }
        func int(_ key: String) -> Int { (meta[key] as? NSNumber)?.intValue ?? 0 }
        return AIUsage(prompt: int("promptTokenCount"), candidates: int("candidatesTokenCount"),
                       thoughts: int("thoughtsTokenCount"), total: int("totalTokenCount"))
    }
}

#if DEBUG
/// DEBUG-only counter of AI calls and tokens per task, per day. Shown in Settings.
final class AIUsageTracker {
    static let shared = AIUsageTracker()

    struct Entry: Codable, Equatable {
        var calls = 0
        var prompt = 0
        var candidates = 0
        var thoughts = 0
        var total = 0
    }

    private let lock = NSLock()
    private let defaults = UserDefaults.standard
    private let key = "ai_usage_debug_v1"

    private struct Stored: Codable {
        var day: String
        var tasks: [String: Entry]
    }

    private static func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func load() -> Stored {
        if let data = defaults.data(forKey: key),
           let stored = try? JSONDecoder().decode(Stored.self, from: data),
           stored.day == Self.today() {
            return stored
        }
        return Stored(day: Self.today(), tasks: [:])
    }

    private func save(_ stored: Stored) {
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: key) }
    }

    func recordCall(task: AITask) {
        lock.lock(); defer { lock.unlock() }
        var stored = load()
        stored.tasks[task.rawValue, default: Entry()].calls += 1
        save(stored)
    }

    func recordUsage(task: AITask, usage: AIUsage) {
        lock.lock(); defer { lock.unlock() }
        var stored = load()
        var entry = stored.tasks[task.rawValue, default: Entry()]
        entry.prompt += usage.prompt
        entry.candidates += usage.candidates
        entry.thoughts += usage.thoughts
        entry.total += usage.total
        stored.tasks[task.rawValue] = entry
        save(stored)
    }

    func snapshot() -> [(task: AITask, entry: Entry)] {
        lock.lock(); defer { lock.unlock() }
        let stored = load()
        return AITask.allCases.compactMap { task in
            stored.tasks[task.rawValue].map { (task, $0) }
        }
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: key)
    }
}
#endif
