import SwiftUI

/// Profile -> Manage workout types: merge several spellings of one workout type into one name.
/// Likely duplicates are grouped automatically; any 2+ names can also be picked by hand.
struct MergeWorkoutTypesView: View {
    @EnvironmentObject var environment: AppEnvironment

    /// Called after a merge so the caller can refresh its numbers.
    var onMerged: () -> Void = {}

    @State private var stats: [LocalStorageService.WorkoutTypeStat] = []
    @State private var selected: Set<String> = []
    @State private var pending: [LocalStorageService.WorkoutTypeStat]?
    @State private var searchText = ""

    private var userId: UUID? { environment.authService.currentUser()?.userId }

    private var groups: [[LocalStorageService.WorkoutTypeStat]] {
        let byName = Dictionary(stats.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        return WorkoutTypeResolver.duplicateGroups(among: stats.map(\.name))
            .map { $0.compactMap { byName[$0] } }
    }

    private var visibleStats: [LocalStorageService.WorkoutTypeStat] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return stats }
        return stats.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                duplicatesSection
                manualSection
            }
            .padding(16)
        }
        .themedBackground()
        .navigationTitle("Manage workout types")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search workout types")
        .onAppear(perform: reload)
        .sheet(isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            if let names = pending {
                MergeTypeKeepSheet(candidates: names) { keep in
                    performMerge(names: names, keep: keep)
                }
            }
        }
    }

    // MARK: - Sections

    private var duplicatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Possible duplicates")
                .notebookSectionHeader()
            if groups.isEmpty {
                Text("No likely duplicates found. Pick names below to merge any you spot yourself.")
                    .font(AppTheme.caveat(14))
                    .foregroundStyle(AppTheme.textSecondary)
                    .accessibilityIdentifier("mergeType.noDuplicates")
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                Button { pending = group } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(group) { stat in
                            HStack {
                                Text(stat.name)
                                    .font(AppTheme.caveat(15))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                Text(Self.countsLabel(stat))
                                    .font(AppTheme.plexMono(11, weight: .regular))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                        Text("Merge \(group.count) names")
                            .font(AppTheme.caveat(13))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.top, 2)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mergeType.group.\(index)")
            }
        }
    }

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Merge manually")
                .notebookSectionHeader()
            Text("Select two or more names that are the same workout type.")
                .font(AppTheme.caveat(13))
                .foregroundStyle(AppTheme.textSecondary)

            VStack(spacing: 0) {
                ForEach(visibleStats) { stat in
                    Button { toggle(stat.name) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selected.contains(stat.name) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(stat.name) ? AppTheme.accent : AppTheme.textSecondary)
                            Text(stat.name)
                                .font(AppTheme.caveat(15))
                                .foregroundStyle(AppTheme.textPrimary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Text(Self.countsLabel(stat))
                                .font(AppTheme.plexMono(11, weight: .regular))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mergeType.pick.\(stat.name)")
                    InkDivider()
                }
            }
            .padding(.horizontal, 12)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.border, lineWidth: 1))

            Button {
                pending = stats.filter { selected.contains($0.name) }
            } label: {
                Text(selected.count >= 2 ? "Merge \(selected.count) selected" : "Select 2 or more to merge")
                    .font(AppTheme.playfairItalic(16, weight: .bold))
                    .foregroundStyle(selected.count >= 2 ? AppTheme.onAccent : AppTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(selected.count >= 2 ? AppTheme.accent : AppTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(selected.count < 2)
            .accessibilityIdentifier("mergeType.mergeSelected")
        }
    }

    // MARK: - Actions

    private func toggle(_ name: String) {
        if selected.contains(name) { selected.remove(name) } else { selected.insert(name) }
    }

    private func reload() {
        guard let userId else { return }
        stats = environment.localStorageService.fetchWorkoutTypeStats(userId: userId)
        selected = selected.filter { name in stats.contains { $0.name == name } }
    }

    private func performMerge(names: [LocalStorageService.WorkoutTypeStat], keep: String) {
        guard let userId else { return }
        environment.workoutTypeMergeService.merge(userId: userId, names: names.map(\.name), keep: keep)
        pending = nil
        selected = []
        reload()
        onMerged()
    }

    static func countsLabel(_ stat: LocalStorageService.WorkoutTypeStat) -> String {
        "\(stat.workoutCount) \(stat.workoutCount == 1 ? "workout" : "workouts")"
    }
}

/// Pick the name to keep (default: the most-logged), then confirm.
private struct MergeTypeKeepSheet: View {
    let candidates: [LocalStorageService.WorkoutTypeStat]
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var keep: String = ""
    @State private var confirming = false

    private var others: [LocalStorageService.WorkoutTypeStat] { candidates.filter { $0.name != keep } }
    private var affectedWorkouts: Int { others.reduce(0) { $0 + $1.workoutCount } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Which name do you want to keep?")
                        .font(AppTheme.playfair(16, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    VStack(spacing: 0) {
                        ForEach(candidates) { stat in
                            Button { keep = stat.name } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: keep == stat.name ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(keep == stat.name ? AppTheme.accent : AppTheme.textSecondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(stat.name)
                                            .font(AppTheme.caveat(16))
                                            .foregroundStyle(AppTheme.textPrimary)
                                            .multilineTextAlignment(.leading)
                                        Text(MergeWorkoutTypesView.countsLabel(stat))
                                            .font(AppTheme.plexMono(11, weight: .regular))
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("mergeType.keep.\(stat.name)")
                            InkDivider()
                        }
                    }
                    .padding(.horizontal, 12)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.border, lineWidth: 1))

                    Text("Every workout, planned session and split day using the other names is renamed to \"\(keep)\". This can't be undone.")
                        .font(AppTheme.caveat(13))
                        .foregroundStyle(AppTheme.textSecondary)

                    Button { confirming = true } label: {
                        Text("Merge")
                            .font(AppTheme.playfairItalic(16, weight: .bold))
                            .foregroundStyle(AppTheme.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(AppTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityIdentifier("mergeType.confirm")
                }
                .padding(16)
            }
            .themedBackground()
            .navigationTitle("Merge workout types")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityIdentifier("mergeType.cancel")
                }
            }
            .confirmationDialog(
                "Merge into \"\(keep)\"?",
                isPresented: $confirming,
                titleVisibility: .visible
            ) {
                Button("Merge into \(keep)") {
                    onConfirm(keep)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Renames \(affectedWorkouts) workouts from \(others.map { "\"\($0.name)\"" }.joined(separator: ", ")) to \"\(keep)\".")
            }
        }
        .onAppear {
            if keep.isEmpty {
                keep = candidates.max(by: { $0.workoutCount < $1.workoutCount })?.name ?? ""
            }
        }
    }
}
