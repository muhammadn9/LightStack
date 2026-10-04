import Foundation

/// One row on an active-workout page: a logged set or a pending (editable) set
/// belonging to one exercise, in one round.
struct SupersetRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case logged(index: Int)
        case pending(index: Int)
    }

    let id: UUID
    let exerciseId: UUID
    /// Zero-based round (set position) within the page.
    let round: Int
    let kind: Kind

    var isPending: Bool {
        if case .pending = kind { return true }
        return false
    }
}

/// Pure helpers for how a (super)set page lays out rows and rests.
enum SupersetRounds {

    /// Default rest when no member specifies one (strength only).
    static let defaultRestSeconds = 90

    /// Rows for a page, grouped by round: round 1 holds every member's first set, and so on.
    /// For a single exercise this is simply its logged sets followed by its pending ones.
    static func rows(
        memberIds: [UUID],
        logged: [UUID: [WorkoutSet]],
        pending: [UUID: [PendingSetInput]]
    ) -> [SupersetRow] {
        let totals = memberIds.map { (logged[$0]?.count ?? 0) + (pending[$0]?.count ?? 0) }
        let rounds = totals.max() ?? 0
        var rows: [SupersetRow] = []
        for round in 0..<rounds {
            for id in memberIds {
                let loggedSets = logged[id] ?? []
                let pendingSets = pending[id] ?? []
                if round < loggedSets.count {
                    rows.append(SupersetRow(id: loggedSets[round].id, exerciseId: id, round: round,
                                            kind: .logged(index: round)))
                } else if round - loggedSets.count < pendingSets.count {
                    let p = round - loggedSets.count
                    rows.append(SupersetRow(id: pendingSets[p].id, exerciseId: id, round: round,
                                            kind: .pending(index: p)))
                }
            }
        }
        return rows
    }

    /// Whether logging a set for `exerciseId` should start the rest timer: always for a
    /// plain exercise, and only for the LAST member of a superset page.
    static func shouldStartRest(afterLogging exerciseId: UUID, in exercises: [Exercise]) -> Bool {
        guard let page = page(containing: exerciseId, in: exercises) else { return false }
        guard page.isSuperset else { return true }
        return page.exerciseIds.last == exerciseId
    }

    /// Longest explicit rest among the members, else 90s for strength, else nil (cardio only).
    static func restSeconds(for members: [Exercise]) -> Int? {
        if let longest = members.compactMap(\.restSeconds).filter({ $0 > 0 }).max() { return longest }
        return members.contains { $0.trackingType == .strength } ? defaultRestSeconds : nil
    }

    /// Rest to start after logging `exerciseId`, or nil when none should start.
    static func restPlan(afterLogging exerciseId: UUID, in exercises: [Exercise]) -> (seconds: Int, name: String)? {
        guard shouldStartRest(afterLogging: exerciseId, in: exercises),
              let page = page(containing: exerciseId, in: exercises) else { return nil }
        let members = page.exerciseIds.compactMap { id in exercises.first { $0.id == id } }
        guard let seconds = restSeconds(for: members) else { return nil }
        return (seconds, members.map(\.name).joined(separator: " + "))
    }

    static func page(containing exerciseId: UUID, in exercises: [Exercise]) -> SupersetPage? {
        SupersetGroup.pages(from: exercises).first { $0.exerciseIds.contains(exerciseId) }
    }
}

// MARK: - Grouping from labels, ordering and copying

extension SupersetGroup {

    /// Same non-empty label (case-insensitive) -> same fresh group id. Labels shared by
    /// fewer than 2 or more than 4 entries, and entries without a label, map to nil.
    static func groupIds(forLabels labels: [String?]) -> [UUID?] {
        let keys = labels.map { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var counts: [String: Int] = [:]
        for key in keys { if let key, !key.isEmpty { counts[key, default: 0] += 1 } }
        var ids: [String: UUID] = [:]
        return keys.map { key in
            guard let key, !key.isEmpty, isValidSize(counts[key] ?? 0) else { return nil }
            if let existing = ids[key] { return existing }
            let new = UUID()
            ids[key] = new
            return new
        }
    }

    /// Clears groups outside 2-4 members, pulls each group's members together at the
    /// position of its first member, and renumbers `orderIndex` 0...n-1.
    static func normalized(_ exercises: [Exercise]) -> [Exercise] {
        let sorted = exercises.sorted { $0.orderIndex < $1.orderIndex }
        let counts = Dictionary(grouping: sorted.compactMap(\.supersetGroupId), by: { $0 }).mapValues(\.count)
        var cleaned = sorted
        for i in cleaned.indices {
            if let gid = cleaned[i].supersetGroupId, !isValidSize(counts[gid] ?? 0) {
                cleaned[i].supersetGroupId = nil
            }
        }
        var result: [Exercise] = []
        var emitted = Set<UUID>()
        for ex in cleaned {
            guard let gid = ex.supersetGroupId else { result.append(ex); continue }
            guard emitted.insert(gid).inserted else { continue }
            result.append(contentsOf: cleaned.filter { $0.supersetGroupId == gid })
        }
        for i in result.indices { result[i].orderIndex = i }
        return result
    }

    /// Puts the given exercises into one new superset (2-4 of them), moving them next to
    /// each other. Returns nil when the count is out of range. Groups left with a single
    /// member are dissolved.
    static func group(ids: [UUID], in exercises: [Exercise]) -> [Exercise]? {
        let unique = Array(NSOrderedSet(array: ids)) as? [UUID] ?? ids
        let present = unique.filter { id in exercises.contains { $0.id == id } }
        guard isValidSize(present.count) else { return nil }
        let gid = UUID()
        let tagged = exercises.map { ex -> Exercise in
            var copy = ex
            if present.contains(ex.id) { copy.supersetGroupId = gid }
            return copy
        }
        return normalized(dissolveSingletons(in: tagged))
    }

    /// For each source exercise, a fresh group id when its group is valid (same old id ->
    /// same new id), else nil. Used when a past workout becomes a new one.
    static func freshGroupIds(copying sources: [Exercise]) -> [UUID?] {
        var map: [UUID: UUID] = [:]
        return sources.map { ex in
            guard let old = ex.supersetGroupId, isValid(groupId: old, in: sources) else { return nil }
            if let existing = map[old] { return existing }
            let new = UUID()
            map[old] = new
            return new
        }
    }
}
