import SwiftUI

/// The AI coach (what it saw in the video): loading row, then verdict, what went well and up to three numbered
/// fixes, or a calm "nothing extra" row when it sees nothing beyond the measurements.
struct FormCoachSection: View {

    let feedback: FormFeedback?
    let isLoading: Bool
    let failure: AIFailureReason?
    let onSelectFix: (FormFix) -> Void
    let canSeek: (FormFix) -> Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FormSectionHeader(title: "Coach (from your video)", systemImage: "sparkles")
            if isLoading {
                loadingRow
            } else if let feedback {
                content(feedback)
            } else if let failure {
                unavailableRow(failure)
            }
        }
    }

    // MARK: States

    private var loadingRow: some View {
        HStack(spacing: 12) {
            ProgressView().tint(AppTheme.accent)
            Text("Coach is reviewing your set…")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
            Spacer(minLength: 0)
        }
        .formCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("formResults.coachLoading")
    }

    private func unavailableRow(_ reason: AIFailureReason) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coach feedback unavailable. \(reason.message) The measurements below are from on-device tracking.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
            Button(action: onRetry) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(minHeight: 36)
            }
            .accessibilityIdentifier("formResults.coachRetry")
        }
        .formCard()
        .accessibilityIdentifier("formResults.coachUnavailable")
    }

    @ViewBuilder private func content(_ feedback: FormFeedback) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !feedback.verdict.isEmpty {
                Text(feedback.verdict)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("formResults.verdict")
            }
            ForEach(Array(feedback.positives.enumerated()), id: \.offset) { _, text in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.success)
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .formCard()

        if feedback.fixes.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(AppTheme.success)
                Text("Nothing extra spotted in the frames")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer(minLength: 0)
            }
            .formCard()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("formResults.nothingExtra")
        }

        ForEach(Array(feedback.fixes.enumerated()), id: \.element.id) { index, fix in
            FixCard(number: index + 1, fix: fix, canSeek: canSeek(fix)) { onSelectFix(fix) }
                .accessibilityIdentifier("formResults.fix.\(index)")
        }
    }
}

private struct FixCard: View {
    let number: Int
    let fix: FormFix
    let canSeek: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(number)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.onAccent)
                        .frame(width: 26, height: 26)
                        .background(AppTheme.accent, in: Circle())
                    Text(fix.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if canSeek {
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                if !fix.why.isEmpty {
                    Text(fix.why)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !fix.cue.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NEXT SET")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.accent)
                        Text(fix.cue)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                if !fix.reps.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(fix.reps, id: \.self) { RepChip(number: $0) }
                    }
                }
            }
            .formCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(canSeek ? "Shows this moment in the replay" : "")
    }
}
