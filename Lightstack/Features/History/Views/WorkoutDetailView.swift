import SwiftUI

/// Full detail view for a past workout session.
/// Shows complete set log table, AI progression note, and user note.
struct WorkoutDetailView: View {
    let workout: Workout
    let viewModel: HistoryViewModel

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppTheme.sectionSpacing) {
                    headerSection
                    exercisesSection
                    if workout.setupNote != nil {
                        setupNoteSection
                    }
                    if workout.userNote != nil {
                        userNoteSection
                    }
                    if workout.aiProgressionNote != nil {
                        aiNoteSection
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(workout.workoutType)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            Text(formatDate(workout.date))
                .font(.title3.bold())
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
                .font(.caption)
                .foregroundStyle(AppTheme.accentSecondary)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppTheme.surfaceElevated)
        .clipShape(Capsule())
    }

    // MARK: - Exercises Section

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(exercises) { exercise in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(exercise.name)
                            .font(.headline)
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Text(exercise.muscleGroup)
                            .font(.caption)
                            .foregroundStyle(AppTheme.accentSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.accent.opacity(0.2))
                            .clipShape(Capsule())
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

    // MARK: - Setup Note Section

    private var setupNoteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "pencil.and.list.clipboard")
                    .foregroundStyle(AppTheme.accent)
                Text("Pre-Workout Notes")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
            }

            Text(workout.setupNote ?? "")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    // MARK: - AI Note Section

    private var aiNoteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(AppTheme.accent)
                Text("AI Progression Note")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
            }

            Text(workout.aiProgressionNote ?? "")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    // MARK: - User Note Section

    private var userNoteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .foregroundStyle(AppTheme.accentSecondary)
                Text("My Notes")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
            }

            Text(workout.userNote ?? "")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
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
