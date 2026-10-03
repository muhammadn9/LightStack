import SwiftUI

/// Lists the coach's suggested workout changes, one card per modification,
/// with Apply / Cancel. Replaces a dense single-paragraph alert.
struct ModificationConfirmationSheet: View {
    let modifications: [WorkoutModification]
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("The coach suggested these changes to your session.")
                        .font(AppTheme.caveat(14))
                        .foregroundStyle(AppTheme.textSecondary)

                    ForEach(Array(modifications.enumerated()), id: \.offset) { _, modification in
                        ModificationCard(modification: modification)
                    }
                }
                .padding(AppTheme.cardPadding)
            }
            .themedBackground()
            .navigationTitle("Review Changes")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button(action: onApply) {
                        Text("Apply Changes")
                            .font(AppTheme.caveat(18, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                            .foregroundStyle(.white)
                            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    }
                    .accessibilityHint("Applies all suggested changes to your workout")

                    Button("Cancel", action: onCancel)
                        .font(AppTheme.caveat(16))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minTouchSize)
                }
                .padding(.horizontal, AppTheme.cardPadding)
                .padding(.bottom, 8)
                .background(.bar)
            }
        }
    }
}

private struct ModificationCard: View {
    let modification: WorkoutModification

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(modification.title)
                .font(AppTheme.caveat(18, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(modification.detailLines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityHidden(true)
                    Text(line)
                        .font(AppTheme.caveat(15))
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let note = modification.noteText {
                Text(note)
                    .font(AppTheme.caveat(13))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [modification.title.replacingOccurrences(of: " · ", with: ", ")]
        parts.append(contentsOf: modification.detailLines)
        if let note = modification.noteText { parts.append("Note: \(note)") }
        return parts.joined(separator: ". ")
    }
}
