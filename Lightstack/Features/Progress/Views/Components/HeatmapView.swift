import SwiftUI

/// 13-week training heatmap: one column per week (oldest left), Monday at the top.
struct HeatmapView: View {
    /// Weeks x 7 days of set counts; -1 marks days still ahead.
    let cells: [[Int]]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 4) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, count in
                            cell(ProgressStats.heatLevel(count))
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Text("Less").font(.caption2).foregroundStyle(AppTheme.textSecondary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(color(level))
                        .frame(width: 11, height: 11)
                }
                Text("More").font(.caption2).foregroundStyle(AppTheme.textSecondary)
                Spacer()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Training heatmap, last \(cells.count) weeks")
        .accessibilityIdentifier("progress.heatmap")
    }

    private func color(_ level: Int) -> Color {
        switch level {
        case ..<0: return .clear
        case 0: return AppTheme.textSecondary.opacity(0.14)
        default: return AppTheme.accent.opacity([0, 0.3, 0.5, 0.75, 1.0][min(level, 4)])
        }
    }

    private func cell(_ level: Int) -> some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(color(level))
            .overlay {
                if level < 0 {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
            }
            .aspectRatio(1, contentMode: .fit)
    }
}
