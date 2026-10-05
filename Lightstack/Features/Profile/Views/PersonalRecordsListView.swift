import SwiftUI

/// Full, searchable list of every personal record.
struct PersonalRecordsListView: View {
    let records: [PersonalRecord]

    enum SortOrder: String, CaseIterable, Identifiable {
        case name = "A–Z"
        case heaviest = "Heaviest"
        case recent = "Recent"
        var id: String { rawValue }
    }

    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .name

    /// Epley estimate; nil when weight or reps is zero.
    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double? {
        guard weight > 0, reps > 0 else { return nil }
        return weight * (1 + Double(reps) / 30)
    }

    private var filtered: [PersonalRecord] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let matches = query.isEmpty
            ? records
            : records.filter { $0.exerciseName.localizedCaseInsensitiveContains(query) }
        switch sortOrder {
        case .name:
            return matches.sorted { $0.exerciseName.localizedCaseInsensitiveCompare($1.exerciseName) == .orderedAscending }
        case .heaviest:
            return matches.sorted {
                (Self.estimatedOneRepMax(weight: $0.weightLbs, reps: $0.reps) ?? 0)
                    > (Self.estimatedOneRepMax(weight: $1.weightLbs, reps: $1.reps) ?? 0)
            }
        case .recent:
            return matches.sorted { $0.dateAchieved > $1.dateAchieved }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("prList.sort")
                .padding(.bottom, 12)

                if filtered.isEmpty {
                    Text("No records found")
                        .font(AppTheme.caveat(14))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(filtered) { pr in
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
        .navigationTitle("Personal Records")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search exercises")
    }

    private func row(_ pr: PersonalRecord) -> some View {
        HStack(spacing: 8) {
            PRStamp()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(pr.exerciseName)
                    .font(AppTheme.caveat(15))
                    .foregroundStyle(AppTheme.textPrimary)
                    .accessibilityIdentifier("prList.row.\(pr.exerciseName)")
                Text(pr.dateAchieved.formatted(date: .abbreviated, time: .omitted))
                    .font(AppTheme.caveat(11))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0f lbs × %d", pr.weightLbs, pr.reps))
                    .font(AppTheme.plexMono(11, weight: .medium))
                    .foregroundStyle(AppTheme.prStamp)
                if let e1rm = Self.estimatedOneRepMax(weight: pr.weightLbs, reps: pr.reps) {
                    Text(String(format: "e1RM %.0f", e1rm))
                        .font(AppTheme.plexMono(10))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
