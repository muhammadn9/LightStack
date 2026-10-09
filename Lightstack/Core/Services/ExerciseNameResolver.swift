import Foundation

/// Local, deterministic matching of exercise names that mean the same lift
/// ("Leg curl machine" / "Seated hamstring curl"). It only ever *suggests*;
/// nothing is renamed without the user's say-so. No AI calls.
enum ExerciseNameResolver {

    /// Two names count as the same exercise at or above this token-set similarity.
    static let threshold = 0.75

    /// Words that carry no identity ("machine", "seated"...).
    private static let fillers: Set<String> = ["machine", "seated", "the", "a", "an", "of", "on", "with"]

    /// Multi-word phrases rewritten to one canonical form, applied in order on the
    /// normalised (lowercased, singular) name.
    private static let phraseSynonyms: [(String, String)] = [
        ("lat pull down", "pulldown"),
        ("pull down", "pulldown"),
        ("lat pulldown", "pulldown"),
        ("hamstring curl", "leg curl"),
        ("adductor", "adduction"),
        ("abductor", "abduction"),
        ("smith machine", "smith"),
        ("chest press", "press")
    ]

    /// Distinguishing tokens of a name. When `dropCable` is true "cable" is removed too.
    private static func tokens(_ name: String, dropCable: Bool) -> Set<String> {
        var key = " " + PersonalRecordsListView.exerciseKey(name) + " "
        for (from, to) in phraseSynonyms {
            key = key.replacingOccurrences(of: " \(from) ", with: " \(to) ")
        }
        var words = key.split(separator: " ").map(String.init).filter { !fillers.contains($0) }
        if dropCable { words.removeAll { $0 == "cable" } }
        return Set(words)
    }

    private static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }

    /// 0...1. 1 means the same exercise after normalisation. "Cable" is ignored only
    /// when everything else matches, so "Cable curl" ~ "Curl" but not "Barbell curl".
    static func similarity(_ a: String, _ b: String) -> Double {
        let plain = jaccard(tokens(a, dropCable: false), tokens(b, dropCable: false))
        let noCable = jaccard(tokens(a, dropCable: true), tokens(b, dropCable: true))
        return max(plain, noCable)
    }

    static func isMatch(_ a: String, _ b: String) -> Bool {
        similarity(a, b) >= threshold
    }

    /// Known names that probably mean `name`, best first. A name that is already
    /// known verbatim (case-insensitive) yields no suggestion for itself.
    static func suggestions(for name: String, among known: [String]) -> [String] {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return [] }
        var seen = Set<String>()
        let scored: [(String, Double)] = known.compactMap { candidate in
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  trimmed.lowercased() != typed.lowercased(),
                  seen.insert(trimmed.lowercased()).inserted else { return nil }
            let score = similarity(typed, trimmed)
            return score >= threshold ? (trimmed, score) : nil
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// Clusters of names that look like the same exercise (size >= 2). Matching is
    /// transitive: if A~B and B~C, all three land in one group. Order follows `names`.
    static func duplicateGroups(among names: [String]) -> [[String]] {
        var parent = Array(0..<names.count)
        func find(_ i: Int) -> Int {
            var root = i
            while parent[root] != root { root = parent[root] }
            return root
        }
        for i in names.indices {
            for j in names.indices where j > i && isMatch(names[i], names[j]) {
                parent[find(j)] = find(i)
            }
        }
        var groups: [Int: [String]] = [:]
        var order: [Int] = []
        for i in names.indices {
            let root = find(i)
            if groups[root] == nil { order.append(root) }
            groups[root, default: []].append(names[i])
        }
        return order.compactMap { groups[$0] }.filter { $0.count >= 2 }
    }
}
