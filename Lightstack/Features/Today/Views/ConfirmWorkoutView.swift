import SwiftUI

/// Shows the AI-generated workout plan for user confirmation before starting.
struct ConfirmWorkoutView: View {
    @ObservedObject var todayViewModel: TodayViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                exerciseList
                confirmButton
            }
            .padding(16)
        }
        .themedBackground()
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(AppTheme.accent)
            Text("Workout Ready")
                .font(.title2.bold())
                .foregroundStyle(AppTheme.textPrimary)
            Text("Your AI coach prepared \(todayViewModel.exercises.count) exercises")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var exerciseList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercise Plan")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            ForEach(todayViewModel.exercises) { exercise in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(exercise.muscleGroup)
                            .font(.caption)
                            .foregroundStyle(AppTheme.accentSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let sets = exercise.targetSets {
                            Text("\(sets) sets")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                        }
                        if let reps = exercise.targetReps {
                            Text(reps)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
                .padding(12)
                .background(AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .cardStyle()
    }

    private var confirmButton: some View {
        Button(action: { todayViewModel.confirmAndStartWorkout() }) {
            HStack {
                Image(systemName: "play.fill")
                Text("Start Workout")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.accentGradient)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
        .padding(.horizontal, 4)
    }
}
