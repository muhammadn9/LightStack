import SwiftUI

/// Full detail view for a past workout session.
/// Shows complete set log table, AI progression note, and user note.
struct WorkoutDetailView: View {
    @EnvironmentObject var environment: AppEnvironment
    let workout: Workout
    let viewModel: HistoryViewModel

    @State private var repeatWorkoutContext: RepeatWorkoutContext?

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppTheme.sectionSpacing) {
                    headerSection
                    exercisesSection
                    NoteCardView(
                        icon: "pencil.and.list.clipboard",
                        iconColor: AppTheme.accent,
                        title: "Pre-Workout Notes",
                        content: workout.setupNote
                    )
                    NoteCardView(
                        icon: "note.text",
                        iconColor: AppTheme.accentSecondary,
                        title: "My Notes",
                        content: workout.userNote
                    )
                    NoteCardView(
                        icon: "sparkles",
                        iconColor: AppTheme.accent,
                        title: "AI Progression Note",
                        content: workout.aiProgressionNote
                    )

                    repeatButton
                        .padding(.bottom, 8)
                }
                .padding(20)
            }
        }
        .navigationTitle(workout.workoutType)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .fullScreenCover(item: $repeatWorkoutContext) { ctx in
            WorkoutSessionSheet(
                todayViewModel: ctx.todayViewModel,
                workoutType: ctx.workoutType,
                mode: .repeatExisting,
                onDismiss: { repeatWorkoutContext = nil }
            )
            .environmentObject(environment)
        }
    }

    // MARK: - Repeat Button

    private var repeatButton: some View {
        Button(action: startRepeatWorkout) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.clockwise")
                Text("Use This Workout Today")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppTheme.accentGradient)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
    }

    private func startRepeatWorkout() {
        guard let userId = environment.authService.currentUser()?.userId else { return }
        let vm = environment.makeInlineTodayViewModel()
        vm.setUserIdSkipRestore(userId)
        let exs = viewModel.fetchExercises(workoutId: workout.id)
        vm.loadExistingWorkout(exercises: exs, workoutType: workout.workoutType)
        repeatWorkoutContext = RepeatWorkoutContext(todayViewModel: vm, workoutType: workout.workoutType)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            Text(formatDate(workout.date))
                .font(AppTheme.playfair(18, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            HStack(spacing: 16) {
                if let duration = workout.durationMinutes {
                    statPill(icon: "clock", value: "\(duration) min")
                }
                statPill(icon: "scalemass", value: formatVolume(totalVolume))
            }
        }
        .cardStyle()
    }

    private func statPill(icon: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(AppTheme.caveat(11))
                .foregroundStyle(AppTheme.accentSecondary)
            Text(value)
                .font(AppTheme.plexMono(10))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    // MARK: - Exercises Section

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(exercises) { exercise in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(exercise.name)
                            .font(AppTheme.playfairItalic(16, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Text(exercise.muscleGroup)
                            .font(AppTheme.caveat(11))
                            .foregroundStyle(AppTheme.accentSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.accent.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    }

                    VStack(spacing: 4) {
                        ForEach(setsForExercise(exercise.id)) { set in
                            SetRowView(workoutSet: set)
                        }
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Helpers

    private var exercises: [Exercise] {
        viewModel.fetchExercises(workoutId: workout.id)
    }

    private func setsForExercise(_ exerciseId: UUID) -> [WorkoutSet] {
        viewModel.fetchSets(exerciseId: exerciseId)
    }

    private var totalVolume: Double {
        var volume = 0.0
        for exercise in exercises {
            for set in setsForExercise(exercise.id) {
                volume += set.weightLbs * Double(set.reps)
            }
        }
        return volume
    }

    private func formatDate(_ date: Date) -> String {
        DateFormatter.weekdayMonthDayYear.string(from: date)
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "%.1fM lbs", volume / 1_000_000)
        } else if volume >= 1_000 {
            return String(format: "%.0fK lbs", volume / 1_000)
        }
        return String(format: "%.0f lbs", volume)
    }
}

// MARK: - Repeat Workout Support

private struct RepeatWorkoutContext: Identifiable {
    let id = UUID()
    let todayViewModel: TodayViewModel
    let workoutType: String
}
