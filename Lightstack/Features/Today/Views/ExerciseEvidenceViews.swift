import SwiftUI

/// Shared text helpers for showing what the coach based a target on.
enum EvidenceFormat {
    /// "Oct 20"
    static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    /// "185×6 @1 · 185×6 @1" (engine text is "185×6@1").
    static func sets(_ sets: [String]) -> String {
        sets.map { $0.replacingOccurrences(of: "@", with: " @") }.joined(separator: " · ")
    }

    /// "Last (Oct 20): 185×6 @1 · ..." or nil without history.
    static func lastLine(_ evidence: ExerciseEvidence) -> String? {
        guard !evidence.lastSets.isEmpty else { return nil }
        let when = evidence.lastSessionDate.map { " (\(day($0)))" } ?? ""
        return "Last\(when): \(sets(evidence.lastSets))"
    }

    static func sourceTitle(_ source: ExerciseEvidence.Source) -> String {
        switch source {
        case .engine: return "Calculated from your log"
        case .ai: return "AI estimate"
        case .aiGuarded: return "AI estimate · adjusted"
        }
    }

    static func trendSymbol(_ trend: ProgressionTrend) -> String {
        switch trend {
        case .up: return "arrow.up.right"
        case .flat: return "arrow.right"
        case .down: return "arrow.down.right"
        }
    }

    static func trendColor(_ trend: ProgressionTrend) -> Color {
        switch trend {
        case .up: return AppTheme.success
        case .flat: return AppTheme.textSecondary
        case .down: return AppTheme.warning
        }
    }

    static func trendName(_ trend: ProgressionTrend) -> String {
        switch trend {
        case .up: return "trending up"
        case .flat: return "holding steady"
        case .down: return "trending down"
        }
    }
}

/// Last / best / rationale lines plus the source badge, under a plan card's coach note.
struct PlanEvidenceBlock: View {
    let evidence: ExerciseEvidence
    let exerciseIndex: Int
    @State private var showReasons = false

    private var hasDetails: Bool {
        !evidence.lastSets.isEmpty || evidence.best != nil || evidence.source == .engine
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if hasDetails {
                details
            }
            sourceBadge
            if showReasons, !evidence.guardrailReasons.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(evidence.guardrailReasons, id: \.self) { reason in
                        Text("• \(reason)")
                            .font(AppTheme.caveat(12))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("plan.reasons.\(exerciseIndex)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let last = EvidenceFormat.lastLine(evidence) {
                Text(last)
                    .font(AppTheme.caveat(12).monospacedDigit())
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let best = evidence.best {
                HStack(spacing: 4) {
                    Text("Best: \(best)")
                        .font(AppTheme.caveat(12).monospacedDigit())
                        .foregroundStyle(AppTheme.textPrimary)
                    if !evidence.lastSets.isEmpty {
                        Image(systemName: EvidenceFormat.trendSymbol(evidence.trend))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(EvidenceFormat.trendColor(evidence.trend))
                            .accessibilityLabel(EvidenceFormat.trendName(evidence.trend))
                    }
                }
            }
            if evidence.source == .engine, !evidence.rationale.isEmpty {
                Text(evidence.rationale)
                    .font(AppTheme.caveat(11))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plan.evidence.\(exerciseIndex)")
    }

    @ViewBuilder
    private var sourceBadge: some View {
        let title = EvidenceFormat.sourceTitle(evidence.source)
        let tint: Color = evidence.source == .engine ? AppTheme.accent : AppTheme.textSecondary
        let label = HStack(spacing: 4) {
            Image(systemName: evidence.source == .engine ? "checkmark.seal" : "sparkles")
                .font(.caption2)
            Text(title)
                .font(AppTheme.caveat(11, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())

        if evidence.guardrailReasons.isEmpty {
            label
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityIdentifier("plan.source.\(exerciseIndex)")
        } else {
            Button { showReasons.toggle() } label: { label }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityHint("Shows why the numbers were adjusted")
                .accessibilityIdentifier("plan.source.\(exerciseIndex)")
        }
    }
}

/// One compact "Last: ..." line for the active-workout header.
struct LastSessionLine: View {
    let evidence: ExerciseEvidence
    let exerciseIndex: Int
    var prefix: String? = nil

    var body: some View {
        if let line = EvidenceFormat.lastLine(evidence) {
            Text((prefix.map { "\($0) · " } ?? "") + line)
                .font(AppTheme.caveat(14).monospacedDigit())
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("workout.last.\(exerciseIndex)")
        }
    }
}

/// "Too easy / About right / Too hard": optional, one tap, saved per exercise.
struct ExerciseFeedbackPicker: View {
    let exercise: Exercise
    let exerciseIndex: Int
    @State private var selection: SessionFeedback?

    private let options: [(SessionFeedback, String, String)] = [
        (.tooEasy, "Too easy", "easy"),
        (.aboutRight, "About right", "right"),
        (.tooHard, "Too hard", "hard")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("How did \(exercise.name) feel?")
                .font(AppTheme.caveat(13))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 6) {
                ForEach(options, id: \.0) { option, title, key in
                    Button { choose(option) } label: {
                        Text(title)
                            .font(AppTheme.caveat(14, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(selection == option ? AppTheme.onAccent : AppTheme.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                            .background(selection == option ? AppTheme.accent : AppTheme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("feedback.\(exerciseIndex).\(key)")
                    .accessibilityValue(selection == option ? "Selected" : "")
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
                }
            }
        }
        .onAppear { selection = ExerciseFeedbackStore.shared.feedback(forExercise: exercise.id) }
    }

    private func choose(_ option: SessionFeedback) {
        // Tapping the chosen answer again clears it.
        let next: SessionFeedback? = selection == option ? nil : option
        selection = next
        ExerciseFeedbackStore.shared.set(next, forExercise: exercise.id)
    }
}
