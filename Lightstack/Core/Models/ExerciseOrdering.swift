import Foundation

/// Pure helpers for reordering exercises and inserting new ones mid-workout.
/// A "unit" is one active-workout page: a single exercise, or a whole superset,
/// so moving units never splits a superset.
enum ExerciseOrdering {

    /// Units in display order, each a list of exercise ids.
    static func units(from exercises: [Exercise]) -> [[UUID]] {
        SupersetGroup.pages(from: exercises).map(\.exerciseIds)
    }

    /// Exercises laid out in `unitOrder`, with `orderIndex` renumbered 0...n-1.
    /// Exercises missing from `unitOrder` keep their relative order at the end.
    static func reordered(_ exercises: [Exercise], unitOrder: [[UUID]]) -> [Exercise] {
        let sorted = exercises.sorted { $0.orderIndex < $1.orderIndex }
        let byId = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        var result: [Exercise] = []
        for id in unitOrder.flatMap({ $0 }) {
            if let exercise = byId[id], seen.insert(id).inserted { result.append(exercise) }
        }
        for exercise in sorted where !seen.contains(exercise.id) { result.append(exercise) }
        return renumbered(result)
    }

    /// Inserts `new` right after the unit at `unitIndex` (after the whole superset
    /// when that unit is one). An out-of-range index appends at the end.
    static func inserting(_ new: Exercise, afterUnit unitIndex: Int, in exercises: [Exercise]) -> [Exercise] {
        var list = exercises.sorted { $0.orderIndex < $1.orderIndex }
        let units = Self.units(from: list)
        var insertAt = list.count
        if units.indices.contains(unitIndex),
           let lastId = units[unitIndex].last,
           let idx = list.firstIndex(where: { $0.id == lastId }) {
            insertAt = idx + 1
        }
        list.insert(new, at: insertAt)
        return renumbered(list)
    }

    static func renumbered(_ exercises: [Exercise]) -> [Exercise] {
        exercises.enumerated().map { index, exercise in
            var copy = exercise
            copy.orderIndex = index
            return copy
        }
    }
}

/// An exercise name the user has logged before, with its muscle group.
struct HistoryExercise: Identifiable, Equatable {
    let name: String
    let muscleGroup: String
    var id: String { name.lowercased() }

    /// Distinct by name (case-insensitive), keeping first occurrence, so callers
    /// pass rows most-recent-first. Blank names are dropped.
    static func distinct(_ rows: [(name: String, muscleGroup: String)]) -> [HistoryExercise] {
        var seen = Set<String>()
        var result: [HistoryExercise] = []
        for row in rows {
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            let group = row.muscleGroup.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(HistoryExercise(name: name, muscleGroup: group.isEmpty ? "Other" : group))
        }
        return result
    }

    /// Case-insensitive substring filter; empty search keeps everything.
    static func filtered(_ items: [HistoryExercise], search: String) -> [HistoryExercise] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}

/// Helpers for the "From history" workout choices on the setup screen.
enum HistoryWorkoutNames {
    /// Distinct workout names, in the order given (most recent first), skipping
    /// blanks and anything in `excluding` (case-insensitive).
    static func distinct(_ names: [String], excluding: [String]) -> [String] {
        var seen = Set(excluding.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        var result: [String] = []
        for raw in names {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            result.append(name)
        }
        return result
    }
}
