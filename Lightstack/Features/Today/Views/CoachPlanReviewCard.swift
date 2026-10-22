import SwiftUI

/// Short rest text for set rows: "2:00" from two minutes up, "90s" below.
enum CoachRestFormat {
    static func short(_ seconds: Int) -> String {
        guard seconds >= 120 else { return "\(seconds)s" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// "Coach's review" at the top of the plan preview: verdict, summary, the edits the coach
/// made to the draft (each with its reason) and the app's own safeguards.
struct CoachPlanReviewCard: View {
    let review: CoachPlanReview
    /// Lines shown while collapsed.
    private static let collapsedLimit = 2

    @State private var expanded = false

    private var appliedChanges: [PlanChange] { review.appliedChanges }
    private var totalLines: Int { appliedChanges.count + review.safeguards.count }
    private var isLong: Bool { totalLines > Self.collapsedLimit + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .foregroundStyle(AppTheme.accent)
                Text("Coach's review")
                    .font(AppTheme.playfairItalic(16, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer(minLength: 8)
                Text(review.verdict == .adjusted ? "Adjusted" : "Sound")
                    .font(AppTheme.caveat(13, weight: .bold))
                    .foregroundStyle(review.verdict == .adjusted ? AppTheme.warning : AppTheme.success)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background((review.verdict == .adjusted ? AppTheme.warning : AppTheme.success).opacity(0.15))
                    .clipShape(Capsule())
                    .accessibilityIdentifier("plan.coachReview.verdict")
            }

            if !review.summary.isEmpty {
                Text(review.summary)
                    .font(AppTheme.caveat(14))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("plan.coachReview.summary")
            }

            let changes = visibleChanges
            ForEach(Array(changes.enumerated()), id: \.offset) { index, change in
                VStack(alignment: .leading, spacing: 1) {
                    Text(Self.changeLine(change))
                        .font(AppTheme.caveat(13, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note = change.note, !note.isEmpty {
                        Text(note)
                            .font(AppTheme.caveat(11))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("plan.coachReview.change.\(index)")
            }

            let safeguards = visibleSafeguards
            if !safeguards.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(safeguards.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .top, spacing: 5) {
                            Image(systemName: "shield")
                                .font(.system(size: 10))
                            Text(line)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(AppTheme.caveat(11))
                        .foregroundStyle(AppTheme.textSecondary)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("plan.coachReview.safeguard.\(index)")
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

    private var visibleChanges: [PlanChange] {
        guard isLong, !expanded else { return appliedChanges }
        return Array(appliedChanges.prefix(Self.collapsedLimit))
    }

    private var visibleSafeguards: [String] {
        guard isLong, !expanded else { return review.safeguards }
        let room = max(0, Self.collapsedLimit - appliedChanges.count)
        return Array(review.safeguards.prefix(room))
    }

    /// "Row: cut to one top set — back trained 2 days ago"
    static func changeLine(_ change: PlanChange) -> String {
        var line = change.exercise
        if !change.detail.isEmpty { line += ": \(change.detail)" }
        if !change.reason.isEmpty { line += " — \(change.reason)" }
        return line
    }
}
