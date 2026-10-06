import SwiftUI

/// One line per exercise: only the best set, with spelling variants of the same
/// exercise ("Hammer curl" / "hammer curls" / "DB hammer curl") merged together.
struct PersonalRecordsListView: View {
    let records: [PersonalRecord]

    enum SortOrder: String, CaseIterable, Identifiable {
        case heaviest = "Heaviest"
        case name = "A–Z"
        var id: String { rawValue }
    }

    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .heaviest

    /// Epley estimate; nil when weight or reps is zero.
    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double? {
        guard weight > 0, reps > 0 else { return nil }
        return weight * (1 + Double(reps) / 30)
    }

    /// Grouping key for an exercise name: case, spacing, punctuation, plurals and
    /// common abbreviations are ignored, so variants of one lift share a key.
    static func exerciseKey(_ name: String) -> String {
        let aliases = ["db": "dumbbell", "dbs": "dumbbell", "bb": "barbell"]
        let words = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { word -> String in
                if let alias = aliases[word] { return alias }
                // Plural -> singular ("curls" -> "curl"), but leave short words and "-ss" alone.
                if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") {
                    return String(word.dropLast())
                }
                return word
            }
        return words.joined(separator: " ")
    }

    /// The single best record per exercise (highest e1RM, then heaviest weight).
    /// The displayed name is the one used most recently.
    static func bestPerExercise(_ records: [PersonalRecord]) -> [PersonalRecord] {
        var groups: [String: [PersonalRecord]] = [:]
        for record in records {
            groups[exerciseKey(record.exerciseName), default: []].append(record)
        }
        return groups.values.compactMap { group in
            let score: (PersonalRecord) -> (Double, Double) = {
                (estimatedOneRepMax(weight: $0.weightLbs, reps: $0.reps) ?? 0, $0.weightLbs)
            }
            guard var best = group.max(by: { score($0) < score($1) }),
                  let latest = group.max(by: { $0.dateAchieved < $1.dateAchieved }) else { return nil }
            best.exerciseName = latest.exerciseName
            return best
        }
    }

    static func sorted(_ records: [PersonalRecord], by order: SortOrder) -> [PersonalRecord] {
        switch order {
        case .heaviest:
            return records.sorted {
                (estimatedOneRepMax(weight: $0.weightLbs, reps: $0.reps) ?? $0.weightLbs)
                    > (estimatedOneRepMax(weight: $1.weightLbs, reps: $1.reps) ?? $1.weightLbs)
            }
        case .name:
            return records.sorted {
                $0.exerciseName.localizedCaseInsensitiveCompare($1.exerciseName) == .orderedAscending
            }
        }
    }

    private var visible: [PersonalRecord] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let best = Self.bestPerExercise(records)
        let matches = query.isEmpty
            ? best
            : best.filter { $0.exerciseName.localizedCaseInsensitiveContains(query) }
        return Self.sorted(matches, by: sortOrder)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("prList.sort")
                .padding(.bottom, 10)

                if visible.isEmpty {
                    Text("No records found")
                        .font(AppTheme.caveat(14))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(visible) { pr in
                        row(pr)
                        InkDivider()
                    }
                }
            }
            .padding(14)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .padding(16)
        }
        .themedBackground()
        .navigationTitle("Top Lifts")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search exercises")
    }

    /// One compact line: name on the left, best set on the right.
    private func row(_ pr: PersonalRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(pr.exerciseName)
                .font(AppTheme.caveat(15))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityIdentifier("prList.row.\(pr.exerciseName)")
            Spacer(minLength: 8)
            Text(String(format: "%.0f × %d", pr.weightLbs, pr.reps))
                .font(AppTheme.plexMono(13, weight: .medium))
                .foregroundStyle(AppTheme.prStamp)
                .accessibilityIdentifier("prList.value.\(pr.exerciseName)")
        }
        .padding(.vertical, 9)
    }
}
