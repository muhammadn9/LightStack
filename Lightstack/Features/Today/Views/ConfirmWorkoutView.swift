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
            HStack {
                Text("Exercise Plan")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text("Tap × to remove")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            ForEach(todayViewModel.exercises) { exercise in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(exercise.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(exercise.muscleGroup)
                            .font(.caption)
                            .foregroundStyle(AppTheme.accentSecondary)

                        // Badge pills row
                        let weightText: String? = {
                            guard let note = exercise.coachNote else { return nil }
                            let prefix = "Target: "
                            if note.hasPrefix(prefix) {
                                return String(note.dropFirst(prefix.count))
                            }
                            return note
                        }()

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                if let sets = exercise.targetSets, sets > 0 {
                                    confirmBadge("\(sets) sets", color: AppTheme.accent)
                                }
                                if let reps = exercise.targetReps, !reps.isEmpty {
                                    confirmBadge(reps + " reps", color: AppTheme.accentSecondary)
                                }
                                if let weight = weightText, !weight.isEmpty {
                                    confirmBadge(weight, color: .orange)
                                }
                                if let rir = exercise.targetRir, !rir.isEmpty {
                                    confirmBadge("RIR \(rir)", color: .purple)
                                }
                                if let rest = exercise.restSeconds, rest > 0 {
                                    confirmBadge("\(rest)s rest", color: .teal)
                                }
                            }
                        }
                    }

                    Spacer()

                    Button(action: {
                        todayViewModel.applyModification(
                            .removeExercise(name: exercise.name),
                            preserveLoggedSets: false
                        )
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(AppTheme.warning)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .cardStyle()
    }

    private func confirmBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
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
