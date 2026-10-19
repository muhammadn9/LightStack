import Foundation

/// Finds which past logged exercises count as "the same lift" as a name the user
/// just added mid-workout, so the new rows can start from last time's numbers.
enum PreviousSessionLookup {

    struct Candidate: Equatable {
        let id: UUID
        let name: String
        let date: Date
    }

    /// Candidate ids to try, best first: every name-for-name match (case, plural and
    /// punctuation insensitive) newest first, then near-equivalents the
    /// `ExerciseNameResolver` treats as the same lift ("Leg curl machine" and
    /// "Seated hamstring curl"), newest first.
    static func rankedMatches(forName name: String, among candidates: [Candidate]) -> [UUID] {
        let key = PersonalRecordsListView.exerciseKey(name)
        guard !key.isEmpty else { return [] }
        var exact: [Candidate] = []
        var fuzzy: [Candidate] = []
        for candidate in candidates {
            if PersonalRecordsListView.exerciseKey(candidate.name) == key {
                exact.append(candidate)
            } else if ExerciseNameResolver.isMatch(name, candidate.name) {
                fuzzy.append(candidate)
            }
        }
        let newestFirst: (Candidate, Candidate) -> Bool = { $0.date > $1.date }
        return exact.sorted(by: newestFirst).map(\.id) + fuzzy.sorted(by: newestFirst).map(\.id)
    }
}
