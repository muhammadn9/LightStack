import SwiftUI

/// The structured post-workout review: overall read, per-exercise notes with an outcome badge,
/// miss analysis, the next-session targets table and recurring flags.
/// Used on the post-workout screen and in History.
struct CoachSessionReviewView: View {
    let review: SessionReview

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(AppTheme.accent)
                Text("Coach's review")
                    .font(AppTheme.playfairItalic(16, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            let read = review.overallRead.trimmingCharacters(in: .whitespacesAndNewlines)
            if !read.isEmpty {
                Text(read)
                    .font(AppTheme.caveat(15))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("review.overallRead")
            }

            ForEach(Array(review.exercises.enumerated()), id: \.offset) { index, exercise in
                exerciseBlock(exercise, index: index)
            }

            nextTargets
            flags
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review.card")
    }

    // MARK: - Per-exercise

    private func exerciseBlock(_ exercise: ExerciseReview, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(exercise.name)
                    .font(AppTheme.playfair(14, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(Self.outcomeTitle(exercise.outcome))
                    .font(AppTheme.caveat(12, weight: .bold))
                    .foregroundStyle(Self.outcomeColor(exercise.outcome))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                    .background(Self.outcomeColor(exercise.outcome).opacity(0.15))
                    .clipShape(Capsule())
                    .fixedSize()
                    .accessibilityIdentifier("review.outcome.\(index)")
            }
            let notes = exercise.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty {
                Text(notes)
                    .font(AppTheme.caveat(13))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let miss = exercise.missAnalysis {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(Self.causeTitle(miss.cause)) → \(Self.decisionTitle(miss.decision))")
                        .font(AppTheme.caveat(13, weight: .bold))
                        .foregroundStyle(AppTheme.warning)
                    if !miss.reason.isEmpty {
                        Text(miss.reason)
                            .font(AppTheme.caveat(11))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("review.miss.\(index)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review.exercise.\(index)")
    }

    // MARK: - Next session

    @ViewBuilder
    private var nextTargets: some View {
        let rows = review.exercises.enumerated().compactMap { index, ex in
            ex.nextTarget.map { (index, ex.name, $0) }
        }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Next session targets")
                    .font(AppTheme.playfairItalic(14, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Exercise")
                        Spacer(minLength: 8)
                        Text("Goal")
                    }
                    .font(AppTheme.caveat(11, weight: .bold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .accessibilityHidden(true)
                    Divider()
                    ForEach(rows, id: \.0) { index, name, target in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(name)
                                .font(AppTheme.caveat(13))
                                .foregroundStyle(AppTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text(target.text)
                                .font(AppTheme.plexMono(13, weight: .medium))
                                .foregroundStyle(AppTheme.accent)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("review.nextTarget.\(index)")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("review.nextTargets")
        }
    }

    @ViewBuilder
    private var flags: some View {
        if !review.recurringFlags.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Keep an eye on")
                    .font(AppTheme.playfairItalic(14, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                ForEach(Array(review.recurringFlags.enumerated()), id: \.offset) { index, flag in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.warning)
                            .padding(.top, 3)
                        Text(flag)
                            .font(AppTheme.caveat(13))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("review.flag.\(index)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Text

    static func outcomeTitle(_ outcome: ExerciseOutcome) -> String {
        switch outcome {
        case .pr: return "PR"
        case .hold: return "Hold"
        case .regression: return "Regression"
        case .missed: return "Missed"
        case .new: return "New"
        }
    }

    static func outcomeColor(_ outcome: ExerciseOutcome) -> Color {
        switch outcome {
        case .pr: return AppTheme.success
        case .hold: return AppTheme.accentSecondary
        case .regression: return AppTheme.warning
        case .missed: return AppTheme.destructive
        case .new: return AppTheme.textSecondary
        }
    }

    static func causeTitle(_ cause: MissCause) -> String {
        switch cause {
        case .lowEnergy: return "Low energy"
        case .poorRecovery: return "Poor recovery"
        case .painOrForm: return "Pain or form"
        case .strengthLoss: return "Strength loss"
        case .unknown: return "Unclear cause"
        }
    }

    static func decisionTitle(_ decision: MissDecision) -> String {
        switch decision {
        case .retry: return "Retry same target"
        case .reduceAndRebuild: return "Drop 5-10% and rebuild"
        case .holdOrSwap: return "Hold or swap"
        }
    }
}
