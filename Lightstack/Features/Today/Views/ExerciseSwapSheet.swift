import SwiftUI

/// Alternatives for one exercise on the plan preview: same-muscle lifts the user has
/// done (with last session's numbers), catalog picks, a full search, and removal.
struct ExerciseSwapSheet: View {
    @ObservedObject var todayViewModel: TodayViewModel
    let exercise: Exercise
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [SwapCandidate] = []
    @State private var showSearch = false

    private var fromHistory: [SwapCandidate] { candidates.filter(\.isFromHistory) }
    private var fromCatalog: [SwapCandidate] { candidates.filter { !$0.isFromHistory } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Instead of \(exercise.name)")
                        .font(AppTheme.playfairItalic(18, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .accessibilityIdentifier("swapSheetTitle")

                    if !fromHistory.isEmpty {
                        section("From your history", fromHistory)
                    }
                    if !fromCatalog.isEmpty {
                        section("Other \(exercise.muscleGroup.lowercased()) exercises", fromCatalog)
                    }
                    if candidates.isEmpty {
                        Text("No close matches. Search the full list instead.")
                            .font(AppTheme.caveat(14))
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Button(action: { showSearch = true }) {
                        Label("Search all exercises", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WaxSealButtonStyle(isSecondary: true))
                    .accessibilityIdentifier("swapSearchButton")

                    Button(role: .destructive) {
                        todayViewModel.removeExercise(at: exercise.id)
                        finish()
                    } label: {
                        Label("Remove this exercise", systemImage: "trash")
                            .font(AppTheme.caveat(15, weight: .bold))
                            .foregroundStyle(AppTheme.warning)
                            .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                    }
                    .accessibilityIdentifier("swapRemoveButton")
                }
                .padding(16)
            }
            .themedBackground()
            .navigationTitle("Swap Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityIdentifier("swapCancelButton")
                }
            }
            .onAppear { candidates = todayViewModel.swapCandidates(forExerciseId: exercise.id) }
            .sheet(isPresented: $showSearch) {
                ExerciseCatalogPicker(loadYourExercises: { todayViewModel.historyExercises() }) { name, group in
                    choose(name: name, muscleGroup: group)
                }
            }
        }
    }

    private func section(_ title: String, _ items: [SwapCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTheme.playfair(14, weight: .bold))
                .foregroundStyle(AppTheme.accent)
            ForEach(items) { candidate in
                row(candidate)
            }
        }
    }

    private func row(_ candidate: SwapCandidate) -> some View {
        Button(action: { choose(name: candidate.name, muscleGroup: candidate.muscleGroup) }) {
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.name)
                    .font(AppTheme.playfair(14, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(Self.prefillSummary(for: candidate, replacing: exercise))
                    .font(AppTheme.caveat(12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("swapOption.\(candidate.name)")
    }

    private func choose(name: String, muscleGroup: String) {
        todayViewModel.swapExercise(id: exercise.id, toName: name, muscleGroup: muscleGroup)
        finish()
    }

    private func finish() {
        onFinish()
        dismiss()
    }

    /// "Last: 55 lbs × 15, 60 × 12, 65 × 9" or, with no history, the replaced exercise's targets.
    static func prefillSummary(for candidate: SwapCandidate, replacing old: Exercise) -> String {
        if candidate.previous.isEmpty {
            let sets = old.targetSets.map { "\($0) sets" } ?? "Sets"
            let reps = old.targetReps.map { " × \($0) reps" } ?? ""
            return "Not logged yet · \(sets)\(reps), no weight"
        }
        let parts = candidate.previous.enumerated().map { index, hint -> String in
            let weight = hint.weightLbs == 0 ? "BW" : String(format: "%g", hint.weightLbs)
            return index == 0 && hint.weightLbs != 0 ? "\(weight) lbs × \(hint.reps)" : "\(weight) × \(hint.reps)"
        }
        return "Last: " + parts.joined(separator: ", ")
    }
}
