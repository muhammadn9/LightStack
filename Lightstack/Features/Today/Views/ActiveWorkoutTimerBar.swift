import SwiftUI

// MARK: - Timer Bar

/// Top bar showing workout type, elapsed time, pause/cancel controls, and running volume.
struct ActiveWorkoutTimerBar: View {
    @ObservedObject var viewModel: ActiveWorkoutViewModel
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
                    Text(viewModel.formattedElapsedTime)
                        .font(AppTheme.plexMono(18, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .monospacedDigit()
                    Button(action: { viewModel.togglePause() }) {
                        Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.accent)
                    }
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
        }
    }
}
