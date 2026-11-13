import SwiftUI

/// Rep count, form score ring and tracking chip.
struct FormSummaryRow: View {

    let repDisplay: FormResultsViewModel.RepDisplay
    let score: Int?
    let status: TrackingStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(repDisplay.value)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.accent)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .accessibilityLabel(repDisplay.value)
                        .accessibilityIdentifier("formResults.repCount")
                    Text(repDisplay.caption)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer(minLength: 8)
                if let score { ScoreRing(score: score) }
            }
            trackingChip
        }
        .formCard()
    }

    private var trackingChip: some View {
        let (text, color, icon): (String, Color, String) = {
            switch status {
            case .good: return ("Tracking: Good", AppTheme.success, "checkmark.circle.fill")
            case .partial: return ("Tracking: Partial", AppTheme.warning, "exclamationmark.circle.fill")
            case .insufficient: return ("Couldn't track", AppTheme.destructive, "eye.slash.fill")
            }
        }()
        return Label(text, systemImage: icon)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14), in: Capsule())
            .accessibilityIdentifier("formResults.tracking")
    }
}

private struct ScoreRing: View {
    let score: Int

    private var color: Color {
        score >= 80 ? AppTheme.success : (score >= 60 ? AppTheme.warning : AppTheme.destructive)
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(AppTheme.surfaceElevated, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(score, 0), 100)) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(score)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: 72, height: 72)
            Text("Form score")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Form score \(score) out of 100")
        .accessibilityIdentifier("formResults.score")
    }
}
