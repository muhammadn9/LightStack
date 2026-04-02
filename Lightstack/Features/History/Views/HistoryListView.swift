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
                    if vm.workouts.isEmpty {
                        emptyState
                    } else {
                        workoutList(vm: vm)
                    }
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

    // MARK: - Workout List

    private func workoutList(vm: HistoryViewModel) -> some View {
        VStack(spacing: 0) {
            filterChips(vm: vm)
                .padding(.top, 16)
            List {
                ForEach(vm.workouts) { workout in
                    NavigationLink(destination: WorkoutDetailView(workout: workout, viewModel: vm)) {
                        workoutCard(workout: workout, vm: vm)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive, action: {
                            deleteWorkout(workout, vm: vm)
                        }) {
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

    // MARK: - Filter Chips

    private func filterChips(vm: HistoryViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "All", isSelected: vm.filterType == nil) {
                    if let userId = environment.authService.currentUser()?.userId {
                        vm.setFilter(nil, userId: userId)
                    }
                }

                ForEach(vm.availableTypes, id: \.self) { type in
                    filterChip(label: type, isSelected: vm.filterType == type) {
                        if let userId = environment.authService.currentUser()?.userId {
                            vm.setFilter(type, userId: userId)
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

    // MARK: - Workout Card

    private func workoutCard(workout: Workout, vm: HistoryViewModel) -> some View {
        let summary = vm.workoutSummary(workout)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Date badge
                VStack(spacing: 2) {
                    Text(dayAbbrev(workout.date))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text("\(dayNumber(workout.date))")
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

    // MARK: - Empty State

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

    // MARK: - Helpers

    private func loadHistory() {
        guard let userId = environment.authService.currentUser()?.userId else { return }
        let vm = environment.makeHistoryViewModel()
        vm.loadWorkouts(userId: userId)
        viewModel = vm
    }

    private func dayAbbrev(_ date: Date) -> String {
        DateFormatter.dayAbbreviation.string(from: date).uppercased()
    }

    private func dayNumber(_ date: Date) -> String {
        DateFormatter.dayNumber.string(from: date)
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "%.1fM lbs", volume / 1_000_000)
        } else if volume >= 1_000 {
            return String(format: "%.0fK lbs", volume / 1_000)
        }
        return String(format: "%.0f lbs", volume)
    }

    private func deleteWorkout(_ workout: Workout, vm: HistoryViewModel) {
        vm.deleteWorkout(workout)
    }
}
