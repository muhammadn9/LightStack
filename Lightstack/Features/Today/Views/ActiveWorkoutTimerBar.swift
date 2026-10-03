import SwiftUI

// MARK: - Timer Bar

/// Top bar showing workout type, elapsed time, pause/cancel controls, and running volume.
struct ActiveWorkoutTimerBar: View {
    let viewModel: ActiveWorkoutViewModel
    let workoutType: String?
    let runningVolume: Double
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Left: workout type + timer
            VStack(alignment: .leading, spacing: 3) {
                Text(workoutType ?? "Workout")
                    .font(AppTheme.playfairItalic(11))
                    .foregroundStyle(AppTheme.accentSecondary)
                HStack(spacing: 7) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .accessibilityLabel("Cancel workout")
                    .accessibilityHint("Ends the current workout session")
                    ElapsedClockView(clock: viewModel.clock, onTogglePause: { viewModel.togglePause() })
                }
            }

            Spacer()

            // Right: volume
            if runningVolume > 0 {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Volume")
                        .font(AppTheme.caveat(12))
                        .foregroundStyle(AppTheme.accentSecondary)
                    Text(String(format: "%.0f lbs", runningVolume))
                        .font(AppTheme.plexMono(15, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(.bar)
        .overlay(alignment: .bottom) {
            InkDivider()
        }
    }
}

/// Elapsed time + pause button. Owns the per-second observation of the clock.
private struct ElapsedClockView: View {
    @ObservedObject var clock: WorkoutClock
    let onTogglePause: () -> Void

    var body: some View {
        Text(clock.formattedElapsedTime)
            .font(AppTheme.plexMono(18, weight: .medium))
            .foregroundStyle(AppTheme.textPrimary)
            .monospacedDigit()
        Button(action: onTogglePause) {
            Image(systemName: clock.isPaused ? "play.fill" : "pause.fill")
                .font(.subheadline)
                .foregroundStyle(AppTheme.accent)
        }
        .accessibilityLabel(clock.isPaused ? "Resume workout" : "Pause workout")
    }
}

// MARK: - Exercise Navigation Buttons

/// Previous / index-label / next / add-exercise navigation block.
struct ExerciseNavButtons: View {
    let currentIndex: Int
    let totalCount: Int
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if currentIndex > 0 {
                Button(action: onPrevious) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: AppTheme.minTouchSize, height: AppTheme.minTouchSize)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
                }
                .accessibilityLabel("Previous exercise")
            }
            Text("\(currentIndex + 1)/\(totalCount)")
                .font(AppTheme.plexMono(16))
                .foregroundStyle(AppTheme.textSecondary)
            if currentIndex < totalCount - 1 {
                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: AppTheme.minTouchSize, height: AppTheme.minTouchSize)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
                }
                .accessibilityLabel("Next exercise")
            }
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: AppTheme.minTouchSize, height: AppTheme.minTouchSize)
                    .background(AppTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
            }
            .accessibilityLabel("Add exercise")
        }
    }
}
