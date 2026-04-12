import SwiftUI

/// Compact flame icon + count badge with orange glow when active.
struct StreakView: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .foregroundStyle(count > 0 ? AppTheme.streakFlame : AppTheme.textSecondary)
                .shadow(color: count > 0 ? AppTheme.streakFlame.opacity(0.5) : .clear, radius: 4)
            Text("\(count)")
                .font(AppTheme.plexMono(14, weight: .bold))
                .foregroundStyle(count > 0 ? AppTheme.textPrimary : AppTheme.textSecondary)
            if count != 1 {
                Text("days")
                    .font(AppTheme.caveat(10))
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                Text("day")
                    .font(AppTheme.caveat(10))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}
