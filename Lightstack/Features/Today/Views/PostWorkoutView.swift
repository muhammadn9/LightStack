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
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .fill(AppTheme.success.opacity(0.1))
                    .frame(width: 88, height: 88)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                            .stroke(AppTheme.success.opacity(0.3), lineWidth: 1)
                    )
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(AppTheme.success)
            }

            Text("Session Complete")
                .font(AppTheme.playfairItalic(22, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Logged to your training journal")
                .font(AppTheme.caveat(15))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 16)
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
                .font(AppTheme.plexMono(16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(unit)
                .font(AppTheme.caveat(10))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
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
                    .font(AppTheme.playfairItalic(16, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            if todayViewModel.isLoadingNote {
                HStack {
                    ProgressView()
                        .tint(AppTheme.accent)
                    Text("Analyzing your session...")
                        .font(AppTheme.caveat(14))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding()
            } else if let note = todayViewModel.aiProgressionNote {
                VStack(alignment: .leading, spacing: 0) {
                    AppTheme.accentGradient
                        .frame(height: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 2))

                    Text(note)
                        .font(AppTheme.caveat(15))
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
        }
    }

    // MARK: - User Note

    private var userNoteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Notes (optional)")
                .font(AppTheme.playfairItalic(16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            TextField("How did it feel? Anything to remember?",
                      text: $userNote,
                      axis: .vertical)
                .padding(14)
                .background(AppTheme.surface)
                .foregroundStyle(AppTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .lineLimit(3...6)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                        .foregroundStyle(AppTheme.accent)
                    }
                }
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button(action: { todayViewModel.saveWorkout(userNote: userNote.isEmpty ? nil : userNote) }) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 13, weight: .semibold))
                Text(todayViewModel.isLoadingNote ? "Analyzing…" : "Save to Training Log")
            }
        }
        .buttonStyle(WaxSealButtonStyle(isSecondary: false))
        .disabled(todayViewModel.isLoadingNote)
        .opacity(todayViewModel.isLoadingNote ? 0.6 : 1)
    }
}
