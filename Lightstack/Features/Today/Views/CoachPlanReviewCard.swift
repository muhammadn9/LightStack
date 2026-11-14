import SwiftUI

/// Short rest text for set rows: "2:00" from two minutes up, "90s" below.
enum CoachRestFormat {
    static func short(_ seconds: Int) -> String {
        guard seconds >= 120 else { return "\(seconds)s" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// A calm heads-up under the plan header: the muscles of this workout were trained hours ago.
struct PlanRecencyBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(AppTheme.accent)
            Text(message)
                .font(AppTheme.caveat(14))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plan.recencyWarning")
    }
}

/// "Coach's plan" at the top of the plan preview: the summary, what the coach changed or wanted to change, and the
/// checks the app ran (with what it had to adjust).
struct CoachPlanReviewCard: View {
    let review: CoachPlanReview
    /// Lines shown while collapsed.
    private static let collapsedLimit = 3

    @State private var expanded = false

    private var notable: [LiftDecision] { review.decisions.filter(\.isNotable) }
    private var adjusted: [PlanCheck] { review.adjustedChecks }
    private var totalLines: Int { notable.count + adjusted.count }
    private var isLong: Bool { totalLines > Self.collapsedLimit + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .foregroundStyle(AppTheme.accent)
                Text("Coach's plan")
                    .font(AppTheme.playfairItalic(16, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer(minLength: 8)
                if review.engineOnly {
                    Text("From your log")
                        .font(AppTheme.caveat(13, weight: .bold))
                        .foregroundStyle(AppTheme.warning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AppTheme.warning.opacity(0.15))
                        .clipShape(Capsule())
                        .accessibilityIdentifier("plan.coachReview.engineOnly")
                }
            }

            if !review.summary.isEmpty {
                Text(review.summary)
                    .font(AppTheme.caveat(14))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("plan.coachReview.summary")
            }

            ForEach(Array(visibleDecisions.enumerated()), id: \.offset) { index, decision in
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(decision.name): \(decision.label)")
                        .font(AppTheme.caveat(13, weight: .bold))
                        .foregroundStyle(decision.held == nil ? AppTheme.textPrimary : AppTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    if !decision.reason.isEmpty {
                        Text(decision.reason)
                            .font(AppTheme.caveat(12))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("plan.coachReview.decision.\(index)")
            }

            if !review.checks.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: adjusted.isEmpty ? "checkmark.shield" : "shield.lefthalf.filled")
                            .font(.system(size: 11))
                        Text(review.checksLine)
                            .accessibilityIdentifier("plan.coachReview.checks")
                    }
                    .font(AppTheme.caveat(12, weight: .bold))
                    .foregroundStyle(adjusted.isEmpty ? AppTheme.success : AppTheme.warning)
                    ForEach(Array(visibleAdjusted.enumerated()), id: \.offset) { index, check in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(check.title)
                                .font(AppTheme.caveat(11, weight: .bold))
                            ForEach(check.adjustments, id: \.self) { line in
                                Text(line)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .font(AppTheme.caveat(11))
                        .foregroundStyle(AppTheme.textSecondary)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("plan.coachReview.adjusted.\(index)")
                    }
                }
            }

            if isLong {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Text(expanded ? "Show less" : "Show all (\(totalLines))")
                        .font(AppTheme.caveat(13, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(minHeight: 32, alignment: .leading)
                }
                .accessibilityIdentifier("plan.coachReview.toggle")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.coachReview")
    }

    private var visibleDecisions: [LiftDecision] {
        guard isLong, !expanded else { return notable }
        return Array(notable.prefix(Self.collapsedLimit))
    }

    private var visibleAdjusted: [PlanCheck] {
        guard isLong, !expanded else { return adjusted }
        return Array(adjusted.prefix(max(0, Self.collapsedLimit - notable.count)))
    }
}
