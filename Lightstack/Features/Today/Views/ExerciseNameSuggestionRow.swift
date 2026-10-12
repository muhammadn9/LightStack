import SwiftUI

/// "You've logged Leg Extension before — use that?" shown when a typed exercise
/// name closely matches one the user already has history under.
struct ExerciseNameSuggestionRow: View {
    let existingName: String
    let onUse: () -> Void
    let onKeep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            (Text("You've logged ")
                + Text(existingName).bold()
                + Text(" before — use that?"))
                .font(AppTheme.caveat(16))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("nameSuggestion.text")

            HStack(spacing: 10) {
                Button(action: onUse) {
                    Text("Use")
                        .font(AppTheme.playfairItalic(15, weight: .bold))
                        .foregroundStyle(AppTheme.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityIdentifier("nameSuggestion.use")

                Button(action: onKeep) {
                    Text("Keep mine")
                        .font(AppTheme.playfairItalic(15, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.accent.opacity(0.4), lineWidth: 1))
                }
                .accessibilityIdentifier("nameSuggestion.keep")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.accent.opacity(0.4), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nameSuggestion.row")
    }
}
