import Foundation

/// One page of an active workout: a single exercise, or a superset of 2-4 adjacent exercises.
struct SupersetPage: Equatable {
    /// Non-nil only for a valid superset (2-4 members).
    let groupId: UUID?
    let exerciseIds: [UUID]

    var isSuperset: Bool { groupId != nil }
}

/// Pure helpers for superset grouping. Operate on exercises ordered by `orderIndex`.
enum SupersetGroup {
    static let minMembers = 2
    static let maxMembers = 4

    /// Groups adjacent members sharing a group id into pages. Groups outside 2-4 members
    /// (or non-adjacent) are treated as plain single-exercise pages.
    static func pages(from exercises: [Exercise]) -> [SupersetPage] {
        let sorted = exercises.sorted { $0.orderIndex < $1.orderIndex }
        var pages: [SupersetPage] = []
        var i = 0
        while i < sorted.count {
            guard let gid = sorted[i].supersetGroupId else {
                pages.append(SupersetPage(groupId: nil, exerciseIds: [sorted[i].id]))
                i += 1
                continue
            }
            var j = i
            while j < sorted.count, sorted[j].supersetGroupId == gid { j += 1 }
            let run = sorted[i..<j].map(\.id)
            if isValidSize(run.count), groupIsContiguous(gid, in: sorted) {
                pages.append(SupersetPage(groupId: gid, exerciseIds: Array(run)))
            } else {
                run.forEach { pages.append(SupersetPage(groupId: nil, exerciseIds: [$0])) }
            }
            i = j
        }
        return pages
    }

    static func isValidSize(_ count: Int) -> Bool {
        (minMembers...maxMembers).contains(count)
    }

    /// True when the group has 2-4 members and they are adjacent.
    static func isValid(groupId: UUID, in exercises: [Exercise]) -> Bool {
        let sorted = exercises.sorted { $0.orderIndex < $1.orderIndex }
        let count = sorted.filter { $0.supersetGroupId == groupId }.count
        return isValidSize(count) && groupIsContiguous(groupId, in: sorted)
    }

    /// Links the exercise at `id` (and its group, if any) with the next exercise
    /// (and its group, if any). Returns the updated exercises, or nil when it cannot link
    /// (no next exercise, or the merged group would exceed 4 members).
    static func link(current id: UUID, withNext exercises: [Exercise]) -> [Exercise]? {
        var sorted = exercises.sorted { $0.orderIndex < $1.orderIndex }
        guard let idx = sorted.firstIndex(where: { $0.id == id }) else { return nil }
        let currentRange = memberRange(at: idx, in: sorted)
        let nextStart = currentRange.upperBound
        guard nextStart < sorted.count else { return nil }
        let nextRange = memberRange(at: nextStart, in: sorted)
        let total = nextRange.upperBound - currentRange.lowerBound
        guard total <= maxMembers else { return nil }
        let gid = sorted[currentRange.lowerBound].supersetGroupId ?? UUID()
        for k in currentRange.lowerBound..<nextRange.upperBound {
            sorted[k].supersetGroupId = gid
        }
        return sorted
    }

    /// Clears the group id from every member of `groupId`.
    static func unlink(groupId: UUID, in exercises: [Exercise]) -> [Exercise] {
        exercises.map { ex in
            var copy = ex
            if copy.supersetGroupId == groupId { copy.supersetGroupId = nil }
            return copy
        }
    }

    /// Clears the group id of any group left with fewer than 2 members.
    static func dissolveSingletons(in exercises: [Exercise]) -> [Exercise] {
        let counts = Dictionary(grouping: exercises.compactMap(\.supersetGroupId), by: { $0 }).mapValues(\.count)
        return exercises.map { ex in
            var copy = ex
            if let gid = copy.supersetGroupId, (counts[gid] ?? 0) < minMembers { copy.supersetGroupId = nil }
            return copy
        }
    }

    // MARK: - Private

    /// Contiguous index range of the exercise at `idx` and its group-mates (just `idx` if ungrouped).
    private static func memberRange(at idx: Int, in sorted: [Exercise]) -> Range<Int> {
        guard let gid = sorted[idx].supersetGroupId else { return idx..<(idx + 1) }
        var lo = idx
        var hi = idx + 1
        while lo > 0, sorted[lo - 1].supersetGroupId == gid { lo -= 1 }
        while hi < sorted.count, sorted[hi].supersetGroupId == gid { hi += 1 }
        return lo..<hi
    }

    private static func groupIsContiguous(_ gid: UUID, in sorted: [Exercise]) -> Bool {
        let indices = sorted.indices.filter { sorted[$0].supersetGroupId == gid }
        guard let first = indices.first, let last = indices.last else { return false }
        return last - first + 1 == indices.count
    }
}
