import SwiftUI

/// Sheet for one day tapped on the week strip: that day's workouts (opening the full
/// detail/edit view), or a prompt to log a workout / mark the day as a rest day.
struct DaySheetView: View {
    @EnvironmentObject var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let date: Date
    let userId: UUID
    /// Called after a rest day is added or removed so callers can refresh.
    let onChange: () -> Void
    /// Called to start the manual entry flow for this day (the sheet dismisses first).
    let onLogWorkout: (Date) -> Void

    @State private var historyViewModel: HistoryViewModel?
    @State private var workouts: [Workout] = []
    @State private var isRestDay = false

    private var title: String { date.formatted(.dateTime.weekday(.wide).month(.wide).day()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if isRestDay {
                        restBanner
                    }
                    if workouts.isEmpty {
                        if !isRestDay { emptyState }
                    } else {
                        ForEach(workouts) { workout in
                            workoutRow(workout)
                        }
                    }
                    if workouts.isEmpty && !isRestDay {
                        actionButton("Log a workout for this day", symbol: "pencil.and.list.clipboard",
                                     id: "daySheet.logWorkout", prominent: true) {
                            let day = date
                            onLogWorkout(day)
                            dismiss()
                        }
                        actionButton("Mark as rest day", symbol: "moon.fill", id: "daySheet.markRest") {
                            environment.localStorageService.addRestDay(userId: userId, date: date)
                            reload()
                            onChange()
                        }
                    }
                }
                .padding(16)
            }
            .themedBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("daySheet.done")
                }
            }
        }
        .accessibilityIdentifier("daySheet")
        .onAppear { reload() }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 28))
                .foregroundStyle(AppTheme.textSecondary)
            Text("No workout")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
                .accessibilityIdentifier("daySheet.noWorkout")
            Text("Nothing logged for this day.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var restBanner: some View {
        ProgressCard(padding: 16) {
            HStack(spacing: 12) {
                Image(systemName: "moon.fill")
                    .foregroundStyle(AppTheme.accentSecondary)
                Text("Rest day")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .accessibilityIdentifier("daySheet.restLabel")
                Spacer()
                Button("Remove rest day") {
                    environment.localStorageService.removeRestDay(userId: userId, date: date)
                    reload()
                    onChange()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .accessibilityIdentifier("daySheet.removeRest")
            }
        }
    }

    @ViewBuilder
    private func workoutRow(_ workout: Workout) -> some View {
        let stats = summary(workout)
        if let historyViewModel {
            NavigationLink {
                WorkoutDetailView(workout: workout, viewModel: historyViewModel)
            } label: {
                ProgressCard(padding: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(workout.workoutType)
                                .font(.headline)
                                .foregroundStyle(AppTheme.textPrimary)
                            HStack(spacing: 12) {
                                Label("\(stats.exercises) exercises", systemImage: "figure.strengthtraining.traditional")
                                Label("\(stats.sets) sets", systemImage: "number")
                                if let duration = workout.durationMinutes, duration > 0 {
                                    Label("\(duration) min", systemImage: "clock")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("daySheet.workout.\(workout.workoutType)")
        }
    }

    private func actionButton(_ label: String, symbol: String, id: String, prominent: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                Text(label)
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(prominent ? ProgressStyle.onAccent : AppTheme.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(prominent ? AppTheme.accent : AppTheme.accent.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func summary(_ workout: Workout) -> (exercises: Int, sets: Int) {
        let exercises = environment.workoutRepository.fetchExercises(workoutId: workout.id)
        let sets = exercises.reduce(0) { $0 + environment.workoutRepository.fetchSets(exerciseId: $1.id).count }
        return (exercises.count, sets)
    }

    private func reload() {
        if historyViewModel == nil { historyViewModel = environment.makeHistoryViewModel() }
        workouts = environment.localStorageService.fetchWorkoutsForDate(userId: userId, date: date)
            .map { Workout(from: $0) }
        isRestDay = environment.localStorageService.isRestDay(userId: userId, date: date)
    }
}
