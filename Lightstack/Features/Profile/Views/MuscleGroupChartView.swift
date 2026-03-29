import SwiftUI

/// Horizontal bar chart showing sets per muscle group with volume-based color intensity.
struct MuscleGroupChartView: View {
    let setsPerGroup: [String: Int]
    let volumePerGroup: [String: Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Training Volume by Muscle Group")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            if sortedGroups.isEmpty {
                Text("No data yet")
                    .font(.subheadline)
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
                .font(.subheadline.weight(.medium))
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
                .font(.subheadline.bold())
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
        setsPerGroup.values.max() ?? 1
    }

    private var maxVolume: Double {
        volumePerGroup.values.max() ?? 1
    }

    private func barWidth(sets: Int, maxWidth: CGFloat) -> CGFloat {
        let proportion = Double(sets) / Double(maxSets)
        return maxWidth * proportion
    }

    private func barOpacity(volume: Double) -> Double {
        let proportion = volume / maxVolume
        return 0.4 + (proportion * 0.6) // Range: 0.4 to 1.0
    }
}
