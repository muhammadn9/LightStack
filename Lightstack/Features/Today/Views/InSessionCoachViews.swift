import SwiftUI

/// What the athlete did with an in-session suggestion.
enum MissDecisionState: Equatable {
    case applied(text: String, message: String)
    case kept
}

/// Inline banner under an exercise when a set fell short: offers lighter weights for the sets
/// still to come and asks (optionally) what got in the way. Never blocks logging.
struct InSessionMissBanner: View {
    let exerciseIndex: Int
    let suggestion: InSessionAdjuster.Suggestion
    let decision: MissDecisionState?
    let chosenReason: MissReason?
    let onApply: () -> Void
    let onKeep: () -> Void
    let onReason: (MissReason) -> Void
    let onDismiss: () -> Void

    private var prefix: String { "session.missBanner.\(exerciseIndex)" }

    /// After Apply the message stays as it was when the athlete tapped (the live suggestion moves on).
    private var displayMessage: String {
        if case .applied(_, let message) = decision { return message }
        return Self.message(for: suggestion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppTheme.warning)
                    .padding(.top, 2)
                Text(displayMessage)
                    .font(AppTheme.caveat(14, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("\(prefix).message")
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
                .accessibilityIdentifier("\(prefix).dismiss")
            }

            decisionRow

            VStack(alignment: .leading, spacing: 4) {
                Text(chosenReason.map { "Noted: \($0.title)" } ?? suggestion.question)
                    .font(AppTheme.caveat(12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .accessibilityIdentifier("session.missReason.\(exerciseIndex).status")
                if chosenReason == nil {
                    FlowLayout(spacing: 6) {
                        ForEach(suggestion.reasons, id: \.self) { reason in
                            Button { onReason(reason) } label: {
                                Text(reason.title)
                                    .font(AppTheme.caveat(13, weight: .bold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(AppTheme.surfaceElevated, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("session.missReason.\(exerciseIndex).\(reason.rawValue)")
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.warning.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.warning.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(prefix)
    }

    @ViewBuilder
    private var decisionRow: some View {
        switch decision {
        case .applied(let text, _):
            Label(text, systemImage: "checkmark.circle.fill")
                .font(AppTheme.caveat(13, weight: .bold))
                .foregroundStyle(AppTheme.success)
                .accessibilityIdentifier("\(prefix).applied")
        case .kept:
            Label("Keeping the plan as written", systemImage: "checkmark")
                .font(AppTheme.caveat(13))
                .foregroundStyle(AppTheme.textSecondary)
                .accessibilityIdentifier("\(prefix).kept")
        case nil:
            if !suggestion.changes.isEmpty {
                HStack(spacing: 10) {
                    Button(action: onApply) {
                        Text("Apply")
                            .font(AppTheme.caveat(14, weight: .bold))
                            .foregroundStyle(AppTheme.onAccent)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 6)
                            .background(AppTheme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(prefix).apply")
                    Button(action: onKeep) {
                        Text("Keep")
                            .font(AppTheme.caveat(14, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 6)
                            .background(AppTheme.surfaceElevated, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(prefix).keep")
                }
            }
        }
    }

    // MARK: - Text

    static func weightText(_ weight: Double) -> String { String(format: "%g", weight) }

    private static func changeName(_ change: InSessionAdjuster.SetChange) -> String {
        switch change.role {
        case .backoff: return "back-off"
        case .top: return "top set"
        default: return "set \(change.index + 1)"
        }
    }

    /// "Top set fell short by 2 reps. Ease the back-off to 145?"
    static func message(for s: InSessionAdjuster.Suggestion) -> String {
        let who = s.role == .straight ? "That set" : s.role.label
        let what = s.rirZero && s.shortBy < InSessionAdjuster.repShortfall
            ? "went to failure"
            : "fell short by \(s.shortBy) rep\(s.shortBy == 1 ? "" : "s")"
        var text = "\(who) \(what)."
        if s.changes.count == 1, let c = s.changes.first {
            text += " Ease the \(changeName(c)) to \(weightText(c.weight))?"
        } else if s.changes.count > 1 {
            text += " Ease the rest to " + s.changes.map { weightText($0.weight) }.joined(separator: " / ") + "?"
        }
        return text
    }

    /// "Eased back-off to 145" shown once applied.
    static func appliedText(for s: InSessionAdjuster.Suggestion) -> String {
        if s.changes.count == 1, let c = s.changes.first {
            return "Eased the \(changeName(c)) to \(weightText(c.weight))"
        }
        return "Eased the rest to " + s.changes.map { weightText($0.weight) }.joined(separator: " / ")
    }
}

/// Subtle nudge after a working set was logged without RIR. Never blocks logging.
struct RirNudgeHint: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lightbulb")
                .font(.system(size: 11))
            Text("Add RIR — it's the most important signal")
                .font(AppTheme.caveat(12))
        }
        .foregroundStyle(AppTheme.textSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("session.rirNudge")
    }
}
