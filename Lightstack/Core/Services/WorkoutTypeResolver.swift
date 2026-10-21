import Foundation

/// Suggests workout-type names that mean the same thing ("Push" / "push" / "Push Day").
/// It only ever *suggests*; nothing is renamed without the user's say-so.
enum WorkoutTypeResolver {

    /// Generic trailing words that add no identity ("Push Day", "Leg Workout").
    private static let suffixes: Set<String> = ["day", "days", "workout", "workouts", "session", "sessions"]

    /// Comparison key: trimmed, lowercased, whitespace collapsed, trailing generic word dropped,
    /// and a trailing plural "s" removed from the last word ("Legs" ~ "Leg", "Pulls" ~ "Pull").
    static func key(_ name: String) -> String {
        var words = name.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if words.count > 1, let last = words.last, suffixes.contains(last) { words.removeLast() }
        if let last = words.last, last.count > 3, last.hasSuffix("s"), !last.hasSuffix("ss") {
            words[words.count - 1] = String(last.dropLast())
        }
        return words.joined(separator: " ")
    }

    /// Clusters of names with the same key (size >= 2), in the order the names were given.
    static func duplicateGroups(among names: [String]) -> [[String]] {
        var groups: [String: [String]] = [:]
        var order: [String] = []
        for name in names {
            let k = key(name)
            guard !k.isEmpty else { continue }
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(name)
        }
        return order.compactMap { groups[$0] }.filter { $0.count >= 2 }
    }
}
