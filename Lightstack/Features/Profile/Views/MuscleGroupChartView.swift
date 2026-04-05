import SwiftUI

/// Horizontal bar chart showing sets per muscle group with volume-based color intensity.
struct MuscleGroupChartView: View {
    let setsPerGroup: [String: Int]
    let volumePerGroup: [String: Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Training Volume by Muscle Group")
                .font(AppTheme.playfairItalic(16, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            if sortedGroups.isEmpty {
                Text("No data yet")
                    .font(AppTheme.caveat(14))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 12) {
                    ForEach(sortedGroups, id: \.group) { item in
                        barRow(group: item.group, sets: item.sets, volume: item.volume)
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Bar Row

    private func barRow(group: String, sets: Int, volume: Double) -> some View {
        HStack(spacing: 12) {
            Text(group)
                .font(AppTheme.caveat(14, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 80, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppTheme.surfaceElevated)
                        .frame(height: 24)

                    // Foreground bar
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.accentGradientStart.opacity(barOpacity(volume: volume)),
                                    AppTheme.accentGradientEnd.opacity(barOpacity(volume: volume))
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: barWidth(sets: sets, maxWidth: geometry.size.width), height: 24)
                }
            }
            .frame(height: 24)

            Text("\(sets)")
                .font(AppTheme.plexMono(14, weight: .bold))
                .foregroundStyle(AppTheme.accentSecondary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    // MARK: - Helpers

    private var sortedGroups: [(group: String, sets: Int, volume: Double)] {
        setsPerGroup.keys.map { group in
            (group: group, sets: setsPerGroup[group] ?? 0, volume: volumePerGroup[group] ?? 0)
        }
        .sorted { $0.sets > $1.sets }
    }

    private var maxSets: Int {
        let max = setsPerGroup.values.max() ?? 0
        return max > 0 ? max : 1  // Ensure never 0 to avoid division by zero
    }

    private var maxVolume: Double {
        let max = volumePerGroup.values.max() ?? 0
        return max > 0 ? max : 1  // Ensure never 0 to avoid division by zero
    }

    private func barWidth(sets: Int, maxWidth: CGFloat) -> CGFloat {
        guard maxSets > 0, maxWidth.isFinite, maxWidth > 0 else { return 0 }
        let proportion = Double(sets) / Double(maxSets)
        guard proportion.isFinite else { return 0 }
        let result = maxWidth * proportion
        return result.isFinite ? result : 0
    }

    private func barOpacity(volume: Double) -> Double {
        guard maxVolume > 0 else { return 0.4 }
        let proportion = volume / maxVolume
        guard proportion.isFinite else { return 0.4 }
        return 0.4 + (proportion * 0.6) // Range: 0.4 to 1.0
    }
}
