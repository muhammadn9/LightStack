import SwiftUI

/// Single logged set display with purple-themed styling.
struct SetRowView: View {
    let workoutSet: WorkoutSet

    var body: some View {
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
}
