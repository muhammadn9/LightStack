import SwiftUI

/// Chronological list of past workout sessions.
/// Shows workout type, date, volume, and exercise count.
struct HistoryListView: View {
    @EnvironmentObject var environment: AppEnvironment
    @State private var viewModel: HistoryViewModel?

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()

                if let vm = viewModel {
                    HistoryContentView(viewModel: vm)
                } else {
                    ProgressView()
                        .tint(AppTheme.accent)
                }
            }
            .navigationTitle("History")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear { loadHistory() }
        }
    }

    // MARK: - Helpers

    private func loadHistory() {
        guard let userId = environment.authService.currentUser()?.userId else { return }
        if viewModel == nil {
            let vm = environment.makeHistoryViewModel()
            vm.loadWorkouts(userId: userId)
            viewModel = vm
        }
    }
}

// MARK: - HistoryContentView

private struct HistoryContentView: View {
    @EnvironmentObject var environment: AppEnvironment
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        if viewModel.workouts.isEmpty && !viewModel.isLoading {
            emptyState
        } else {
            VStack(spacing: 0) {
                filterChips
                    .padding(.top, 16)
                List {
                    ForEach(viewModel.workouts) { workout in
                        NavigationLink(destination: WorkoutDetailView(workout: workout, viewModel: viewModel)) {
                            workoutCard(workout: workout)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                if let userId = environment.authService.currentUser()?.userId {
                                    viewModel.deleteWorkout(workout, userId: userId)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundStyle(AppTheme.accent.opacity(0.5))
            Text("No workout history yet")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
            Text("Complete your first workout to see it here")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "All", isSelected: viewModel.filterType == nil) {
                    if let userId = environment.authService.currentUser()?.userId {
                        viewModel.setFilter(nil, userId: userId)
                    }
                }
                ForEach(viewModel.availableTypes, id: \.self) { type in
                    filterChip(label: type, isSelected: viewModel.filterType == type) {
                        if let userId = environment.authService.currentUser()?.userId {
                            viewModel.setFilter(type, userId: userId)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        AppTheme.accentGradient
                    } else {
                        AppTheme.surfaceElevated
                    }
                }
                .clipShape(Capsule())
        }
    }

    private func workoutCard(workout: Workout) -> some View {
        let summary = viewModel.workoutSummary(workout)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(spacing: 2) {
                    Text(DateFormatter.dayAbbreviation.string(from: workout.date).uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(DateFormatter.dayNumber.string(from: workout.date))
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.accent)
                }
                .frame(width: 50)
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.workoutType)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                    HStack(spacing: 12) {
                        Label("\(summary.exerciseCount) exercises", systemImage: "figure.strengthtraining.traditional")
                        if let duration = workout.durationMinutes {
                            Label("\(duration) min", systemImage: "clock")
                        }
                        Label(formatVolume(summary.totalVolume), systemImage: "scalemass")
                    }
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .cardStyle()
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1_000_000 { return String(format: "%.1fM lbs", volume / 1_000_000) }
        if volume >= 1_000 { return String(format: "%.0fK lbs", volume / 1_000) }
        return String(format: "%.0f lbs", volume)
    }
}
