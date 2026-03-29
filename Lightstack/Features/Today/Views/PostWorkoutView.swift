import SwiftUI

/// Post-workout summary screen with purple radiant theme.
struct PostWorkoutView: View {
    @ObservedObject var todayViewModel: TodayViewModel
    @State private var userNote: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.sectionSpacing) {
                completionHeader
                sessionStatsRow
                aiNoteSection
                userNoteSection
                saveButton
            }
            .padding(20)
        }
    }

    // MARK: - Completion Header

    private var completionHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.success.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(AppTheme.success)
                    .shadow(color: AppTheme.success.opacity(0.3), radius: 8)
            }

            Text("Workout Complete")
                .font(.title2.bold())
                .foregroundStyle(AppTheme.textPrimary)

            Text("Great session! Here's your coach's feedback.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }

    // MARK: - Session Stats

    private var sessionStatsRow: some View {
        HStack(spacing: 16) {
            if let duration = todayViewModel.sessionDurationMinutes {
                statPill(icon: "clock", value: "\(duration)", unit: "min")
            }
            statPill(icon: "scalemass", value: String(format: "%.0f", sessionVolume), unit: "lbs")
            statPill(icon: "figure.strengthtraining.traditional", value: "\(todayViewModel.exercises.count)", unit: "exercises")
        }
    }

    private func statPill(icon: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(AppTheme.accentSecondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var sessionVolume: Double {
        var volume = 0.0
        for exercise in todayViewModel.exercises {
            for s in todayViewModel.loggedSetsForExercise(exercise.id) {
                volume += s.weightLbs * Double(s.reps)
            }
        }
        return volume
    }

    // MARK: - AI Progression Note

    private var aiNoteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(AppTheme.accent)
                    .symbolEffect(.pulse, options: .repeating)
                Text("Coach's Progression Note")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
            }

            if todayViewModel.isLoadingNote {
                HStack {
                    ProgressView()
                        .tint(AppTheme.accent)
                    Text("Analyzing your session...")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding()
            } else if let note = todayViewModel.aiProgressionNote {
                VStack(alignment: .leading, spacing: 0) {
                    AppTheme.accentGradient
                        .frame(height: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 2))

                    Text(note)
                        .font(.body)
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - User Note

    private var userNoteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Notes (optional)")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            TextField("How did it feel? Anything to remember?",
                      text: $userNote,
                      axis: .vertical)
                .padding(14)
                .background(AppTheme.surface)
                .foregroundStyle(AppTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .lineLimit(3...6)
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button(action: { todayViewModel.saveWorkout(userNote: userNote.isEmpty ? nil : userNote) }) {
            HStack {
                Image(systemName: "square.and.arrow.down")
                Text("Save Workout")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.accentGradient)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .shadow(color: AppTheme.accent.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .disabled(todayViewModel.isLoadingNote)
        .opacity(todayViewModel.isLoadingNote ? 0.6 : 1)
    }
}
