import SwiftUI

/// Single logged set display with purple-themed styling.
/// Pass `exercise` to enable cardio-specific rendering; defaults to strength display.
struct SetRowView: View {
    let workoutSet: WorkoutSet
    var exercise: Exercise? = nil

    var body: some View {
        if exercise?.trackingType == .cardio {
            cardioBody
        } else {
            strengthBody
        }
    }

    private var strengthBody: some View {
        HStack(spacing: 6) {
            // Set number badge
            Text("\(workoutSet.setNumber)")
                .font(AppTheme.plexMono(10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(AppTheme.accent)
                .clipShape(Circle())

            Text(String(format: "%.1f", workoutSet.weightLbs))
                .font(AppTheme.caveat(13))
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.textPrimary)
            Text("lbs")
                .font(AppTheme.caveat(11))
                .foregroundStyle(AppTheme.textSecondary)

            Text("x")
                .font(AppTheme.caveat(11))
                .foregroundStyle(AppTheme.textSecondary)

            Text("\(workoutSet.reps)")
                .font(AppTheme.caveat(13))
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.textPrimary)
            Text("reps")
                .font(AppTheme.caveat(11))
                .foregroundStyle(AppTheme.textSecondary)

            Text("@")
                .font(AppTheme.caveat(11))
                .foregroundStyle(AppTheme.textSecondary)

            Text("RIR \(workoutSet.rir)")
                .font(AppTheme.caveat(13))
                .fontWeight(.medium)
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            if workoutSet.isPR {
                Image(systemName: "star.fill")
                    .foregroundStyle(AppTheme.warning)
                    .font(.caption)
                    .shadow(color: AppTheme.warning.opacity(0.5), radius: 4)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(AppTheme.surfaceElevated.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    private var cardioBody: some View {
        HStack(spacing: 6) {
            // Set number badge
            Text("\(workoutSet.setNumber)")
                .font(AppTheme.plexMono(10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(AppTheme.accent)
                .clipShape(Circle())

            let summary = CardioFormatting.loggedSummary(
                durationSeconds: workoutSet.durationSeconds,
                distanceMiles: workoutSet.distanceMiles,
                inclineLevel: workoutSet.inclineLevel
            )
            Text(summary.isEmpty ? "—" : summary)
                .font(AppTheme.caveat(13))
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(AppTheme.surfaceElevated.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }
}
